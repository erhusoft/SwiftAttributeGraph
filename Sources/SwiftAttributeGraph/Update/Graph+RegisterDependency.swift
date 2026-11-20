extension Graph {
    /// Makes the running rule depend on `attribute` without reading its value (`AGGraphRegisterDependency` in native
    /// AttributeGraph). SwiftUI calls it from inside rules with options 0. The edge is recorded like a read, so a later
    /// change to `attribute` dirties the rule. Only the default options are modeled.
    public func registerDependency<Value>(on attribute: Attribute<Value>) {
        registerDependency(on: attribute.erased)
    }

    /// The untyped form of ``registerDependency(on:)-(Attribute<Value>)``.
    public func registerDependency(on attribute: AnyAttribute) {
        assertOwnThread()
        precondition(evaluatingNode != Graph.noNode, "registerDependency(on:): no rule is running")
        precondition(table.isLive(attribute.id), "registerDependency(on:): the attribute is dead")
        recordRead(of: attribute.id.index, by: evaluatingNode)
    }
}
