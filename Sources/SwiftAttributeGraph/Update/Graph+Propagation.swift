extension Graph {
    /// Marks as dirty everything that reads `source`, directly or not, without running any rule.
    ///
    /// The traversal is iterative and does not descend through a node that is already dirty: all its readers are
    /// already dirty too, because a node can only be brought up to date after its inputs.
    func propagateDirty(from source: UInt32) {
        if hasAnyInvalidationCallback {
            propagateDirtyWithInvalidationCallback(from: source)
            return
        }
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

    private func propagateDirtyWithInvalidationCallback(from source: UInt32) {
        let originID = AttributeID(index: source, generation: table.generations[Int(source)])
        let originAttr = AnyAttribute(id: originID)
        let originSubgraphCtx = subgraphs.context(of: table.owner(at: source))
        var localStack: [UInt32] = []
        if edgeComparators.isEmpty {
            localStack.append(contentsOf: table.outputs[Int(source)])
        } else {
            for dependent in table.outputs[Int(source)] {
                if edgeComparators[dependent]?[source] != nil,
                   stickyChangedEdges[dependent]?.contains(source) != true {
                    continue
                }
                localStack.append(dependent)
            }
        }
        let skipsNoEdge = edgeComparators.isEmpty && offsetIndirects.isEmpty
        while let node = localStack.popLast() {
            let n = Int(node)
            let state = table.state[n]
            if state & NodeState.dirty != 0 { continue }
            table.state[n] = state | NodeState.dirty
            let owner = table.owner(at: node)
            if table.flags[n] != 0 { subgraphs.markDirtyFlags(table.flags[n], on: owner) }
            if state & NodeState.observed != 0 { queueNotification(node) }
            if state & NodeState.hasCrossContextInput != 0 && !table.outputs[n].isEmpty {
                let consumerSubgraphCtx = subgraphs.context(of: owner)
                if consumerSubgraphCtx != originSubgraphCtx {
                    let ctx = graphContext(forSubgraphContext: consumerSubgraphCtx)
                    if !ctx.isInvalidated && ctx.lastInvalidationEpoch != readEpoch {
                        ctx.lastInvalidationEpoch = readEpoch
                        if let cb = ctx.invalidationCallback {
                            withoutUpdate { cb(originAttr) }
                        }
                    }
                }
            }
            if skipsNoEdge {
                localStack.append(contentsOf: table.outputs[n])
                continue
            }
            for dependent in table.outputs[n] {
                if table.state[Int(dependent)] & NodeState.indirect == 0,
                   (edgeComparators[dependent]?[node] != nil || hasOffsetInChain(node)),
                   stickyChangedEdges[dependent]?.contains(node) != true {
                    continue
                }
                localStack.append(dependent)
            }
        }
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
