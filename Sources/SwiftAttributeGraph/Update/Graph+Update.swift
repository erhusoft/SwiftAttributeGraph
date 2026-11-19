/// One entry of the update stack: a node being brought up to date and the next input edge to verify.
///
/// Resuming at `next` instead of rescanning the inputs is the update-stack idea of Compute (`UpdateStack`).
struct UpdateFrame {
    var node: UInt32
    /// A nonnegative input cursor, or `-1` while a resumable rule is suspended.
    var next: Int
    /// Remembers whether an earlier input edge already had a changed version when the frame leaves to update a later
    /// dirty input edge.
    var inputChanged = false
    /// Fits the original frame's padding on 64-bit platforms; no source is freed while an update is active.
    var waiting: UInt32 = Graph.noNode
    /// Cooperative cancellation flag set by `Graph.cancelUpdate()`.
    var isCancelled = false
}

extension Graph {
    // MARK: Cancellation

    /// Cooperatively marks all active frames on the current update stack as cancelled.
    public func cancelUpdate() {
        assertOwnThread()
        precondition(!frames.isEmpty, "cancelUpdate: no update is currently running")
        for index in frames.indices {
            if frames[index].isCancelled { continue }
            frames[index].isCancelled = true
        }
    }

    /// Whether the current update frame has been marked cancelled via ``cancelUpdate()``.
    public var updateWasCancelled: Bool {
        assertOwnThread()
        precondition(!frames.isEmpty, "updateWasCancelled: no update is currently running")
        return frames[frames.count - 1].isCancelled
    }

    @inline(__always)
    var isCurrentFrameCancelled: Bool {
        !frames.isEmpty && frames[frames.count - 1].isCancelled
    }

    // MARK: Reading

    /// The value of an attribute, bringing it up to date first if it is dirty.
    ///
    /// Inside a rule the read is recorded as a dependency of that rule.
    public func value<Value>(of attribute: Attribute<Value>) -> Value {
        assertOwnThread()
        if let running = ThreadLocalGraph.current() {
            precondition(running === self, "a rule cannot read an attribute of another graph")
        }
        flushUpdateCallbackIfReady()
        return read(attribute)
    }

    /// The read itself, for callers that already know the running graph is this one (`Attribute.value` found it in
    /// the thread-local slot, so it skips the second lookup).
    @inline(__always)
    func read<Value>(_ attribute: Attribute<Value>) -> Value {
        precondition(table.isLive(attribute.id), "reading a dead attribute (its subgraph was invalidated)")
        let index = attribute.id.index
        let n = Int(index)

        // An indirect attribute redirects to another attribute: bringing the indirect up to date updates its source,
        // and the reader records a single dependency edge on the indirect attribute itself.
        if table.state[n] & NodeState.indirect != 0 {
            if table.state[n] & NodeState.dirty != 0 {
                precondition(!isResumingStep, "a resumable rule must poll a dirty input and return needsInput")
                update(index)
            }
            if evaluatingNode != Graph.noNode { recordRead(of: index) }
            if let reader = offsetFieldReaders[index] {
                guard let result = reader() as? Value else {
                    preconditionFailure("offsetFieldReaders: projected field type mismatch")
                }
                return result
            }
            let resolved = resolveIndirect(attribute)
            if let reader = offsetFieldReaders[resolved.id.index] {
                guard let result = reader() as? Value else {
                    preconditionFailure("offsetFieldReaders: projected field type mismatch")
                }
                if evaluatingNode == Graph.noNode && !deferredInvalidations.isEmpty { flushDeferredInvalidations() }
                return result
            }
            if table.state[Int(resolved.id.index)] & NodeState.dirty != 0 {
                precondition(!isResumingStep, "a resumable rule must poll a dirty input and return needsInput")
                update(resolved.id.index)
            }
            let value = typedNode(resolved).value.unsafelyUnwrapped
            if evaluatingNode == Graph.noNode && !deferredInvalidations.isEmpty { flushDeferredInvalidations() }
            return value
        }

        if table.state[n] & NodeState.dirty != 0 {
            precondition(!isResumingStep, "a resumable rule must poll a dirty input and return needsInput")
            update(index)
        }
        if evaluatingNode != Graph.noNode { recordRead(of: index) }
        let value = typedNode(attribute).value.unsafelyUnwrapped
        if evaluatingNode == Graph.noNode && !deferredInvalidations.isEmpty { flushDeferredInvalidations() }
        return value
    }

