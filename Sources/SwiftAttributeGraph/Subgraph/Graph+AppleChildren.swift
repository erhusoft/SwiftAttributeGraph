extension Graph {
    /// The number of children of `subgraph` (`AGSubgraphGetChildCount` in native AttributeGraph).
    public func childCount(of subgraph: Subgraph) -> UInt32 {
        assertOwnThread()
        precondition(subgraphs.isLive(subgraph.id), "childCount(of:): the subgraph was invalidated")
        return UInt32(subgraphs.children(of: subgraph.id.index).count)
    }

    /// The child at `index` in link order, with its two-bit tag (`AGSubgraphGetChild` in native AttributeGraph).
    public func child(of subgraph: Subgraph, at index: UInt32) -> (subgraph: Subgraph, tag: UInt8) {
        assertOwnThread()
        precondition(subgraphs.isLive(subgraph.id), "child(of:at:): the subgraph was invalidated")
        let children = subgraphs.childrenWithTags(of: subgraph.id.index)
        precondition(Int(index) < children.count, "child(of:at:): index out of range")
        let entry = children[Int(index)]
        return (Subgraph(id: subgraphs.id(at: entry.child)), entry.tag)
    }

    /// The number of parents of `subgraph`, the root and every secondary parent (`AGSubgraphGetParentCount`).
    public func parentCount(of subgraph: Subgraph) -> UInt64 {
        assertOwnThread()
        precondition(subgraphs.isLive(subgraph.id), "parentCount(of:): the subgraph was invalidated")
        return UInt64(subgraphs.parents(of: subgraph.id.index).count)
    }

    /// The parent at `index` in link order (`AGSubgraphGetParent` in native AttributeGraph).
    public func parent(of subgraph: Subgraph, at index: Int64) -> Subgraph {
        assertOwnThread()
        precondition(subgraphs.isLive(subgraph.id), "parent(of:at:): the subgraph was invalidated")
        let parents = subgraphs.parents(of: subgraph.id.index)
        precondition(index >= 0 && Int(index) < parents.count, "parent(of:at:): index out of range")
        return Subgraph(id: subgraphs.id(at: parents[Int(index)]))
    }
}
