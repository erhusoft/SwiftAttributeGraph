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

/// Subgraph flag methods with Apple's names: `AGSubgraphRef.intersects(self:flags:)`, `isDirty(self:flags:)` and
/// `update(self:flags:)` [O, native headers AGSubgraph.h].
extension Subgraph {
    /// Whether any attribute of this subgraph has flags in common with `flags`.
    public func intersects(flags: AttributeFlags) -> Bool {
        owningGraph().intersects(self, flags: flags)
    }

    /// Whether any dirty attribute of this subgraph has flags in common with `flags`.
    public func isDirty(flags: AttributeFlags) -> Bool {
        owningGraph().isDirty(self, flags: flags)
    }

    /// Updates the attributes of this subgraph that have flags in common with `flags`.
    public func update(flags: AttributeFlags = .all) {
        owningGraph().update(self, flags: flags)
    }
}

extension Subgraph {
    /// Links `child` under this subgraph with a two-bit tag (`AGSubgraphAddChild2` in native AttributeGraph).
    public func addChild(_ child: Subgraph, tag: UInt8) { owningGraph().addChild(child, to: self, tag: tag) }

    /// The number of children (`AGSubgraphGetChildCount` in native AttributeGraph).
    public var childCount: UInt32 { owningGraph().childCount(of: self) }

    /// The child at `index` in link order, with its tag (`AGSubgraphGetChild` in native AttributeGraph).
    public func child(at index: UInt32) -> (subgraph: Subgraph, tag: UInt8) { owningGraph().child(of: self, at: index) }

    /// The number of parents linked to this subgraph (`AGSubgraphGetParentCount` in native AttributeGraph).
    public var parentCount: UInt64 { owningGraph().parentCount(of: self) }

    /// The parent at `index` in link order (`AGSubgraphGetParent` in native AttributeGraph).
    public func parent(at index: Int64) -> Subgraph { owningGraph().parent(of: self, at: index) }
}

/// The identifier of a subgraph observer (`AGObserverID` in native AttributeGraph, `ObserverID` there).
public typealias ObserverID = Int

extension Subgraph {
    /// Registers `observer` to run once when this subgraph is invalidated, and returns its identifier
    /// (`AGSubgraphAddObserver` in native AttributeGraph). The observer stays until ``removeObserver(_:)`` or the subgraph
    /// dies.
    public func addObserver(_ observer: @escaping () -> Void) -> ObserverID {
        owningGraph().observe(self, onInvalidate: observer).id
    }

    /// Removes the observer with `id`, so it does not run (`AGSubgraphRemoveObserver` in native AttributeGraph).
    public func removeObserver(_ id: ObserverID) {
        let graph = owningGraph()
        guard graph.subgraphs.isLive(self.id) else { return }
        graph.subgraphObservers[self.id.index]?.removeAll { $0.id == id }
        if graph.subgraphObservers[self.id.index]?.isEmpty ?? false { graph.subgraphObservers[self.id.index] = nil }
    }
}
