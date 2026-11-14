/// Type-erased holder of the value of a node. The common, non-generic parts of a node live in `NodeTable` arrays;
/// only the typed value (and the rule, if any) lives here.
class NodeBox {
    /// Runs the rule, stores its result and reports whether the value changed. Only rules override this.
    func evaluate(comparison: Comparison) -> Bool { fatalError("evaluate() called on a node that is not a rule") }
}

/// A box holding a value of a known type.
class TypedNode<Value>: NodeBox {
    var value: Value?

    init(value: Value?) { self.value = value }

    /// Stores `new` and returns whether it counts as a change under `comparison`.
    @inline(__always)
    final func store(_ new: Value, comparison: Comparison) -> Bool {
        if let old = value {
            if comparison.isEqual(old, new) { return false }
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

    init(body: @escaping () -> Value) {
        self.body = body
        super.init(value: nil)
    }

    override func evaluate(comparison: Comparison) -> Bool { store(body(), comparison: comparison) }
}

/// A rule given as a type that conforms to ``Rule``.
final class TypeRuleNode<R: Rule>: TypedNode<R.Value> {
    let rule: R

    init(rule: R) {
        self.rule = rule
        super.init(value: nil)
    }

    override func evaluate(comparison: Comparison) -> Bool { store(rule.value, comparison: comparison) }
}
