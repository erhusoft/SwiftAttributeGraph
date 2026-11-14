/// Type-erased holder of the value of a node. The common, non-generic parts of a node live in `NodeTable` arrays;
/// only the typed value (and the rule, if any) lives here.
class NodeBox {
    /// Runs the rule, stores its result and reports whether the value changed. Only rules override this.
    func evaluate() -> Bool { fatalError("evaluate() called on a node that is not a rule") }
}

/// A box holding a value of a known type.
class TypedNode<Value>: NodeBox {
    var value: Value?
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

    override func evaluate() -> Bool { store(body()) }
}

/// A rule given as a type that conforms to ``Rule``.
final class TypeRuleNode<R: Rule>: TypedNode<R.Value> {
    let rule: R

    init(rule: R, isEqual: @escaping (R.Value, R.Value) -> Bool) {
        self.rule = rule
        super.init(value: nil, isEqual: isEqual)
    }

    override func evaluate() -> Bool { store(rule.value) }
}
