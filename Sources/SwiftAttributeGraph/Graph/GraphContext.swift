/// An update-callback and lifecycle context associated with a ``Graph`` (matching `AG::Graph::Context` in native
/// AttributeGraph, distinct from ``SubgraphContext``).
///
/// Each `GraphContext` owns a distinct ``SubgraphContext`` for invalidation scoping, maintains its own `needsUpdate`
/// flag and update callback, and invalidates its live subgraphs when ``invalidate()`` is called or when the context is
/// deallocated while its `Graph` is still alive.
///
/// Minimal model of native shared contexts (`AGGraphCreateShared`) [O]: a graph has a default context (``Graph/defaultContext``)
/// and any number of shared ones (``Graph/makeSharedContext()``). Every context has its own ``contextID``, user
/// ``context`` pointer (`AGGraphSetContext`/`AGGraphGetContext`), update callback, cross-context invalidation callback
/// (`AGGraphSetInvalidationCallback`), `needsUpdate` flag (as seen by ``counter(for:)``), and subgraphs; they all share
/// the graph's attributes, counters and ``graphID`` [O].
public final class GraphContext {
    private weak var graph: Graph?
    let id: UInt32
    /// Process-wide number of this context, from the counter shared with graph IDs (`contextID` of
    /// `AGGraphGetCounter`): the default context of a graph is `graphID + 1`; a shared context takes the next number of
    /// the counter when it is created [O].
    public let contextID: UInt64
    /// Process-wide number of the graph this context belongs to; shared by all its contexts [O].
    public let graphID: UInt64
    /// What ``counter(for:)`` reports as `contextNeedsUpdate`: raised by this context's `setNeedsUpdate`, lowered by the
    /// next top-level rule read of the graph, from any context [O].
    var counterNeedsUpdate = false
    /// The invalidation context associated with this `GraphContext`.
    public let subgraphContext: SubgraphContext
    /// User-supplied opaque context pointer associated with this `GraphContext` (`AGGraphGetContext` / `AGGraphSetContext`
    /// in native AttributeGraph; defaults to `nil` [O]).
    public var context: UnsafeRawPointer?
    var updateCallback: (() -> Void)?
    var invalidationCallback: ((AnyAttribute) -> Void)?
    var lastInvalidationEpoch: UInt32 = 0
    var needsUpdate = false
    private(set) var isInvalidated = false

    init(graph: Graph, id: UInt32, contextID: UInt64, subgraphContext: SubgraphContext) {
        self.graph = graph
        self.id = id
        self.contextID = contextID
        self.graphID = graph.graphCounterID
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

    /// Registers a callback invoked during dirty propagation when an attribute of another context of the same graph
    /// changes, reaches a clean consumer in this context that has at least one output, and at least one value read has
    /// occurred on the graph since this context was last notified (`AGGraphSetInvalidationCallback` in native
    /// AttributeGraph [O]).
    public func setInvalidationCallback(_ callback: ((AnyAttribute) -> Void)?) {
        guard let graph else { return }
        graph.assertOwnThread()
        guard !isInvalidated else { return }
        invalidationCallback = callback
        graph.refreshHasAnyInvalidationCallback()
    }

    /// Marks this context as needing an update without invoking the callback immediately; callbacks are drained
    /// when reading a value or starting an update outside an active update pass.
    public func setNeedsUpdate() {
        guard let graph else { return }
        graph.assertOwnThread()
        guard !isInvalidated else { return }
        needsUpdate = true
        counterNeedsUpdate = true
        graph.needsUpdateFlag = true
    }

    /// The graph this context belongs to, or `nil` once it was released.
    public var owningGraph: Graph? { graph }

    /// The value of a counter as seen from this context (`AGGraphGetCounter` on a shared `Graph` object in native
    /// AttributeGraph). Measured with a graph and one shared context on macOS 15.8.3 [O]:
    /// - ``Graph/CounterQueryType/contextID`` is this context's number, ``Graph/CounterQueryType/graphID`` is the graph's.
    /// - ``Graph/CounterQueryType/contextNeedsUpdate`` is this context's flag; ``Graph/CounterQueryType/needsUpdate``
    ///   is the graph's, raised by any context.
    /// - ``Graph/CounterQueryType/contextThreadUpdating`` is `1` only while a rule of a subgraph of this context runs;
    ///   ``Graph/CounterQueryType/threadUpdating`` is `1` for every context of the graph.
    /// - Every other selector (nodes, subgraphs, updates, ...) is graph-wide.
    ///
    /// A rule that runs in another context while a rule of this one waits for it (nested reads across contexts) was
    /// not measured; the engine looks at the innermost running rule [?].
    public func counter(for query: Graph.CounterQueryType) -> UInt64 {
        switch query {
        case .contextID: return contextID
        case .graphID: return graphID
        case .contextNeedsUpdate: return counterNeedsUpdate ? 1 : 0
        case .contextThreadUpdating: return graph?.isRunning(in: self) == true ? 1 : 0
        default: return graph?.counter(for: query) ?? 0
        }
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
        invalidationCallback = nil
        needsUpdate = false
        counterNeedsUpdate = false
        graph?.invalidateContext(self)
    }
}