    /// Runs `body` without recording dependency edges on the currently evaluating rule (`Graph.withoutUpdate` in
    /// native AttributeGraph).
    ///
    /// Dirty attributes read inside `body` still evaluate normally to produce their up-to-date value, but no edge is
    /// added from those attributes to the outer rule.
    public func withoutUpdate<T>(_ body: () -> T) -> T {
        assertOwnThread()
        let previousNode = evaluatingNode
        let previousResuming = isResumingStep
        evaluatingNode = Graph.noNode
        isResumingStep = false
        defer {
            evaluatingNode = previousNode
            isResumingStep = previousResuming
        }
        return body()
    }

    /// Static convenience for ``withoutUpdate(_:)-5k18s`` that uses the graph whose rule is currently running on this
    /// thread (or runs `body` directly if no rule is running).
    public static func withoutUpdate<T>(_ body: () -> T) -> T {
        guard let graph = ThreadLocalGraph.current() else {
            return body()
        }
        return graph.withoutUpdate(body)
    }

    /// Whether `attribute` currently holds a computed or initial value (`Attribute.hasValue` in native
    /// AttributeGraph).
    ///
    /// Inputs and indirect attributes always report `true`; rules report `false` until they have completed their first
    /// evaluation.
    public func hasValue<Value>(of attribute: Attribute<Value>) -> Bool {
        hasValue(of: attribute.erased)
    }

    /// Whether `attribute` currently holds a computed or initial value (`AnyAttribute.hasValue` in native
    /// AttributeGraph).
    public func hasValue(of attribute: AnyAttribute) -> Bool {
        assertOwnThread()
        precondition(table.isLive(attribute.id), "hasValue(of:): the attribute is dead")
        return table.state[Int(attribute.id.index)] & NodeState.hasValue != 0
    }

    /// Brings `attribute` up to date if it is dirty, without recording a dependency edge on any currently running rule
    /// (`Attribute.updateValue()` in native AttributeGraph).
    public func updateValue<Value>(of attribute: Attribute<Value>) {
        updateValue(of: attribute.erased)
    }

    /// Brings `attribute` up to date if it is dirty, without recording a dependency edge on any currently running rule
    /// (`AnyAttribute.updateValue()` in native AttributeGraph).
    public func updateValue(of attribute: AnyAttribute) {
        assertOwnThread()
        precondition(table.isLive(attribute.id), "updateValue(of:): the attribute is dead")
        let index = attribute.id.index
        let n = Int(index)
        withoutUpdate {
            if table.state[n] & NodeState.dirty != 0 {
                update(index)
            }
            if table.state[n] & NodeState.indirect != 0 {
                var current = attribute.id
                while table.isLive(current), table.state[Int(current.index)] & NodeState.indirect != 0 {
                    let box = table.box(at: current.index) as! AnyIndirectNode
                    current = box.source
                }
                if table.isLive(current), table.state[Int(current.index)] & NodeState.dirty != 0 {
                    update(current.index)
                }
            }
        }
        if evaluatingNode == Graph.noNode && !deferredInvalidations.isEmpty { flushDeferredInvalidations() }
    }

    /// Asserts that `attribute` is alive and structurally valid in the graph (`Attribute.validate()` in native
    /// AttributeGraph). Does not evaluate dirty rules or record dependency edges.
    public func validate<Value>(_ attribute: Attribute<Value>) {
        validate(attribute.erased)
    }

