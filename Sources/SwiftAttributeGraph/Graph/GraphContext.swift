/// An update-callback context associated with a ``Graph`` (matching `AG::Graph::Context` in native AttributeGraph,
/// distinct from ``SubgraphContext``).
///
/// Each `GraphContext` maintains its own `needsUpdate` flag and update callback, coalescing repeated requests until
/// the graph drains pending callbacks before evaluation or at the end of a batch.
public final class GraphContext {
    private unowned let graph: Graph
    let id: UInt32
    var updateCallback: (() -> Void)?
    var needsUpdate = false

    init(graph: Graph, id: UInt32) {
        self.graph = graph
        self.id = id
    }

    /// Registers a callback invoked when this context has pending update work.
    public func setUpdateCallback(_ callback: (() -> Void)?) {
        graph.assertOwnThread()
        updateCallback = callback
    }

    /// Marks this context as needing an update and drains callbacks if the graph is not inside a batch or evaluation.
    public func setNeedsUpdate() {
        graph.assertOwnThread()
        needsUpdate = true
        graph.flushUpdateCallbackIfReady()
    }
}
