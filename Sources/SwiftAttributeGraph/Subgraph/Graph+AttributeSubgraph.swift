extension Graph {
    /// The subgraph that owns `attribute`: the one that was current when it was created
    /// (`AGAttribute.subgraph` in native AttributeGraph).
    public func subgraph<Value>(of attribute: Attribute<Value>) -> Subgraph {
        subgraph(of: attribute.erased)
    }

    /// The subgraph that owns `attribute` (`AnyAttribute.subgraph` in native AttributeGraph).
    public func subgraph(of attribute: AnyAttribute) -> Subgraph {
        subgraph(of: attribute.id)
    }
}