    /// Asserts that `attribute` is alive and structurally valid in the graph (`AnyAttribute.validate()` in native
    /// AttributeGraph). Does not evaluate dirty rules or record dependency edges.
    public func validate(_ attribute: AnyAttribute) {
        assertOwnThread()
        precondition(table.isLive(attribute.id), "validate(_:): the attribute is dead")
    }

    /// Marks a rule attribute dirty and pending so it is forced to re-evaluate on its next read even if none of its
    /// inputs changed (`Attribute.invalidateValue()` in native AttributeGraph), and propagates dirty to its readers.
    public func invalidateValue<Value>(of attribute: Attribute<Value>) {
        invalidateValue(of: attribute.erased)
    }

    /// Marks a rule attribute dirty and pending so it is forced to re-evaluate on its next read even if none of its
    /// inputs changed (`AnyAttribute.invalidateValue()` in native AttributeGraph), and propagates dirty to its readers.
    public func invalidateValue(of attribute: AnyAttribute) {
        assertOwnThread()
        precondition(table.isLive(attribute.id), "invalidateValue(of:): the attribute is dead")
        let index = attribute.id.index
        let n = Int(index)
        precondition(table.state[n] & NodeState.isRule != 0, "invalidateValue(of:): only rule attributes can be invalidated")
        let wasDirty = table.state[n] & NodeState.dirty != 0
        table.state[n] |= NodeState.dirty | NodeState.pending
        if !wasDirty && (table.state[n] & NodeState.observed != 0) {
            queueNotification(index)
        }
        propagateDirty(from: index)
        flushNotifications()
    }

    /// Mutates the stored ``Rule`` or ``StatefulRule`` body of `attribute` in place (`Attribute.mutateBody` in native
    /// AttributeGraph).
    ///
    /// When `invalidating` is `true`, ``invalidateValue(of:)-(Attribute<Value>)`` is called after `body` finishes so
    /// the attribute and its readers are marked dirty and the rule is forced to re-run on its next read. When
    /// `invalidating` is `false`, the attribute's dirty state is left untouched.
    public func mutateBody<R, Value>(of attribute: Attribute<Value>, as type: R.Type, invalidating: Bool,
                                     _ body: (inout R) -> Void) {
        assertOwnThread()
        precondition(table.isLive(attribute.id), "mutateBody(of:as:invalidating:_:): the attribute is dead")
        let box = table.box(at: attribute.id.index)
        guard box.mutateRuleBody(as: type, body) else {
            preconditionFailure("mutateBody(of:as:invalidating:_:): the attribute does not hold a rule of type \(R.self)")
        }
        if invalidating {
            invalidateValue(of: attribute)
        }
    }

    // MARK: Writing

    /// Writes a new value into an input attribute. If it counts as equal under the attribute's comparison policy,
    /// nothing happens; otherwise the version rises, the readers are marked dirty and observers are notified.
    public func setValue<Value>(_ value: Value, for attribute: Attribute<Value>) {
        assertOwnThread()
        precondition(evaluatingNode == Graph.noNode, "setValue(_:for:): a rule must not write to the graph")
        precondition(table.isLive(attribute.id), "setValue(_:for:): the attribute is dead (its subgraph was invalidated)")
        let index = Int(attribute.id.index)
        precondition(table.state[index] & NodeState.isRule == 0, "setValue(_:for:): cannot write to a rule")

        // An indirect attribute redirects to another attribute: writing it writes to the terminal source.
        if table.state[index] & NodeState.indirect != 0 {
            precondition(offsetFieldReaders[attribute.id.index] == nil,
                         "setValue(_:for:): cannot write to an offset-field attribute")
            setValue(value, for: resolveIndirect(attribute))
            return
        }

        let oldValue = typedNode(attribute).value
        guard typedNode(attribute).store(value) else { return }
        globalVersion &+= 1
        table.versions[index] &+= 1
        if table.state[index] & NodeState.observed != 0 { queueNotification(UInt32(index)) }
        if let oldValue {
            evaluateEdgeComparators(for: UInt32(index), oldValue: oldValue, newValue: value)
        }
        propagateDirty(from: UInt32(index))
        flushNotifications()
    }

