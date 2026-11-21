extension Attribute {
    /// Creates an indirect attribute that redirects to this one (`AGGraphCreateIndirectAttribute`, `createIndirect(self:)` in
    /// native AttributeGraph). It is created in the current subgraph, like ``Graph/makeIndirect(_:)``.
    public func createIndirect() -> Attribute<Value> {
        graph.makeIndirect(self)
    }

    /// Creates an indirect attribute that redirects to this one and declares the size of the value it projects
    /// (`AGGraphCreateIndirectAttribute2`). The declared size may not be larger than the size of `Value`: native
    /// AttributeGraph aborts with "invalid size for indirect attribute" in that case. Measured natively, the indirect
    /// attribute still reads the whole source value whatever the declared size, so the size is only checked here.
    public func createIndirect(size: Int) -> Attribute<Value> {
        precondition(size <= MemoryLayout<Value>.size,
                     "invalid size for indirect attribute: \(size) vs \(MemoryLayout<Value>.size)")
        return createIndirect()
    }
}
