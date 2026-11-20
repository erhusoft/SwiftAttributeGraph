/// An untyped weak reference to an attribute (`AGWeakAttribute`, `AnyWeakAttribute` in native AttributeGraph). It does not
/// keep the attribute's subgraph alive, and it resolves to `nil` once that subgraph has been invalidated and freed.
public struct AnyWeakAttribute: Hashable, Sendable {
    /// The underlying attribute ID, or `nil` if empty.
    public var id: AttributeID?

    /// Creates a weak reference to `attribute`, or an empty one when `attribute` is `nil`.
    public init(_ attribute: AnyAttribute?) {
        self.id = attribute?.id
    }

    /// Creates an untyped weak reference from a typed one.
    public init<Value>(_ weakAttribute: WeakAttribute<Value>) {
        self.id = weakAttribute.id
    }

    /// The strong attribute if it is still alive, or `nil` if it is empty or its subgraph was invalidated and freed
    /// (`AGWeakAttributeGetAttribute` in native AttributeGraph).
    public var attribute: AnyAttribute? {
        get {
            guard let id, let graph = GraphRegistry.graph(forTag: id.graphTag) else { return nil }
            return graph.anyAttribute(of: self)
        }
        set {
            id = newValue?.id
        }
    }

    /// Reinterprets the reference as a typed weak attribute of `Value` (the caller must know the type).
    public func unsafeCast<Value>(to _: Value.Type) -> WeakAttribute<Value> {
        var typed = WeakAttribute<Value>()
        typed.id = id
        return typed
    }
}

extension Graph {
    /// The strong attribute behind an untyped weak reference, or `nil` if it is empty or was freed.
    public func anyAttribute(of weakAttribute: AnyWeakAttribute) -> AnyAttribute? {
        assertOwnThread()
        guard let id = weakAttribute.id else { return nil }
        if id.graphTag == graphTag {
            guard table.isLive(id) else { return nil }
            return AnyAttribute(id: id)
        }
        guard let owner = GraphRegistry.graph(forTag: id.graphTag) else { return nil }
        return owner.anyAttribute(of: weakAttribute)
    }
}
