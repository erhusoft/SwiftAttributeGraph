

/// A type-erased rule execution context (`AttributeGraph.AnyRuleContext`).
///
/// Allows dynamic, type-agnostic inspection and mutation of the evaluating attribute
/// and dependency reads during rule updates.
public struct AnyRuleContext: Equatable {
    private unowned(unsafe) let graph: Graph
    private let node: UInt32

    /// The attribute that owns this context (`AnyRuleContext.attribute`).
    public var attribute: AnyAttribute {
        get {
            AnyAttribute(id: AttributeID(index: node, generation: graph.table.generations[Int(node)]))
        }
        set {
            precondition(graph.contains(newValue.id), "AnyRuleContext: attribute is dead")
        }
    }

    /// Creates an untyped rule context for `attribute` (`AnyRuleContext.init(attribute:)`).
    public init(attribute: AnyAttribute) {
        guard let graph = GraphRegistry.graph(forTag: attribute.id.graphTag) else {
            preconditionFailure("AnyRuleContext created after graph was released")
        }
        self.graph = graph
        self.node = attribute.id.index
    }

    /// Creates an untyped rule context from a typed `RuleContext<Value>`.
    public init<Value>(_ context: RuleContext<Value>) {
        self.init(attribute: context.attribute.erased)
    }

    /// Reinterprets this context as a typed `RuleContext<Value>`.
    public func unsafeCast<Value>(to type: Value.Type = Value.self) -> RuleContext<Value> {
        let typedAttr = Attribute<Value>(id: attribute.id)
        return RuleContext<Value>(attribute: typedAttr)
    }

    /// Runs `body` within this rule context (`AnyRuleContext.update(body:)`).
    public func update(body: () -> Void) {
        let previous = graph.evaluatingNode
        graph.evaluatingNode = node
        defer { graph.evaluatingNode = previous }
        body()
    }

    /// Reads `attribute` as a dependency and reports whether it changed.
    public func changedValue<Value>(
        of attribute: Attribute<Value>,
        options: AGValueOptions = []
    ) -> (value: Value, changed: Bool) {
        let val = graph.value(of: attribute, options: Graph.ReadOptions(rawValue: options.rawValue))
        return (val, graph.inputChanged(of: node, source: attribute.id.index) ?? true)
    }

    /// Reads `attribute` as a dependency and returns its value and change flags.
    public func valueAndFlags<Value>(
        of attribute: Attribute<Value>,
        options: AGValueOptions = []
    ) -> (value: Value, flags: AGChangedValueFlags) {
        let res = changedValue(of: attribute, options: options)
        return (res.value, res.changed ? .changed : [])
    }

    /// Reads `attribute` as a dependency (`AnyRuleContext.subscript(Attribute)`).
    public subscript<Value>(attribute: Attribute<Value>) -> Value {
        graph.value(of: attribute)
    }

    /// Reads `weakAttribute` if live as a dependency (`AnyRuleContext.subscript(WeakAttribute)`).
    public subscript<Value>(weakAttribute: WeakAttribute<Value>) -> Value? {
        graph.value(of: weakAttribute)
    }

    /// Reads `optionalAttribute` if present as a dependency (`AnyRuleContext.subscript(OptionalAttribute)`).
    public subscript<Value>(optionalAttribute: OptionalAttribute<Value>) -> Value? {
        graph.value(of: optionalAttribute)
    }

    /// Whether both contexts are for the same node of the same graph.
    public static func == (lhs: AnyRuleContext, rhs: AnyRuleContext) -> Bool {
        lhs.graph === rhs.graph && lhs.node == rhs.node
    }
}
