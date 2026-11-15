/// A typed handle to an attribute. It carries only the ID, so it is cheap to copy and does not retain the graph.
@propertyWrapper
public struct Attribute<Value>: Hashable, Sendable {
    /// The ID of the attribute inside its graph.
    public let id: AttributeID

    /// Creates a handle from an ID. The caller is responsible for the type matching the stored value.
    public init(id: AttributeID) { self.id = id }

    /// Creates a handle copying `attribute`.
    public init(_ attribute: Attribute<Value>) { self = attribute }

    /// The value of the attribute read from the graph whose rule is running on this thread (for `@Attribute` property
    /// wrapper usage inside a ``Rule`` or ``StatefulRule``).
    public var wrappedValue: Value { value }

    /// The attribute handle itself (`$property` when used as `@Attribute`).
    public var projectedValue: Attribute<Value> {
        get { self }
        set { self = newValue }
    }

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
