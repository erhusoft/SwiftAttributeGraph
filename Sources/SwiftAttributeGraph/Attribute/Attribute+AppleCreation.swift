extension Attribute {
    /// The attribute with this identifier (`Attribute.init(identifier:)` in native AttributeGraph); nothing is checked.
    public init(identifier: AnyAttribute) {
        self.init(id: identifier.id)
    }

    /// The erased attribute (`Attribute.identifier` in native AttributeGraph). Setting it points this handle at another attribute.
    public var identifier: AnyAttribute {
        get { AnyAttribute(id: id) }
        set { self = Attribute(id: newValue.id) }
    }

    /// The graph of the current subgraph, or the program stops as native does (`attempting to create attribute with no subgraph: <body type>`;
    /// measured on macOS 15.8.3 for a value, a rule and a stateful rule).
    private static func graphOfTheCurrentSubgraph(creating body: Any.Type) -> Graph {
        guard let current = Subgraph.current else {
            preconditionFailure("attempting to create attribute with no subgraph: \(body)")
        }
        return current.graph
    }

    /// An input holding `value`, made in the current subgraph (`Attribute.init(value:)` in native AttributeGraph). Its body is `External<Value>`,
    /// which compares its values as `equatableAlways`. Stops the program when no subgraph is current.
    public init(value: Value) {
        let graph = Attribute.graphOfTheCurrentSubgraph(creating: External<Value>.self)
        self = graph.makeInput(value, comparison: .comparison(.equatableAlways))
    }

    /// An input that has no value yet, made in the current subgraph (`Attribute.init(type:)` in native AttributeGraph). Its value state is
    /// dirty and pending until it is written; reading it before stops the program. Native keeps the dirty and pending bits after the first write
    /// (value state 11); the engine clears them (8).
    public init(type _: Value.Type) {
        let graph = Attribute.graphOfTheCurrentSubgraph(creating: External<Value>.self)
        self = graph.makeEmptyInput(Value.self)
    }

    /// An attribute computed by `rule`, made in the current subgraph (`Attribute.init(_:)` for a ``Rule`` in native AttributeGraph).
    public init<R: Rule>(_ rule: R) where Value == R.Value {
        self = Attribute.graphOfTheCurrentSubgraph(creating: R.self).makeRule(rule)
    }

    /// An attribute computed by a stateful rule, made in the current subgraph (`Attribute.init(_:)` for a ``StatefulRule`` in native AttributeGraph).
    public init<R: StatefulRule>(_ rule: R) where Value == R.Value {
        self = Attribute.graphOfTheCurrentSubgraph(creating: R.self).makeStatefulRule(rule)
    }
}

extension Graph {
    /// An input with no value: dirty and pending, so that reading it goes through its update and stops the program until it is written.
    func makeEmptyInput<Value>(_ type: Value.Type, comparison: ValuePolicy = .comparison(.equatableAlways)) -> Attribute<Value> {
        assertOwnThread()
        let node = InputNode<Value>(value: nil, type: nodeType(comparison, for: Value.self))
        return Attribute(id: allocateEmptyInput(node))
    }

    func allocateEmptyInput(_ node: NodeBox) -> AttributeID {
        if let primary {
            return primary.withCurrent(Subgraph(id: currentSubgraph)) {
                primary.allocateEmptyInput(node)
            }
        }
        let id = allocate(node, state: NodeState.dirty | NodeState.pending)
        changeCount &+= 1
        return id
    }

    /// The first write of an input made with no value gives it one: it stops being dirty and pending.
    @inline(__always)
    func markFirstValue(of index: Int) {
        if table.state[index] & NodeState.hasValue == 0 {
            table.state[index] = (table.state[index] & ~(NodeState.dirty | NodeState.pending)) | NodeState.hasValue
        }
    }
}
