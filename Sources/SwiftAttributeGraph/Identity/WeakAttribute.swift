/// A weak reference to an attribute: it does not keep the attribute's subgraph alive, and resolves to `nil` once that
/// subgraph has been invalidated and freed.
@dynamicMemberLookup
@propertyWrapper
public struct WeakAttribute<Value>: Hashable, Sendable {
    /// The underlying attribute ID, or `nil` if initialized empty.
    public var id: AttributeID?

    /// Creates an empty weak attribute that always resolves to `nil`.
    public init() {
        self.id = nil
    }

    /// Creates a weak attribute from its erased form (`WeakAttribute.init(base:)` in native AttributeGraph).
    public init(base: AnyWeakAttribute) {
        self.id = base.id
    }

    /// Creates a weak reference to `attribute`.
    public init(_ attribute: Attribute<Value>) {
        self.id = attribute.id
    }

    /// Creates a weak reference to an optional `attribute`.
    public init(_ attribute: Attribute<Value>?) {
        self.id = attribute?.id
    }

    /// Returns the strong `Attribute` handle if the referenced attribute is still alive in its graph, or `nil` if its
    /// subgraph was invalidated and freed (`AGWeakAttributeGetAttribute` in native AttributeGraph [O]).
    public var attribute: Attribute<Value>? {
        get {
            guard let id, let graph = GraphRegistry.graph(forTag: id.graphTag) else { return nil }
            return graph.attribute(of: self)
        }
        set {
            id = newValue?.id
        }
    }

    /// Projects a field of the referenced attribute into a child attribute, or `nil` if the target is not alive
    /// (`WeakAttribute.subscript(dynamicMember:)` in native AttributeGraph).
    public subscript<Member>(dynamicMember keyPath: KeyPath<Value, Member>) -> Attribute<Member>? {
        attribute.map { $0[keyPath: keyPath] }
    }

    /// The value of the referenced attribute, bringing it up to date first if needed, or `nil` if the attribute is no
    /// longer alive (`AGGraphGetWeakValue` in native AttributeGraph [O]).
    ///
    /// Reading inside a rule while the target attribute is alive records a dependency on that target attribute; reading
    /// outside a rule updates the target if dirty and returns its value without recording any dependency [O].
    public var value: Value? {
        if let graph = ThreadLocalGraph.current() {
            return graph.value(of: self)
        }
        guard let id, let graph = GraphRegistry.graph(forTag: id.graphTag) else { return nil }
        return graph.value(of: self)
    }

    /// Reads the value of the referenced attribute with `options` and reports whether it changed (`WeakAttribute.changedValue`
    /// in native AttributeGraph [O]), or returns `nil` if the target was freed.
    public func changedValue(options: Graph.ReadOptions = []) -> (value: Value, changed: Bool)? {
        if let graph = ThreadLocalGraph.current() {
            return graph.changedValue(of: self, options: options)
        }
        guard let id, let graph = GraphRegistry.graph(forTag: id.graphTag) else { return nil }
        return graph.changedValue(of: self, options: options)
    }

    /// The value of the referenced attribute when used as `@WeakAttribute`, or `nil` if the target was invalidated and
    /// freed.
    public var wrappedValue: Value? { value }

    /// The weak attribute wrapper itself (`$property` when used as `@WeakAttribute`).
    public var projectedValue: WeakAttribute<Value> {
        get { self }
        set { self = newValue }
    }
}

extension Graph {
    /// Returns the strong `Attribute` handle if the referenced attribute is still alive, or `nil` if its subgraph was
    /// invalidated and freed.
    public func attribute<Value>(of weakAttribute: WeakAttribute<Value>) -> Attribute<Value>? {
        assertOwnThread()
        guard let id = weakAttribute.id else { return nil }
        if id.graphTag == graphTag {
            guard table.isLive(id) else { return nil }
            return Attribute(id: id)
        }
        guard let owner = GraphRegistry.graph(forTag: id.graphTag) else { return nil }
        return owner.attribute(of: weakAttribute)
    }

    /// Reads the value of `weakAttribute` if its target attribute is still alive, bringing it up to date first if
    /// needed (and recording a dependency when called inside a rule), or returns `nil` if the target was freed.
    public func value<Value>(of weakAttribute: WeakAttribute<Value>) -> Value? {
        assertOwnThread()
        guard let id = weakAttribute.id else { return nil }
        if let running = ThreadLocalGraph.current() {
            precondition((running === self || running.graphTag == self.graphTag) && id.graphTag == graphTag, "a rule cannot read an attribute of another graph")
            guard table.isLive(id) else { return nil }
            return value(of: Attribute<Value>(id: id))
        }
        if id.graphTag == graphTag {
            guard table.isLive(id) else { return nil }
            return value(of: Attribute<Value>(id: id))
        }
        guard let owner = GraphRegistry.graph(forTag: id.graphTag) else { return nil }
        return owner.value(of: weakAttribute)
    }

    /// Reads the value of `weakAttribute` with `options` if its target attribute is still alive, bringing it up to date
    /// first if needed, or returns `nil` if the target was freed (`AGGraphGetWeakValue` in native AttributeGraph [O]).
    public func value<Value>(of weakAttribute: WeakAttribute<Value>, options: ReadOptions) -> Value? {
        if options.contains(.noDependency) {
            return withoutUpdate { value(of: weakAttribute) }
        }
        return value(of: weakAttribute)
    }

    /// Reads the value of `weakAttribute` and reports whether it changed since the running rule's previous evaluation
    /// (or since the attribute was last verified when called outside a rule), or returns `nil` if the target was freed.
    public func changedValue<Value>(of weakAttribute: WeakAttribute<Value>, options: ReadOptions = []) -> (value: Value, changed: Bool)? {
        assertOwnThread()
        if options.contains(.noDependency) {
            return withoutUpdate {
                guard let val = value(of: weakAttribute) else { return nil }
                return (val, false)
            }
        }
        guard let id = weakAttribute.id else { return nil }
        if id.graphTag != graphTag {
            precondition(ThreadLocalGraph.current() == nil, "a rule cannot read an attribute of another graph")
            guard let owner = GraphRegistry.graph(forTag: id.graphTag) else { return nil }
            return owner.changedValue(of: weakAttribute, options: options)
        }
        guard table.isLive(id) else { return nil }
        let attr = Attribute<Value>(id: id)
        let node = evaluatingNode
        let val = value(of: attr)
        if node != Graph.noNode {
            return (val, inputChanged(of: node, attribute: attr))
        }
        return (val, false)
    }
}
