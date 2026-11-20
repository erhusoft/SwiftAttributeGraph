/// Subgraph methods with the names Apple uses in `AGSubgraphRef` [O, native headers AGSubgraph.h]. They resolve the
/// owning graph from the subgraph's tag, so no graph reference is stored in the handle (design decision, measured
/// separately). The graph-level methods remain until the core has moved to these names.
extension Subgraph {
    /// Whether the subgraph is still alive (`AGSubgraphRef.isValid`).
    public var isValid: Bool {
        guard let graph = GraphRegistry.graph(forTag: id.graphTag) else { return false }
        return graph.isValid(self)
    }

    /// Makes `child` a child of this subgraph (`AGSubgraphRef.addChild(self:_:)`).
    public func addChild(_ child: Subgraph) {
        owningGraph().addChild(child, to: self)
    }

    /// Removes `child` from this subgraph (`AGSubgraphRef.removeChild(self:_:)`).
    public func removeChild(_ child: Subgraph) {
        owningGraph().removeChild(child, from: self)
    }

    /// Invalidates this subgraph and everything it owns (`AGSubgraphRef.invalidate(self:)`).
    public func invalidate() {
        owningGraph().invalidate(self)
    }

    private func owningGraph() -> Graph {
        guard let graph = GraphRegistry.graph(forTag: id.graphTag) else {
            preconditionFailure("Subgraph used after its graph was released")
        }
        return graph
    }
}
