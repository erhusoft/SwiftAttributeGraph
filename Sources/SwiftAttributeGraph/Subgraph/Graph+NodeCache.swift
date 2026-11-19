extension Graph {
    /// Creates a new ``GraphContext`` for independent per-context update callbacks and subgraph lifecycle.
    public func makeContext() -> GraphContext {
        assertOwnThread()
        precondition(nextGraphContextID != UInt32.max, "makeContext: context ID space exhausted")
        let id = nextGraphContextID
        nextGraphContextID += 1
        let ctx = GraphContext(graph: self, id: id, subgraphContext: makeSubgraphContext())
        updateContexts.removeAll { $0.value == nil }
        updateContexts.append(WeakGraphContext(value: ctx))
        return ctx
    }

    func invalidateContext(_ context: GraphContext) {
        assertOwnThread()
        context.updateCallback = nil
        context.needsUpdate = false
        let targetCtx = context.subgraphContext.rawValue
        for index in 0..<subgraphs.slotCount {
            let sgID = subgraphs.id(at: UInt32(index))
            guard subgraphs.isLive(sgID),
                  !subgraphs.isFalling(index: UInt32(index)),
                  subgraphs.context(of: UInt32(index)) == targetCtx else { continue }
            let sg = Subgraph(id: sgID)
            if sg != rootSubgraph {
                invalidate(sg)
            }
        }
    }

    /// Registers a callback on the graph's default context, invoked when the graph transitions from clean to needing an
    /// update (matching `AGGraphSetUpdateCallback` / `Context::call_update()` in native AttributeGraph).
    ///
    /// If a batch or rule evaluation is currently active, delivery is deferred until the outermost scope completes.
    public func setUpdateCallback(_ callback: (() -> Void)?) {
        assertOwnThread()
        defaultUpdateContext.setUpdateCallback(callback)
    }

    /// Marks the graph's default context as needing an update without invoking the callback immediately;
    /// callbacks are drained when reading a value or starting an update outside an active update pass
    /// (matching `AGGraphSetNeedsUpdate`).
    public func setNeedsUpdate() {
        assertOwnThread()
        defaultUpdateContext.setNeedsUpdate()
    }

    func markNeedsUpdateCallback() {
        defaultUpdateContext.needsUpdate = true
        flushUpdateCallbackIfReady()
    }

    func flushUpdateCallbackIfReady() {
        guard !isInUpdateCallback, batchDepth == 0, evaluatingNode == Graph.noNode, !isInvalidating else { return }
        isInUpdateCallback = true
        defer { isInUpdateCallback = false }
        var iterations = 0
        let maxIterations = 1024
        while batchDepth == 0 && evaluatingNode == Graph.noNode && !isInvalidating {
            var firedAny = false
            for entry in updateContexts {
                guard let ctx = entry.value, !ctx.isInvalidated, ctx.needsUpdate else { continue }
                ctx.needsUpdate = false
                firedAny = true
                ctx.updateCallback?()
            }
            if !firedAny { break }
            iterations += 1
            precondition(iterations < maxIterations, "update callback loop exceeded \(maxIterations) iterations")
        }
        updateContexts.removeAll { $0.value == nil || $0.value?.isInvalidated == true }
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

    /// Ages all parked cached attributes and frees those that reach `maxAge` (default `255`, matching `0xff` passes
    /// in native `AG::NodeCache::collect`), disconnecting their input edges from sources' output lists first.
    public func collectCachedNodes(maxAge: UInt8 = 255) {
        assertOwnThread()
        for sgIndex in Array(nodeCaches.keys) {
            guard let expired = nodeCaches[sgIndex]?.collect(maxAge: maxAge), !expired.isEmpty else { continue }
            for node in expired {
                let id = AttributeID(index: node, generation: table.generations[Int(node)])
                if table.isLive(id) {
                    for edge in table.inputs[Int(node)] {
                        removeOutput(node, from: edge.source, at: edge.positionInOutputs)
                    }
                    table.inputs[Int(node)].removeAll(keepingCapacity: false)
                    observers[node] = nil
                    table.free(index: node)
                }
            }
        }
    }
}
