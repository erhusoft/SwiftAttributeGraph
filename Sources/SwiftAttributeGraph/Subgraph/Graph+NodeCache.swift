extension Graph {
    /// Registers a callback invoked when the graph transitions from clean to needing an update (matching
    /// `AGGraphSetUpdateCallback` / `Context::call_update()` in native AttributeGraph).
    ///
    /// If a batch or rule evaluation is currently active, delivery is deferred until the outermost scope completes.
    public func setUpdateCallback(_ callback: (() -> Void)?) {
        assertOwnThread()
        updateCallback = callback
    }

    func markNeedsUpdateCallback() {
        needsUpdateCallback = true
        flushUpdateCallbackIfReady()
    }

    func flushUpdateCallbackIfReady() {
        guard needsUpdateCallback, batchDepth == 0, evaluatingNode == Graph.noNode, !isInvalidating else { return }
        needsUpdateCallback = false
        updateCallback?()
    }

    /// Looks up or creates a cached attribute in `owner` (or the currently evaluating node's owner subgraph, matching
    /// `read_cached_attribute` in native AttributeGraph).
    ///
    /// If the attribute is read outside an active evaluation and has no downstream consumers, it is immediately parked
    /// in the subgraph's ``SubgraphNodeCache``.
    public func readCachedAttribute<Key: Hashable, Value>(
        key: Key,
        owner: Subgraph? = nil,
        create: () -> Attribute<Value>
    ) -> Attribute<Value> {
        assertOwnThread()
        let ownerSubgraph: Subgraph
        if let owner {
            ownerSubgraph = owner
        } else if evaluatingNode != Graph.noNode {
            ownerSubgraph = Subgraph(id: subgraphs.id(at: table.owner(at: evaluatingNode)))
        } else {
            ownerSubgraph = Subgraph(id: currentSubgraph)
        }
        precondition(subgraphs.isLive(ownerSubgraph.id) && !subgraphs.isFalling(index: ownerSubgraph.id.index),
                     "readCachedAttribute: owner subgraph is not valid")

        let cacheKey = SubgraphNodeCache.Key(typeID: ObjectIdentifier(Value.self), key: AnyHashable(key))
        if let entry = nodeCaches[ownerSubgraph.id.index]?.lookup(key: cacheKey) {
            let id = AttributeID(index: entry.node, generation: entry.generation)
            if table.isLive(id) {
                if evaluatingNode == Graph.noNode && table.outputs[Int(entry.node)].isEmpty {
                    nodeCaches[ownerSubgraph.id.index]?.park(node: entry.node)
                }
                return Attribute<Value>(id: id)
            }
        }

        let attribute = withCurrent(ownerSubgraph) { create() }
        let idx = Int(attribute.id.index)
        table.state[idx] |= NodeState.cached
        nodeCaches[ownerSubgraph.id.index, default: SubgraphNodeCache()].insert(
            key: cacheKey,
            node: attribute.id.index,
            generation: attribute.id.generation,
            age: (evaluatingNode == Graph.noNode && table.outputs[idx].isEmpty) ? 1 : 0
        )
        return attribute
    }

    /// Parks a cached node in its owner subgraph's cache when its last consumer is removed.
    func parkCachedNodeIfUnreferenced(_ node: UInt32) {
        let idx = Int(node)
        guard table.state[idx] & NodeState.cached != 0, table.outputs[idx].isEmpty else { return }
        let owner = table.owner(at: node)
        nodeCaches[owner]?.park(node: node)
    }

    /// Ages all parked cached attributes and frees those that reach `maxAge` (matching `AG::NodeCache::collect`).
    public func collectCachedNodes(maxAge: UInt8 = 2) {
        assertOwnThread()
        for sgIndex in Array(nodeCaches.keys) {
            guard let expired = nodeCaches[sgIndex]?.collect(maxAge: maxAge), !expired.isEmpty else { continue }
            for node in expired {
                let id = AttributeID(index: node, generation: table.generations[Int(node)])
                if table.isLive(id) {
                    observers[node] = nil
                    table.free(index: node)
                }
            }
        }
    }
}
