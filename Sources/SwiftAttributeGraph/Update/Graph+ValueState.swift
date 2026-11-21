extension Graph {
    /// The state bits of `attribute` (`AGAttribute.valueState` in native AttributeGraph). Only the bits in
    /// ``ValueState`` are reported.
    @available(*, deprecated, message: "Use the Apple-named accessor on the attribute instead: `attribute.valueState`.")
    public func valueState<Value>(of attribute: Attribute<Value>) -> ValueState {
        valueStateImpl(of: attribute.erased)
    }

    /// The state bits of `attribute` (`AnyAttribute.valueState` in native AttributeGraph).
    @available(*, deprecated, message: "Use the Apple-named accessor on the attribute instead: `attribute.valueState`.")
    public func valueState(of attribute: AnyAttribute) -> ValueState {
        valueStateImpl(of: attribute)
    }

    /// The implementation behind ``valueState(of:)``, shared with `Attribute.valueState` (not deprecated).
    func valueStateImpl(of attribute: AnyAttribute) -> ValueState {
        assertOwnThread()
        precondition(table.isLive(attribute.id), "valueState(of:): the attribute is dead")
        let state = table.state[Int(attribute.id.index)]
        var result: ValueState = []
        if state & NodeState.dirty != 0 { result.insert(.dirty) }
        if state & NodeState.pending != 0 { result.insert(.pending) }
        if state & NodeState.hasValue != 0 { result.insert(.valueExists) }
        if state & NodeState.selfModified != 0 { result.insert(.selfModified) }
        return result
    }
}
