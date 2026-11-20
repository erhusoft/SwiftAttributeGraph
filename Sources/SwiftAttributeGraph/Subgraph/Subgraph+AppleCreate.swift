/// Apple's `AGSubgraphRef.init(graph:)`: a subgraph owned by the graph's current subgraph [O, native headers
/// AGSubgraph.h]. Equivalent to `Graph.makeSubgraph()`.
extension Subgraph {
    /// Creates a subgraph in `graph`, owned by the current subgraph.
    public init(graph: Graph) {
        self = graph.makeSubgraph()
    }
}
