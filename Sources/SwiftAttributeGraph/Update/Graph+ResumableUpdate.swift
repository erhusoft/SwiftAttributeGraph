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
        let previousCursor = trackCursor
        let previousSubgraph = currentSubgraph
        let previouslyResuming = isResumingStep
        let previousGraph = ThreadLocalGraph.install(self)
        evaluatingNode = node
        trackCursor = firstStep ? 0 : -frames[top].next - 1
        let owner = table.owner(at: node)
        if currentSubgraph.index != owner || subgraphs.isFalling(index: owner) {
            currentSubgraph = subgraphForCreating(in: owner)
        }
        if frames[top].waiting != Graph.noNode { recordRead(of: frames[top].waiting) }
        isResumingStep = true
        let id = AttributeID(index: node, generation: table.generations[n])
        let outcome = table.box(at: node).resume(in: self, node: id, firstStep: firstStep)
        let cursor = trackCursor
        isResumingStep = previouslyResuming
        evaluatingNode = previousNode
        trackCursor = previousCursor
        currentSubgraph = previousSubgraph
        _ = ThreadLocalGraph.install(previousGraph)

        switch outcome.step {
        case .needsInput(let attribute):
            precondition(table.isLive(attribute.id), "needsInput: the attribute is dead")
            let source = attribute.id.index
            precondition(table.state[Int(source)] & NodeState.dirty != 0,
                         "needsInput requires a dirty input; poll a ready value instead")
            frames[top].next = -cursor - 1
            frames[top].waiting = source
            push(source)
        case .finished:
            pruneEdges(of: node, keeping: cursor)
            table.state[n] = (table.state[n] & ~(NodeState.dirty | NodeState.evaluating | NodeState.pending))
                | NodeState.hasValue
            if outcome.changed { table.versions[n] &+= 1 }
            frames.removeLast()
        }
    }
}
