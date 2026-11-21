extension Graph {
    /// The subgraph that owns `attribute`: the one that was current when it was created
    /// (`AGAttribute.subgraph` in native AttributeGraph).
    @available(*, deprecated, message: "Use the Apple-named accessor on the attribute instead: `attribute.subgraph`.")
    public func subgraph<Value>(of attribute: Attribute<Value>) -> Subgraph {
        subgraphImpl(of: attribute.erased)
    }

    /// The subgraph that owns `attribute` (`AnyAttribute.subgraph` in native AttributeGraph).
    @available(*, deprecated, message: "Use the Apple-named accessor on the attribute instead: `attribute.subgraph`.")
    public func subgraph(of attribute: AnyAttribute) -> Subgraph {
        subgraphImpl(of: attribute)
    }

    /// The implementation behind ``subgraph(of:)``, shared with `Attribute.subgraph` (not deprecated).
    func subgraphImpl(of attribute: AnyAttribute) -> Subgraph {
        subgraph(of: attribute.id)
    }
}

extension Graph {
    /// The subgraph that owns `attribute`, or `nil` if the attribute no longer exists because its subgraph was freed
    /// (`AGGraphGetAttributeSubgraph2`, `AGAttribute.subgraphOrNil` in native AttributeGraph).
    @available(*, deprecated, message: "Use the Apple-named accessor on the attribute instead: `attribute.subgraphOrNil`.")
    public func subgraphOrNil<Value>(of attribute: Attribute<Value>) -> Subgraph? {
        subgraphOrNilImpl(of: attribute.erased)
    }

    /// The untyped form of ``subgraphOrNil(of:)-(Attribute<Value>)``.
    @available(*, deprecated, message: "Use the Apple-named accessor on the attribute instead: `attribute.subgraphOrNil`.")
    public func subgraphOrNil(of attribute: AnyAttribute) -> Subgraph? {
        subgraphOrNilImpl(of: attribute)
    }

    /// The implementation behind ``subgraphOrNil(of:)-(AnyAttribute)``, shared with `Attribute.subgraphOrNil` (not deprecated).
    func subgraphOrNilImpl(of attribute: AnyAttribute) -> Subgraph? {
        assertOwnThread()
        guard table.isLive(attribute.id) else { return nil }
        return subgraph(of: attribute)
    }
}
