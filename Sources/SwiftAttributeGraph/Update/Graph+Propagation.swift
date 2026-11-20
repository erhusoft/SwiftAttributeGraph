extension Graph {
    /// Marks as dirty everything that reads `source`, directly or not, without running any rule.
    ///
    /// The traversal is iterative and does not descend through a node that is already dirty: all its readers are
    /// already dirty too, because a node can only be brought up to date after its inputs.
    func propagateDirty(from source: UInt32) {
        dirtyStack.removeAll(keepingCapacity: true)
        if edgeComparators.isEmpty {
            dirtyStack.append(contentsOf: table.outputs[Int(source)])
            drainDirtyStack()
            return
        }
        for dependent in table.outputs[Int(source)] {
            if edgeComparators[dependent]?[source] != nil,
               stickyChangedEdges[dependent]?.contains(source) != true {
                continue
            }
            dirtyStack.append(dependent)
        }
        drainDirtyStack()
    }

    /// Marks the given nodes themselves dirty (unless they already are) and everything that reads them.
    func markDirty(roots: [UInt32]) {
        dirtyStack.removeAll(keepingCapacity: true)
        dirtyStack.append(contentsOf: roots)
        drainDirtyStack()
    }

    private func drainDirtyStack() {
        // Without partial edge comparators or offset attributes no edge is ever skipped, so the common case pays no
        // dictionary lookup per edge. Marking dirty runs no user code, so neither can appear during the drain.
        let skipsNoEdge = edgeComparators.isEmpty && offsetIndirects.isEmpty
        while let node = dirtyStack.popLast() {
            let n = Int(node)
            if table.state[n] & NodeState.dirty != 0 { continue }
            table.state[n] |= NodeState.dirty
            if table.flags[n] != 0 { subgraphs.markDirtyFlags(table.flags[n], on: table.owner(at: node)) }
            if table.state[n] & NodeState.observed != 0 { queueNotification(node) }
            if skipsNoEdge {
                dirtyStack.append(contentsOf: table.outputs[n])
                continue
            }
            for dependent in table.outputs[n] {
                if table.state[Int(dependent)] & NodeState.indirect == 0,
                   (edgeComparators[dependent]?[node] != nil || hasOffsetInChain(node)),
                   stickyChangedEdges[dependent]?.contains(node) != true {
                    continue
                }
                dirtyStack.append(dependent)
            }
        }
    }
}
