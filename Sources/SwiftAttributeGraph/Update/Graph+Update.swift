/// One entry of the update stack: a node being brought up to date and the next input edge to verify.
///
/// Resuming at `next` instead of rescanning the inputs is the update-stack idea of Compute (`UpdateStack`).
struct UpdateFrame {
    var node: UInt32
    var next: Int
    /// A stateful rule keeps scanning after it found an input that changed; if it then has to bring a later input up
    /// to date, the frame is left and resumed, so what it found is kept here.
    var inputChanged = false
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
        if table.state[Int(index)] & NodeState.dirty != 0 { update(index) }
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
        guard typedNode(attribute).store(value) else { return }
        table.versions[index] &+= 1
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
                run(node)
            } else {
                table.state[n] &= ~(NodeState.dirty | NodeState.evaluating)
            }
            frames.removeLast()
        }
    }

    private func push(_ node: UInt32) {
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

        let changed = table.box(at: node).evaluate(in: self, node: node)

        currentSubgraph = previousSubgraph
        _ = ThreadLocalGraph.install(previousGraph)
        let cursor = trackCursor
        evaluatingNode = previousNode
        trackCursor = previousCursor

        pruneEdges(of: node, keeping: cursor)
        table.state[n] = (table.state[n] & ~(NodeState.dirty | NodeState.evaluating | NodeState.pending))
            | NodeState.hasValue
        if changed { table.versions[n] &+= 1 }
    }

    /// Where what a rule creates is born: the subgraph that owns the rule, or its nearest ancestor that is not being
    /// invalidated (a rule of a falling subgraph may still run in the same update).
    private func subgraphForCreating(in owner: UInt32) -> SubgraphID {
        var index = owner
        while subgraphs.isFalling(index: index), let parent = subgraphs.parent(of: subgraphs.id(at: index)) {
            index = parent.index
        }
        return subgraphs.id(at: index)
    }

    // MARK: What changed (for stateful rules)

    /// Whether the edge from `source` into `node` was changed when the node's run began; `nil` if there is no such edge.
    @inline(__always)
    func inputChanged(of node: UInt32, source: UInt32) -> Bool? {
        for edge in table.inputs[Int(node)] where edge.source == source { return edge.changed }
        return nil
    }

    /// Whether any input edge of `node` was changed, ignoring `excluded`. Every input counts on the first run.
    func anyInputChanged(of node: UInt32, excluding excluded: [UInt32]) -> Bool {
        let n = Int(node)
        if table.state[n] & NodeState.hasValue == 0 { return true }
        for edge in table.inputs[n] where edge.changed && !excluded.contains(edge.source) { return true }
        return false
    }

    // MARK: Tracking

    /// Records that the running rule read `source`. Edges stay in read order: a read moves its edge to the cursor,
    /// and whatever is left after the cursor when the rule ends was not read and is pruned.
    func recordRead(of source: UInt32) {
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

        table.inputs[consumer].insert(InputEdge(source: source, seenVersion: version, read: true), at: trackCursor)
        trackCursor += 1
        table.outputs[Int(source)].append(evaluatingNode)
    }

    /// Removes the edges after `cursor`: the ones the rule did not read in its last run.
    private func pruneEdges(of node: UInt32, keeping cursor: Int) {
        let n = Int(node)
        guard cursor < table.inputs[n].count else { return }
        for edge in table.inputs[n][cursor...] { removeOutput(node, from: edge.source) }
        table.inputs[n].removeSubrange(cursor...)
    }

    /// Removes `dependent` from the output list of `source` (swap with the last: the list has no order).
    func removeOutput(_ dependent: UInt32, from source: UInt32) {
        let s = Int(source)
        if let position = table.outputs[s].firstIndex(of: dependent) {
            table.outputs[s].swapAt(position, table.outputs[s].count - 1)
            table.outputs[s].removeLast()
        }
    }
}