    // MARK: Updating

    /// Brings a dirty node up to date with an explicit stack: no recursion that depends on the graph's depth.
    ///
    /// A dirty node verifies all its previous input edges in ascending attribute index order, bringing dirty rules up
    /// to date first. Only then, if any input's version differs from the one it saw (or the node never ran or lost an
    /// input), does its own rule run. If no input changed, the rule is skipped and the node is marked clean.
    ///
    /// A rule that reads an input it did not read before reaches this function again from inside the rule; that
    /// nested call still uses the native stack and is the documented limit that M4 removes.
    func update(_ root: UInt32) {
        let base = frames.count
        push(root)
        outer: while frames.count > base {
            let top = frames.count - 1
            let node = frames[top].node
            let n = Int(node)
            if frames[top].isCancelled {
                table.state[n] = (table.state[n] & ~NodeState.evaluating) | NodeState.dirty | NodeState.pending
                frames.removeLast()
                continue
            }
            if frames[top].next < 0 {
                advanceResumable(top: top, firstStep: false)
                continue
            }
            var mustRun = table.state[n] & NodeState.hasValue == 0 || table.state[n] & NodeState.pending != 0
                || frames[top].inputChanged

            var i = frames[top].next
            while i < table.inputs[n].count {
                let edge = table.inputs[n][i]
                let source = Int(edge.source)
                if table.state[source] & NodeState.dirty != 0 {
                    frames[top].next = i
                    frames[top].inputChanged = mustRun
                    push(edge.source)
                    continue outer
                }
                if table.versions[source] != edge.seenVersion {
                    if edgeComparators[node]?[edge.source] != nil || hasOffsetInChain(edge.source) {
                        if stickyChangedEdges[node]?.contains(edge.source) == true {
                            mustRun = true
                        } else {
                            table.inputs[n][i].seenVersion = table.versions[source]
                        }
                    } else {
                        mustRun = true
                    }
                }
                i += 1
            }

            if table.state[n] & NodeState.indirect != 0 {
                if let box = table.box(at: node) as? AnyIndirectNode {
                    let s = Int(box.source.index)
                    if table.state[s] & NodeState.dirty != 0 {
                        frames[top].next = table.inputs[n].count
                        frames[top].inputChanged = mustRun
                        push(box.source.index)
                        continue outer
                    }
                    let currentSourceVersion = table.versions[s]
                    let sourceChanged = box.sourceRedirected || currentSourceVersion != box.sourceSeenVersion
                    box.sourceSeenVersion = currentSourceVersion
                    box.sourceRedirected = false
                    for idx in table.inputs[n].indices {
                        let edgeSource = Int(table.inputs[n][idx].source)
                        table.inputs[n][idx].seenVersion = table.versions[edgeSource]
                    }
                    if sourceChanged {
                        globalVersion &+= 1
                        table.versions[n] &+= 1
                    }
                }
                table.state[n] &= ~(NodeState.dirty | NodeState.evaluating | NodeState.pending)
                frames.removeLast()
                continue
            }

            if mustRun {
                if table.state[n] & NodeState.resumable != 0 {
                    advanceResumable(top: top, firstStep: true)
                    continue
                }
                run(node)
            } else {
                table.state[n] &= ~(NodeState.dirty | NodeState.evaluating)
            }
            frames.removeLast()
        }
    }

    func push(_ node: UInt32) {
        let n = Int(node)
        precondition(table.state[n] & NodeState.evaluating == 0,
                     "cycle detected: an attribute depends on itself through its own rule")
        table.state[n] |= NodeState.evaluating
        frames.append(UpdateFrame(node: node, next: 0))
    }

