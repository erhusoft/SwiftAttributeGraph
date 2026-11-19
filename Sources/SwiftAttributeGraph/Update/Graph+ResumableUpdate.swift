extension Graph {
    /// Advances a resumable frame after its old inputs, or its requested input, have been brought up to date.
    func advanceResumable(top: Int, firstStep: Bool) {
        let node = frames[top].node
        let n = Int(node)
        if firstStep {
            for i in table.inputs[n].indices {
                let edge = table.inputs[n][i]
                table.inputs[n][i].read = false
                table.inputs[n][i].changed = table.versions[Int(edge.source)] != edge.seenVersion
            }
        }

        let previousNode = evaluatingNode
        let previousSubgraph = currentSubgraph
        let previouslyResuming = isResumingStep
        let previousGraph = ThreadLocalGraph.install(self)
        evaluatingNode = node
        let owner = table.owner(at: node)
        if !subgraphs.isLive(currentSubgraph) || subgraphs.isFalling(index: currentSubgraph.index) {
            currentSubgraph = subgraphForCreating(in: owner)
        }
        if frames[top].waiting != Graph.noNode { recordRead(of: frames[top].waiting) }
        isResumingStep = true
        let id = AttributeID(index: node, generation: table.generations[n])
        let outcome = table.box(at: node).resume(in: self, node: id, firstStep: firstStep)
        isResumingStep = previouslyResuming
        evaluatingNode = previousNode
        currentSubgraph = previousSubgraph
        _ = ThreadLocalGraph.install(previousGraph)

        if frames[top].isCancelled {
            table.state[n] = (table.state[n] & ~NodeState.evaluating) | NodeState.dirty | NodeState.pending
            frames.removeLast()
            return
        }

        switch outcome.step {
        case .needsInput(let attribute):
            precondition(table.isLive(attribute.id), "needsInput: the attribute is dead")
            let source = attribute.id.index
            precondition(table.state[Int(source)] & NodeState.dirty != 0,
                         "needsInput requires a dirty input; poll a ready value instead")
            frames[top].next = -1
            frames[top].waiting = source
            push(source)
        case .finished:
            recalculationCount &+= 1
            pruneEdges(of: node)
            table.state[n] = (table.state[n] & ~(NodeState.dirty | NodeState.evaluating | NodeState.pending))
                | NodeState.hasValue
            if outcome.changed {
                globalVersion &+= 1
                changeCount &+= 1
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
            frames.removeLast()
        }
    }
}
