extension Graph {
    /// Creates a shared reference to `graph` sharing the underlying attribute and subgraph tables (`AGGraphCreateShared`).
    ///
    /// ## What is shared
    /// - Storage tables: `table` (attributes, values, versions, inputs, outputs)
    /// - Graph namespace tag: `graphTag`
    /// - Identity counters: `graphCounterID` (the `graphID` counter)
    /// - Subgraph hierarchy: `subgraphs`
    /// - Subgraph caches, comparators, and node tables
    /// - Strong lifecycle anchor: holding a shared handle keeps the primary storage alive even if the creator `Graph` is released
    ///
    /// ## What is not shared (per-handle identity)
    /// - `activeContext`: each shared handle owns its distinct `GraphContext` (with unique `contextID` and `subgraphContext`)
    /// - Current creation scope: `currentSubgraph` (initialized to the handle's dedicated root subgraph)
    /// - Dedicated root subgraph: `rootSubgraph` (scoped to the handle's `subgraphContext`)
    /// - Callbacks and observation routing: `onInvalidation` / `onUpdate` operate on the handle's own `activeContext`
    public convenience init(shared: Graph) {
        let underlying = shared.primary ?? shared
        let ctx = underlying.makeSharedContext()
        let root = underlying.subgraphs.allocate(parent: nil, context: ctx.subgraphContext.rawValue)
        self.init(sharedPrimary: underlying, context: ctx, rootSubgraph: Subgraph(id: root))
    }

    /// The active context of this graph handle.
    public var currentContext: GraphContext {
        activeContext ?? defaultUpdateContext
    }

    /// Resolves the storage graph for this handle (self if primary, or primary).
    @inline(__always)
    var storageGraph: Graph {
        primary ?? self
    }
}