    /// Runs the rule of a node, rebuilds its input edges from what it read and bumps its version if the value changed.
    private func run(_ node: UInt32) {
        let n = Int(node)
        let stateful = table.state[n] & NodeState.stateful != 0
        if stateful {
            for i in table.inputs[n].indices {
                let edge = table.inputs[n][i]
                table.inputs[n][i].read = false
                table.inputs[n][i].changed = table.versions[Int(edge.source)] != edge.seenVersion
            }
        } else {
            for i in table.inputs[n].indices { table.inputs[n][i].read = false }
        }

        let previousNode = evaluatingNode
        evaluatingNode = node
        let previousGraph = ThreadLocalGraph.install(self)
        let previousSubgraph = currentSubgraph
        let owner = table.owner(at: node)
        if !subgraphs.isLive(currentSubgraph) || subgraphs.isFalling(index: currentSubgraph.index) {
            currentSubgraph = subgraphForCreating(in: owner)
        }

        recalculationCount &+= 1
        let changed = table.box(at: node).evaluate(in: self, node: node)

        currentSubgraph = previousSubgraph
        _ = ThreadLocalGraph.install(previousGraph)
        evaluatingNode = previousNode

        if !frames.isEmpty, frames[frames.count - 1].isCancelled {
            table.state[n] = (table.state[n] & ~NodeState.evaluating) | NodeState.dirty | NodeState.pending
            return
        }

        pruneEdges(of: node)
        table.state[n] = (table.state[n] & ~(NodeState.dirty | NodeState.evaluating | NodeState.pending))
            | NodeState.hasValue
        if changed {
            globalVersion &+= 1
            table.versions[n] &+= 1
        } else {
            for dependent in table.outputs[n] {
                let dep = Int(dependent)
                if table.state[dep] & NodeState.dirty != 0,
                   table.state[dep] & (NodeState.pending | NodeState.stateful) == 0,
                   table.inputs[dep].count == 1,
                   table.inputs[dep][0].source == node,
                   table.inputs[dep][0].seenVersion == table.versions[n] {
                    table.state[dep] &= ~NodeState.dirty
                }
            }
        }
    }

    /// Where a running rule creates attributes when the caller's current subgraph is being invalidated: the subgraph
    /// that owns the rule (observed in native AttributeGraph), or, when that one is falling too, its nearest ancestor
    /// that is not (kept from M5; not observed natively). With a live caller subgraph, rules create there: evaluating a
    /// rule does not change the current subgraph, as in native AttributeGraph.
    func subgraphForCreating(in owner: UInt32) -> SubgraphID {
        if !subgraphs.isFalling(index: owner) {
            return subgraphs.id(at: owner)
        }
        var queue: [UInt32] = subgraphs.parents(of: owner)
        var visited: Set<UInt32> = [owner]
        var head = 0
        while head < queue.count {
            let candidate = queue[head]
            head += 1
            if !visited.insert(candidate).inserted { continue }
            if !subgraphs.isFalling(index: candidate) {
                return subgraphs.id(at: candidate)
            }
            for p in subgraphs.parents(of: candidate) where !visited.contains(p) {
                queue.append(p)
            }
        }
        return rootSubgraph.id
    }

    // MARK: What changed (for stateful rules)

    /// Whether the edge from `source` into `node` was changed when the node's run began; `nil` if there is no such edge.
    @inline(__always)
    @usableFromInline
    func inputChanged(of node: UInt32, source: UInt32) -> Bool? {
        let edges = table.inputs[Int(node)]
        var low = 0, high = edges.count
        while low < high {
            let mid = (low + high) >> 1
            let midSource = edges[mid].source
            if midSource == source { return edges[mid].changed }
            if midSource < source { low = mid + 1 } else { high = mid }
        }
        return nil
    }

