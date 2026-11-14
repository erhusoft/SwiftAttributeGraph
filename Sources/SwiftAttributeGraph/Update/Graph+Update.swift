/// One entry of the update stack: a node being brought up to date and the next input edge to verify.
///
/// Resuming at `next` instead of rescanning the inputs is the update-stack idea of Compute (`UpdateStack`).
struct UpdateFrame {
    var node: UInt32
    /// A nonnegative input cursor, or `-readCursor - 1` while a resumable rule is suspended.
    var next: Int
    /// A stateful rule keeps scanning after it found an input that changed; if it then has to bring a later input up
    /// to date, the frame is left and resumed, so what it found is kept here.
    var inputChanged = false
    /// Fits the original frame's padding on 64-bit platforms; no source is freed while an update is active.
    var waiting: UInt32 = Graph.noNode
}

extension Graph {
    // MARK: Reading

    /// The value of an attribute, bringing it up to date first if it is dirty.
    ///
    /// Inside a rule the read is recorded as a dependency of that rule.
    public func value<Value>(of attribute: Attribute<Value>) -> Value {
        assertOwnThread()
        if let running = ThreadLocalGraph.current() {
            precondition(running === self, "a rule cannot read an attribute of another graph")
        }
        return read(attribute)
    }

    /// The read itself, for callers that already know the running graph is this one (`Attribute.value` found it in
    /// the thread-local slot, so it skips the second lookup).
    @inline(__always)
    func read<Value>(_ attribute: Attribute<Value>) -> Value {
        precondition(table.isLive(attribute.id), "reading a dead attribute (its subgraph was invalidated)")
        let index = attribute.id.index
        let n = Int(index)

        // An indirect attribute redirects to another attribute: reading it reads the source,
        // so the rule that reads it depends on the source too.
        if table.state[n] & NodeState.indirect != 0 {
            let box = table.box(at: index) as! IndirectNode<Value>
            precondition(table.isLive(box.source), "reading an indirect attribute whose source is dead")
            if evaluatingNode != Graph.noNode { recordRead(of: index) }
            return read(Attribute<Value>(id: box.source))
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

    // MARK: Writing

    /// Writes a new value into an input attribute. If it counts as equal under the attribute's comparison policy,
    /// nothing happens; otherwise the version rises, the readers are marked dirty and observers are notified.
    public func setValue<Value>(_ value: Value, for attribute: Attribute<Value>) {
        assertOwnThread()
        precondition(evaluatingNode == Graph.noNode, "setValue(_:for:): a rule must not write to the graph")
        precondition(table.isLive(attribute.id), "setValue(_:for:): the attribute is dead (its subgraph was invalidated)")
        let index = Int(attribute.id.index)
        precondition(table.state[index] & NodeState.isRule == 0, "setValue(_:for:): cannot write to a rule")

        // An indirect attribute redirects to another attribute: writing it writes to the source.
        if table.state[index] & NodeState.indirect != 0 {
            let box = table.box(at: UInt32(index)) as! IndirectNode<Value>
            precondition(table.isLive(box.source), "writing an indirect attribute whose source is dead")
            setValue(value, for: Attribute<Value>(id: box.source))
            return
        }

        guard typedNode(attribute).store(value) else { return }
        globalVersion &+= 1
        table.versions[index] &+= 1
        table.lastVerified[index] = globalVersion
        if table.state[index] & NodeState.observed != 0 { queueNotification(UInt32(index)) }
        propagateDirty(from: UInt32(index))
        flushNotifications()
    }

    // MARK: Updating

    /// Brings a dirty node up to date with an explicit stack: no recursion that depends on the graph's depth.
    ///
    /// A dirty node verifies its inputs in the order they were read, bringing dirty rules up to date first, and stops
    /// at the first input whose version differs from the one it saw. Only then does its own rule run. If no input
    /// changed, the rule is skipped and the node is just marked clean (the cut by versions).
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
            if frames[top].next < 0 {
                advanceResumable(top: top, firstStep: false)
                continue
            }
            var mustRun = table.state[n] & NodeState.hasValue == 0 || table.state[n] & NodeState.pending != 0
                || frames[top].inputChanged
            // A stateful rule needs every input up to date (to know what changed), so it does not stop at the first
            // input that changed and it does not skip the scan when it must run anyway.
            let stateful = table.state[n] & NodeState.stateful != 0

            if !mustRun || stateful {
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
                    if table.versions[source] != edge.seenVersion { mustRun = true; if !stateful { break } }
                    i += 1
                }
            }

            if mustRun {
                if table.state[n] & NodeState.resumable != 0 {
                    advanceResumable(top: top, firstStep: true)
                    continue
                }
                run(node)
            } else {
                table.state[n] &= ~(NodeState.dirty | NodeState.evaluating)
                table.lastVerified[n] = globalVersion
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
        let previousCursor = trackCursor
        evaluatingNode = node
        trackCursor = 0
        let previousGraph = ThreadLocalGraph.install(self)
        let previousSubgraph = currentSubgraph
        let owner = table.owner(at: node)
        if currentSubgraph.index != owner || subgraphs.isFalling(index: owner) {
            currentSubgraph = subgraphForCreating(in: owner)
        }

        recalculationCount &+= 1
        let changed = table.box(at: node).evaluate(in: self, node: node)

        currentSubgraph = previousSubgraph
        _ = ThreadLocalGraph.install(previousGraph)
        let cursor = trackCursor
        evaluatingNode = previousNode
        trackCursor = previousCursor

        pruneEdges(of: node, keeping: cursor)
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
                    table.lastVerified[dep] = globalVersion
                }
            }
        }
        table.lastVerified[n] = globalVersion
    }

    /// Where what a rule creates is born: the subgraph that owns the rule, or its nearest ancestor that is not being
    /// invalidated (a rule of a falling subgraph may still run in the same update).
    func subgraphForCreating(in owner: UInt32) -> SubgraphID {
        var index = owner
        while subgraphs.isFalling(index: index), let parent = subgraphs.parent(of: subgraphs.id(at: index)) {
            index = parent.index
        }
        return subgraphs.id(at: index)
    }

    // MARK: What changed (for stateful rules)

    /// Whether the edge from `source` into `node` was changed when the node's run began; `nil` if there is no such edge.
    @inline(__always)
    @usableFromInline
    func inputChanged(of node: UInt32, source: UInt32) -> Bool? {
        for edge in table.inputs[Int(node)] where edge.source == source { return edge.changed }
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

    /// Records that the running rule read `source`. Edges stay in read order: a read moves its edge to the cursor,
    /// and whatever is left after the cursor when the rule ends was not read and is pruned.
    @usableFromInline func recordRead(of source: UInt32) {
        let consumer = Int(evaluatingNode)
        precondition(source != evaluatingNode, "a rule cannot read itself")
        let version = table.versions[Int(source)]
        let count = table.inputs[consumer].count

        if trackCursor < count, table.inputs[consumer][trackCursor].source == source {
            table.inputs[consumer][trackCursor].read = true
            table.inputs[consumer][trackCursor].seenVersion = version
            trackCursor += 1
            return
        }

        var found = -1
        for j in 0..<count where table.inputs[consumer][j].source == source { found = j; break }

        if found >= 0 {
            if found < trackCursor { return }            // read twice in the same run: keep the first position
            var edge = table.inputs[consumer].remove(at: found)
            edge.read = true
            edge.seenVersion = version
            table.inputs[consumer].insert(edge, at: trackCursor)
            trackCursor += 1
            return
        }

        table.outputs[Int(source)].append(evaluatingNode)
        let position = UInt32(table.outputs[Int(source)].count - 1)
        table.inputs[consumer].insert(InputEdge(source: source, seenVersion: version, read: true,
                                                positionInOutputs: position), at: trackCursor)
        trackCursor += 1
    }

    /// Removes the edges after `cursor`: the ones the rule did not read in its last run.
    func pruneEdges(of node: UInt32, keeping cursor: Int) {
        let n = Int(node)
        guard cursor < table.inputs[n].count else { return }
        for edge in table.inputs[n][cursor...] {
            removeOutput(node, from: edge.source, at: edge.positionInOutputs)
        }
        table.inputs[n].removeSubrange(cursor...)
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
    }

    /// Finds the edge of `node` that reads `source` and updates its `positionInOutputs` to `position`.
    /// O(number of inputs of `node`), which is normally small; the costly part (searching `outputs[source]`) is gone.
    @inline(__always)
    func updatePositionInOutputs(_ node: UInt32, from source: UInt32, to position: UInt32) {
        let n = Int(node)
        for i in table.inputs[n].indices where table.inputs[n][i].source == source {
            table.inputs[n][i].positionInOutputs = position
            return
        }
    }
}
