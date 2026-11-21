extension Attribute {
    /// Creates an indirect attribute that redirects to this one (`AGGraphCreateIndirectAttribute`, `createIndirect(self:)` in
    /// native AttributeGraph). It is created in the current subgraph, like ``Graph/makeIndirect(_:)``.
    public func createIndirect() -> Attribute<Value> {
        graph.makeIndirect(self)
    }
}
