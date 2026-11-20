extension Graph {
    /// Makes `attribute1` depend on `attribute2` as if it had read it (`AGGraphAddInput` in native AttributeGraph).
    /// Changing `attribute2` then dirties `attribute1`. The edge is an ordinary read: the next run of `attribute1` drops
    /// it unless the rule reads `attribute2` again. Apple's `options` and `token` are not modeled.
    public func addInput<Value1, Value2>(_ attribute1: Attribute<Value1>, _ attribute2: Attribute<Value2>) {
        addInput(attribute1.erased, attribute2.erased)
    }

    /// The untyped form of ``addInput(_:_:)-(Attribute<Value1>,Attribute<Value2>)``.
    public func addInput(_ attribute1: AnyAttribute, _ attribute2: AnyAttribute) {
        assertOwnThread()
        precondition(table.isLive(attribute1.id), "addInput: attribute1 is dead")
        precondition(table.isLive(attribute2.id), "addInput: attribute2 is dead")
        precondition(
            subgraphs.context(of: table.owner(at: attribute1.id.index)) ==
                subgraphs.context(of: table.owner(at: attribute2.id.index)),
            "addInput: attributes in different namespaces")
        recordRead(of: attribute2.id.index, by: attribute1.id.index)
    }
}