    /// Whether any input edge of `node` was changed, ignoring `excluded`. Every input counts on the first run.
    @usableFromInline func anyInputChanged(of node: UInt32, excluding excluded: [UInt32]) -> Bool {
        let n = Int(node)
        if table.state[n] & NodeState.hasValue == 0 { return true }
        for edge in table.inputs[n] where edge.changed && !excluded.contains(edge.source) { return true }
        return false
    }

    // MARK: Tracking

    /// Records that the running rule read `source`. Edges are kept sorted by ascending `source` index; edges not
    /// marked `read` when the rule ends are pruned by `pruneEdges(of:)`.
    @usableFromInline func recordRead(of source: UInt32) {
        let consumer = Int(evaluatingNode)
        precondition(source != evaluatingNode, "a rule cannot read itself")
        let version = table.versions[Int(source)]
        let count = table.inputs[consumer].count

        if count == 0 || table.inputs[consumer][count - 1].source < source {
            table.outputs[Int(source)].append(evaluatingNode)
            let position = UInt32(table.outputs[Int(source)].count - 1)
            table.inputs[consumer].append(InputEdge(source: source, seenVersion: version, read: true,
                                                    positionInOutputs: position))
            return
        }

        var low = 0, high = count
        while low < high {
            let mid = (low + high) >> 1
            if table.inputs[consumer][mid].source < source {
                low = mid + 1
            } else {
                high = mid
            }
        }

        if low < count, table.inputs[consumer][low].source == source {
            table.inputs[consumer][low].read = true
            table.inputs[consumer][low].seenVersion = version
            return
        }

        table.outputs[Int(source)].append(evaluatingNode)
        let position = UInt32(table.outputs[Int(source)].count - 1)
        table.inputs[consumer].insert(InputEdge(source: source, seenVersion: version, read: true,
                                                positionInOutputs: position), at: low)
    }

    /// Removes the edges that the rule did not read in its last run (mark-and-sweep preserving ascending `source` order).
    func pruneEdges(of node: UInt32) {
        let n = Int(node)
        let count = table.inputs[n].count
        var writeIndex = 0
        for readIndex in 0..<count {
            let edge = table.inputs[n][readIndex]
            if edge.read {
                if writeIndex != readIndex {
                    table.inputs[n][writeIndex] = edge
                }
                writeIndex += 1
            } else {
                edgeComparators[node]?.removeValue(forKey: edge.source)
                stickyChangedEdges[node]?.remove(edge.source)
                removeOutput(node, from: edge.source, at: edge.positionInOutputs)
            }
        }
        if writeIndex < count {
            table.inputs[n].removeSubrange(writeIndex..<count)
        }
    }

    /// Removes `dependent` from the output list of `source` at the given position (swap with the last: the list has
    /// no order). The position must be the position of `dependent` in `outputs[source]`, as recorded in the edge's
    /// `positionInOutputs`. O(1) instead of O(degree).
    func removeOutput(_ dependent: UInt32, from source: UInt32, at position: UInt32) {
        let s = Int(source)
        let p = Int(position)
        guard p < table.outputs[s].count else { return }
        let last = table.outputs[s].count - 1
        if p != last {
            let movedNode = table.outputs[s][last]
            table.outputs[s][p] = movedNode
            // Keep the moved node's edge position up to date.
            updatePositionInOutputs(movedNode, from: source, to: UInt32(p))
        }
        table.outputs[s].removeLast()
        parkCachedNodeIfUnreferenced(source)
    }

    /// Finds the edge of `node` that reads `source` and updates its `positionInOutputs` to `position`.
    /// O(log(number of inputs of `node`)).
    @inline(__always)
    func updatePositionInOutputs(_ node: UInt32, from source: UInt32, to position: UInt32) {
        let n = Int(node)
        var low = 0, high = table.inputs[n].count
        while low < high {
            let mid = (low + high) >> 1
            let midSource = table.inputs[n][mid].source
            if midSource == source {
                table.inputs[n][mid].positionInOutputs = position
                return
            }
            if midSource < source { low = mid + 1 } else { high = mid }
        }
    }
}
