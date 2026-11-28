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
        precondition(table.isLive(attribute1.id), "attribute being read has no value: \(attribute1.id.rawValue)")
        precondition(table.isLive(attribute2.id), "reading from invalid source attribute: \(attribute2.id.rawValue)")
        precondition(attribute1.id != attribute2.id, "cyclic edge: \(attribute2.id.rawValue) -> \(attribute1.id.rawValue)")
        precondition(
            attribute1.id.graphTag == attribute2.id.graphTag,
            "attribute references can't cross graph namespaces"
        )
        precondition(
            subgraphs.context(of: table.owner(at: attribute1.id.index)) ==
                subgraphs.context(of: table.owner(at: attribute2.id.index)),
            "attribute references can't cross graph namespaces")
        // An edge that already exists is left as it is: adding it again reads nothing, so the version the rule saw must not move (fuzzer seed
        // 19905: the rule would have kept a stale value).
        if table.inputs[Int(attribute1.id.index)].contains(where: { $0.source == attribute2.id.index }) { return }
        recordRead(of: attribute2.id.index, by: attribute1.id.index)
    }
}
