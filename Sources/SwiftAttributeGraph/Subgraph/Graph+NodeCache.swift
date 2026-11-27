extension Graph {
    /// The graph's own context, the one ``counter(for:)`` and ``setUpdateCallback(_:)`` refer to. Its
    /// ``GraphContext/contextID`` is `graphID + 1` [O]. Subgraphs not created through another context belong to it.
    public var defaultContext: GraphContext {
        assertOwnThread()
        return defaultUpdateContext
    }

    /// Creates a second context over this same graph (`AGGraphCreateShared(graph)` in native AttributeGraph).
    ///
    /// The new context has the graph's ``Graph/CounterQueryType/graphID`` and takes the next number of the process-wide
    /// counter as its ``GraphContext/contextID`` [O]; it is not the same object as the default context [O]. Subgraphs
    /// created with ``GraphContext/makeSubgraph(parent:)`` belong to it (``graphContext(of:)-(Subgraph)``).
    public func makeSharedContext() -> GraphContext {
        assertOwnThread()
        precondition(nextGraphContextID != UInt32.max, "makeSharedContext: context ID space exhausted")
        let id = nextGraphContextID
        nextGraphContextID += 1
        let ctx = GraphContext(graph: self, id: id, contextID: GraphRegistry.reserveCounterID(),
                               subgraphContext: makeSubgraphContext())
        updateContexts.removeAll { $0.value == nil }
        updateContexts.append(WeakGraphContext(value: ctx))
        return ctx
    }

    /// Same as ``makeSharedContext()``: every context created after the default one is a shared context and takes a
    /// number of the process-wide counter [O].
    public func makeContext() -> GraphContext { makeSharedContext() }

    /// The context a subgraph belongs to: the one it was created with (``GraphContext/makeSubgraph(parent:)``), or the
    /// parent's when it was created without one, or the default context.
    ///
    /// Subgraphs made with ``makeSubgraph(parent:context:)`` and a bare ``SubgraphContext`` that no ``GraphContext``
    /// owns report the default context [?]. Native keeps the context chosen by `Subgraph(graph:)`, where the graph
    /// object passed is the context [O]; `AGSubgraphGetCurrentGraphContext` through the Swift overlay crashes (exit 139)
    /// and the "current" context was not measured [?].
    public func graphContext(of subgraph: Subgraph) -> GraphContext {
        assertOwnThread()
        precondition(subgraphs.isLive(subgraph.id), "graphContext(of:): the subgraph was invalidated")
        return graphContext(forSubgraphContext: subgraphs.context(of: subgraph.id.index))
    }

    /// The context of the subgraph that owns `attribute` (what native shows as the graph object of the attribute [O]).
    public func graphContext<Value>(of attribute: Attribute<Value>) -> GraphContext {
        assertOwnThread()
        precondition(table.isLive(attribute.id), "graphContext(of:): the attribute is dead")
        return graphContext(forSubgraphContext: subgraphs.context(of: table.owner(at: attribute.id.index)))
    }

    /// The context that owns the subgraph context with this raw value; the default one if none does.
    func graphContext(forSubgraphContext raw: UInt32) -> GraphContext {
        if raw != SubgraphTable.defaultContext {
            for entry in updateContexts {
                if let ctx = entry.value, ctx.subgraphContext.rawValue == raw { return ctx }
            }
        }
        return defaultUpdateContext
    }

    /// Whether the innermost running rule belongs to a subgraph of `context`.
    func isRunning(in context: GraphContext) -> Bool {
        guard let frame = frames.last else { return false }
        return graphContext(forSubgraphContext: subgraphs.context(of: table.owner(at: frame.node))) === context
    }

    /// Lowers the graph's `needsUpdate` and every context's `contextNeedsUpdate` (a top-level rule read does, from any
    /// context [O]).
    func clearNeedsUpdateFlags() {
        needsUpdateFlag = false
        for entry in updateContexts { entry.value?.counterNeedsUpdate = false }
    }

    func invalidateContext(_ context: GraphContext) {
        assertOwnThread()
        context.updateCallback = nil
        context.invalidationCallback = nil
        context.needsUpdate = false
        refreshHasAnyInvalidationCallback()
        refreshHasAnyPendingUpdateCallback()
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

    func refreshHasAnyInvalidationCallback() {
        var any = false
        for entry in updateContexts {
            if let ctx = entry.value, !ctx.isInvalidated, ctx.invalidationCallback != nil {
                any = true
                break
            }
        }
        hasAnyInvalidationCallback = any
    }

    func refreshHasAnyPendingUpdateCallback() {
        var any = false
        for entry in updateContexts {
            if let ctx = entry.value, !ctx.isInvalidated, ctx.needsUpdate {
                any = true
                break
            }
        }
        hasAnyPendingUpdateCallback = any
    }

    /// User-supplied opaque context pointer on the graph's default context (`AGGraphGetContext` / `AGGraphSetContext` in
    /// native AttributeGraph; defaults to `nil` [O]).
    public var context: UnsafeRawPointer? {
        get {
            assertOwnThread()
            precondition(!isInvalidated, "invalidated graph")
            return defaultUpdateContext.context
        }
        set {
            assertOwnThread()
            precondition(!isInvalidated, "invalidated graph")
            defaultUpdateContext.context = newValue
        }
    }

    /// Registers a cross-context invalidation callback on the graph's default context (`AGGraphSetInvalidationCallback`
    /// in native AttributeGraph [O]).
    public func setInvalidationCallback(_ callback: ((AnyAttribute) -> Void)?) {
        assertOwnThread()
        defaultUpdateContext.setInvalidationCallback(callback)
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

    /// Whether any live update context is waiting to fire its callback (O(1) cached flag).
    @inline(__always)
    var hasPendingUpdateCallback: Bool {
        hasAnyPendingUpdateCallback
    }

    func flushUpdateCallbackIfReady() {
        guard !isInUpdateCallback, batchDepth == 0, evaluatingNode == Graph.noNode, !isInvalidating else { return }
        isInUpdateCallback = true
        defer {
            isInUpdateCallback = false
            refreshHasAnyPendingUpdateCallback()
        }
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
        withoutActuallyEscaping(create) { create in
            cachedAttribute(typeKey: ObjectIdentifier(Value.self), key: AnyHashable(key), owner: owner, create: create)!
        }
    }

    /// Looks up a cached attribute without creating it (`AGGraphReadCachedAttributeIfExists` in native AttributeGraph).
    func existingCachedAttribute<Value>(typeKey: ObjectIdentifier, key: AnyHashable, owner: Subgraph?) -> Attribute<Value>? {
        cachedAttribute(typeKey: typeKey, key: key, owner: owner, create: nil)
    }

    /// The shared body of ``readCachedAttribute(key:owner:create:)`` and the `Rule.cachedValue` family: `typeKey` is what
    /// the native cache calls the key type, and `key` the key value compared with `==`. With `create == nil` it only looks.
    func cachedAttribute<Value>(
        typeKey: ObjectIdentifier,
        key: AnyHashable,
        owner: Subgraph?,
        create: (() -> Attribute<Value>)?
    ) -> Attribute<Value>? {
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
                     "accessing invalidated subgraph")

        let cacheKey = SubgraphNodeCache.Key(typeID: typeKey, key: key)
        if let entry = nodeCaches[ownerSubgraph.id.index]?.lookup(key: cacheKey) {
            let id = AttributeID(index: entry.node, generation: entry.generation)
            if table.isLive(id) {
                if evaluatingNode == Graph.noNode && table.outputs[Int(entry.node)].isEmpty {
                    nodeCaches[ownerSubgraph.id.index]?.park(node: entry.node)
                }
                return Attribute<Value>(id: id)
            }
        }
        guard let create else { return nil }

        // A new key takes over the oldest parked entry of the same type that a pass aged to 2 or more. Native reuses its
        // node; here it is freed and a fresh one made, so the old key is gone either way.
        if let recycled = nodeCaches[ownerSubgraph.id.index]?.takeOldestRecyclable(typeID: typeKey) {
            freeCachedNode(recycled)
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
            for node in expired { freeCachedNode(node) }
        }
    }

    /// Frees a cached node, disconnecting its input edges from the sources' output lists first.
    func freeCachedNode(_ node: UInt32) {
        let id = AttributeID(index: node, generation: table.generations[Int(node)])
        guard table.isLive(id) else { return }
        for edge in table.inputs[Int(node)] {
            removeOutput(node, from: edge.source, at: edge.positionInOutputs)
        }
        table.inputs[Int(node)].removeAll(keepingCapacity: false)
        observers[node] = nil
        table.free(index: node)
    }

    /// One collection pass over the node caches, run where native AttributeGraph runs `invalidate_subgraphs`: the end of an
    /// invalidation, of ``update(_:flags:)`` and of a deferral of invalidations (oracle scenarios `p1`, `p2`, `p3`). Not while
    /// a rule runs or invalidations are deferred.
    func runCachePass() {
        guard evaluatingNode == Graph.noNode, !isInvalidating, deferringSubgraphInvalidationDepth == 0 else { return }
        collectCachedNodes()
    }
}
