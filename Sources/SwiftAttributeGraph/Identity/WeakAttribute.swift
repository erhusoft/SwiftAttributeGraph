/// A weak reference to an attribute: it does not keep the attribute's subgraph alive, and resolves to `nil` once that
/// subgraph has been invalidated and freed.
public struct WeakAttribute<Value>: Hashable, Sendable {
    /// The underlying attribute ID, or `nil` if initialized empty.
    public var id: AttributeID?

    /// Creates an empty weak attribute that always resolves to `nil`.
    public init() {
        self.id = nil
    }

    /// Creates a weak reference to `attribute`.
    public init(_ attribute: Attribute<Value>) {
        self.id = attribute.id
    }

    /// Creates a weak reference to an optional `attribute`.
    public init(_ attribute: Attribute<Value>?) {
        self.id = attribute?.id
    }

    /// The value of the referenced attribute read from the graph whose rule is running on this thread, or `nil` if the
    /// attribute is no longer alive.
    ///
    /// Reading inside a rule while the target attribute is alive records a dependency on that target attribute.
    public var value: Value? {
        guard let graph = ThreadLocalGraph.current() else {
            preconditionFailure("WeakAttribute.value can only be read inside a rule; use Graph.value(of:) elsewhere")
        }
        return graph.value(of: self)
    }
}

extension Graph {
    /// Returns the strong `Attribute` handle if the referenced attribute is still alive in the graph, or `nil` if its
    /// subgraph was invalidated and freed.
    public func attribute<Value>(of weakAttribute: WeakAttribute<Value>) -> Attribute<Value>? {
        assertOwnThread()
        guard let id = weakAttribute.id, table.isLive(id) else { return nil }
        return Attribute(id: id)
    }

    /// Reads the value of `weakAttribute` if its target attribute is still alive, bringing it up to date first if
    /// needed (and recording a dependency when called inside a rule), or returns `nil` if the target was freed.
    public func value<Value>(of weakAttribute: WeakAttribute<Value>) -> Value? {
        assertOwnThread()
        if let running = ThreadLocalGraph.current() {
            precondition(running === self, "a rule cannot read an attribute of another graph")
        }
        guard let id = weakAttribute.id, table.isLive(id) else { return nil }
        return read(Attribute<Value>(id: id))
    }

    /// Reads the value of `weakAttribute` and reports whether it changed since the running rule's previous evaluation
    /// (or since the attribute was last verified when called outside a rule), or returns `nil` if the target was freed.
    public func changedValue<Value>(of weakAttribute: WeakAttribute<Value>) -> (value: Value, changed: Bool)? {
        assertOwnThread()
        guard let id = weakAttribute.id, table.isLive(id) else { return nil }
        let attr = Attribute<Value>(id: id)
        let node = evaluatingNode
        let val = read(attr)
        if node != Graph.noNode {
            return (val, inputChanged(of: node, attribute: attr))
        }
        return (val, false)
    }
}
