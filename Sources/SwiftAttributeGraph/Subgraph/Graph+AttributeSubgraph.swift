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

extension Graph {
    /// The subgraph that owns `attribute`, or `nil` if the attribute no longer exists because its subgraph was freed
    /// (`AGGraphGetAttributeSubgraph2`, `AGAttribute.subgraphOrNil` in native AttributeGraph).
    public func subgraphOrNil<Value>(of attribute: Attribute<Value>) -> Subgraph? {
        subgraphOrNil(of: attribute.erased)
    }

    /// The untyped form of ``subgraphOrNil(of:)-(Attribute<Value>)``.
    public func subgraphOrNil(of attribute: AnyAttribute) -> Subgraph? {
        assertOwnThread()
        guard table.isLive(attribute.id) else { return nil }
        return subgraph(of: attribute)
    }
}
