/// An update-callback and lifecycle context associated with a ``Graph`` (matching `AG::Graph::Context` in native
/// AttributeGraph, distinct from ``SubgraphContext``).
///
/// Each `GraphContext` owns a distinct ``SubgraphContext`` for invalidation scoping, maintains its own `needsUpdate`
/// flag and update callback, and invalidates its live subgraphs when ``invalidate()`` is called or when the context is
/// deallocated while its `Graph` is still alive.
public final class GraphContext {
    private weak var graph: Graph?
    let id: UInt32
    /// The invalidation context associated with this `GraphContext`.
    public let subgraphContext: SubgraphContext
    var updateCallback: (() -> Void)?
    var needsUpdate = false
    private(set) var isInvalidated = false

    init(graph: Graph, id: UInt32, subgraphContext: SubgraphContext) {
        self.graph = graph
        self.id = id
        self.subgraphContext = subgraphContext
    }

    deinit {
        if !isInvalidated, let graph {
            graph.invalidateContext(self)
        }
    }

    /// Registers a callback invoked when this context has pending update work.
    public func setUpdateCallback(_ callback: (() -> Void)?) {
        guard let graph else { return }
        graph.assertOwnThread()
        guard !isInvalidated else { return }
        updateCallback = callback
    }

    /// Marks this context as needing an update and drains callbacks if the graph is not inside a batch or evaluation.
    public func setNeedsUpdate() {
        guard let graph else { return }
        graph.assertOwnThread()
        guard !isInvalidated else { return }
        needsUpdate = true
        graph.flushUpdateCallbackIfReady()
    }

    /// Creates a subgraph in this context's ``subgraphContext``.
    public func makeSubgraph(parent: Subgraph? = nil) -> Subgraph {
        guard let graph else {
            preconditionFailure("makeSubgraph: the owning Graph was deallocated")
        }
        return graph.makeSubgraph(parent: parent, context: subgraphContext)
    }

    /// Clears pending callbacks/requests and invalidates all live subgraphs belonging to this context.
    public func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        updateCallback = nil
        needsUpdate = false
        graph?.invalidateContext(self)
    }
}
