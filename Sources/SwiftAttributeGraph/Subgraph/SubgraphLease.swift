/// A reference-counted owner of a subgraph: releasing the last lease invalidates the subgraph, which notifies its
/// observers and frees what it owns, as Apple's `AGSubgraphRef` does when its last reference goes away.
///
/// ``Subgraph`` itself stays a value handle; a lease is the object that carries the lifetime.
public final class SubgraphLease {
    private let graph: Graph
    /// The subgraph this lease keeps alive.
    public let subgraph: Subgraph

    /// Creates a subgraph owned by the graph's current subgraph (as ``Subgraph/init(graph:)`` does).
    public init(graph: Graph) {
        self.graph = graph
        self.subgraph = Subgraph(graph: graph)
    }

    /// Takes over the lifetime of an existing subgraph: releasing the lease invalidates it. Used by containers that
    /// create their children under a parent in a given context.
    public init(adopting subgraph: Subgraph, graph: Graph) {
        self.graph = graph
        self.subgraph = subgraph
    }

    deinit {
        // A subgraph already invalidated by other means is left alone; the root is never invalidated.
        guard graph.subgraphs.isLive(subgraph.id), subgraph != graph.rootSubgraph else { return }
        graph.invalidate(subgraph)
    }
}
