/// A typed handle to an attribute. It carries only the ID, so it is cheap to copy and does not retain the graph.
public struct Attribute<Value> {
    /// The ID of the attribute inside its graph.
    public let id: AttributeID

    /// Creates a handle from an ID. The caller is responsible for the type matching the stored value.
    public init(id: AttributeID) { self.id = id }

    /// The handle without its value type.
    public var erased: AnyAttribute { AnyAttribute(id: id) }
}

/// A handle to an attribute whose value type is not known at the use site.
public struct AnyAttribute: Hashable, Sendable {
    /// The ID of the attribute inside its graph.
    public let id: AttributeID

    /// Creates a handle from an ID.
    public init(id: AttributeID) { self.id = id }
}
