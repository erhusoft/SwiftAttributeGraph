/// Attribute accessors with the names Apple uses in `AGAttribute` (`hasValue`, `flags`; `value` already exists inside rules) [O, native headers
/// AGAttribute.h]. They resolve the owning graph from the attribute's tag. The graph-level methods stay for hot paths.
extension Attribute {
    /// Whether the attribute has a value (`AGAttribute.hasValue`).
    public var hasValue: Bool {
        guard let graph = GraphRegistry.graph(forTag: id.graphTag) else { return false }
        return graph.hasValue(of: self)
    }

    /// The attribute's flags (`AGAttribute.flags`).
    public var flags: AttributeFlags {
        get {
            guard let graph = GraphRegistry.graph(forTag: id.graphTag) else { return [] }
            return graph.flags(of: self)
        }
        nonmutating set {
            guard let graph = GraphRegistry.graph(forTag: id.graphTag) else {
                preconditionFailure("Attribute flags set after its graph was released")
            }
            graph.setFlags(newValue, for: self)
        }
    }
}
