/// A typed handle to an attribute. It carries only the ID, so it is cheap to copy and does not retain the graph.
@dynamicMemberLookup
@propertyWrapper
public struct Attribute<Value>: Hashable, Sendable {
    /// The ID of the attribute inside its graph.
    public let id: AttributeID

    /// Creates a handle from an ID. The caller is responsible for the type matching the stored value.
    @inlinable public init(id: AttributeID) { self.id = id }

    /// Creates a handle copying `attribute`.
    @inlinable public init(_ attribute: Attribute<Value>) { self = attribute }

    /// The value of the attribute read from the graph whose rule is running on this thread (for `@Attribute` property
    /// wrapper usage inside a ``Rule`` or ``StatefulRule``).
    @inlinable public var wrappedValue: Value { value }

    /// The attribute handle itself (`$property` when used as `@Attribute`).
    @inlinable public var projectedValue: Attribute<Value> {
        get { self }
        set { self = newValue }
    }

    /// Projects a field of `Value` into a ``Focus`` child attribute in the graph whose rule is running on this thread.
    public subscript<Member>(dynamicMember keyPath: KeyPath<Value, Member>) -> Attribute<Member> {
        self[keyPath: keyPath]
    }

    /// Projects a field of `Value` into a ``Focus`` child attribute in the graph whose rule is running on this thread.
    public subscript<Member>(keyPath keyPath: KeyPath<Value, Member>) -> Attribute<Member> {
        guard let graph = ThreadLocalGraph.current() else {
            preconditionFailure("Attribute[keyPath:] can only be used inside a rule; use Graph.makeFocus(_:keyPath:) elsewhere")
        }
        return graph.makeFocus(self, keyPath: keyPath)
    }

    /// The handle without its value type.
    @inlinable public var erased: AnyAttribute { AnyAttribute(id: id) }
}

/// A handle to an attribute whose value type is not known at the use site.
public struct AnyAttribute: Hashable, Sendable {
    /// The ID of the attribute inside its graph.
    public let id: AttributeID

    /// Creates a handle from an ID.
    @inlinable public init(id: AttributeID) { self.id = id }
}
