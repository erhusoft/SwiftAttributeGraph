extension Graph {
    /// Frees every attribute the subgraph owns. The root subgraph cannot be invalidated.
    ///
    /// Rules outside the subgraph that read what it owned lose those edges and become dirty, together with everything
    /// that reads them: they will run again on their next read and must not read the dead attributes. Observers of
    /// the attributes that became dirty are notified. Invalidating while a rule runs is not supported in M0 (the
    /// deferred invalidation of M5 will allow it).
    public func invalidate(_ subgraph: Subgraph) {
        assertOwnThread()
        precondition(subgraph != rootSubgraph, "invalidate: the root subgraph cannot be invalidated")
        precondition(subgraphs.isLive(subgraph.id), "invalidate: the subgraph was already invalidated")
        precondition(evaluatingNode == Graph.noNode, "invalidate: cannot invalidate while a rule is running")

        let ownerIndex = subgraph.id.index
        let owned = subgraphs.release(subgraph.id)
        var affected: [UInt32] = []

        // Detach the owned attributes from their neighbours outside the subgraph before any slot is freed.
        for node in owned {
            let n = Int(node)
            for edge in table.inputs[n] where table.owner(at: edge.source) != ownerIndex {
                removeOutput(node, from: edge.source)
            }
            for dependent in table.outputs[n] where table.owner(at: dependent) != ownerIndex {
                table.inputs[Int(dependent)].removeAll { $0.source == node }
                table.state[Int(dependent)] |= NodeState.pending   // it lost an input: it must run again
                affected.append(dependent)
            }
        }

        for node in owned {
            observers[node] = nil
            table.free(index: node)
        }

        markDirty(roots: affected)
        flushNotifications()
    }
}
