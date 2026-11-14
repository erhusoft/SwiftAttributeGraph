/// Type-erased holder of the value of a node. The common, non-generic parts of a node live in `NodeTable` arrays;
/// only the typed value (and the rule, if any) lives here.
@usableFromInline class NodeBox {
    /// Runs the rule, stores its result and reports whether the value changed. Only rules override this.
    func evaluate(in graph: Graph, node: UInt32) -> Bool { fatalError("evaluate() called on a node that is not a rule") }
    /// Performs one step; only resumable rule nodes override this.
    func resume(in graph: Graph, node: AttributeID, firstStep: Bool) -> (step: RuleStep, changed: Bool) {
        preconditionFailure("resume() called on a node that is not resumable")
    }
}

/// A box holding a value of a known type.
@usableFromInline class TypedNode<Value>: NodeBox {
    @usableFromInline var value: Value?
    /// Whether two values count as the same, resolved from the attribute's policy and the type when it was created.
    let isEqual: (Value, Value) -> Bool

    init(value: Value?, isEqual: @escaping (Value, Value) -> Bool) {
        self.value = value
        self.isEqual = isEqual
    }

    /// Stores `new` and returns whether it counts as a change.
    @inline(__always)
    final func store(_ new: Value) -> Bool {
        if let old = value {
            if isEqual(old, new) { return false }
        }
        value = new
        return true
    }
}

/// A leaf whose value is written from outside.
final class InputNode<Value>: TypedNode<Value> {}

/// A rule given as a closure.
final class ClosureRuleNode<Value>: TypedNode<Value> {
    let body: () -> Value

    init(body: @escaping () -> Value, isEqual: @escaping (Value, Value) -> Bool) {
        self.body = body
        super.init(value: nil, isEqual: isEqual)
    }

    override func evaluate(in graph: Graph, node: UInt32) -> Bool { store(body()) }
}

/// A rule given as a type that conforms to ``Rule``.
final class TypeRuleNode<R: Rule>: TypedNode<R.Value> {
    let rule: R

    init(rule: R, isEqual: @escaping (R.Value, R.Value) -> Bool) {
        self.rule = rule
        super.init(value: nil, isEqual: isEqual)
    }

    override func evaluate(in graph: Graph, node: UInt32) -> Bool { store(rule.value) }
}

/// A rule given as a type that conforms to ``StatefulRule``.
final class StatefulRuleNode<R: StatefulRule>: TypedNode<R.Value> {
    var rule: R

    init(rule: R, isEqual: @escaping (R.Value, R.Value) -> Bool) {
        self.rule = rule
        super.init(value: nil, isEqual: isEqual)
    }

    override func evaluate(in graph: Graph, node: UInt32) -> Bool {
        var context = RuleContext<R.Value>(graph: graph, node: node, value: value ?? R.initialValue)
        rule.updateValue(&context)
        return finish(context)
    }
}

/// A stateful rule given as a closure.
final class ClosureStatefulRuleNode<Value>: TypedNode<Value> {
    let body: (inout RuleContext<Value>) -> Void
    let initialValue: Value?

    init(initialValue: Value?, body: @escaping (inout RuleContext<Value>) -> Void, isEqual: @escaping (Value, Value) -> Bool) {
        self.body = body
        self.initialValue = initialValue
        super.init(value: nil, isEqual: isEqual)
    }

    override func evaluate(in graph: Graph, node: UInt32) -> Bool {
        var context = RuleContext<Value>(graph: graph, node: node, value: value ?? initialValue)
        body(&context)
        return finish(context)
    }
}

extension TypedNode {
    /// Takes the outcome of a stateful rule: a written value goes through the comparison; without a write the value
    /// stays (the initial one, on the first run) and the attribute did not change.
    @inline(__always)
    final func finish(_ context: RuleContext<Value>) -> Bool {
        if context.wasWritten { return store(context.result.unsafelyUnwrapped) }
        if value == nil {
            guard let initial = context.result else {
                preconditionFailure("a stateful rule must write a value on its first run when it has no initialValue")
            }
            value = initial
        }
        return false
    }
}
