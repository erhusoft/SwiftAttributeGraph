/// Type-erased holder of the value of a node. The common, non-generic parts of a node live in `NodeTable` arrays;
/// only the typed value (and the rule, if any) lives here.
@usableFromInline class NodeBox {
    /// Runs the rule, stores its result and reports whether the value changed. Only rules override this.
    func evaluate(in graph: Graph, node: UInt32) -> Bool { fatalError("evaluate() called on a node that is not a rule") }
    /// Performs one step; only resumable rule nodes override this.
    func resume(in graph: Graph, node: AttributeID, firstStep: Bool) -> (step: RuleStep, changed: Bool) {
        preconditionFailure("resume() called on a node that is not resumable")
    }
    /// Mutates the stored rule body in place if its type is `R`, returning `true` when matched.
    func mutateRuleBody<R>(as type: R.Type, _ body: (inout R) -> Void) -> Bool { false }
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

    override func evaluate(in graph: Graph, node: UInt32) -> Bool {
        let result = body()
        if graph.isCurrentFrameCancelled, graph.table.state[Int(node)] & NodeState.hasValue != 0 { return false }
        return store(result)
    }
}

/// A rule given as a type that conforms to ``Rule``.
final class TypeRuleNode<R: Rule>: TypedNode<R.Value> {
    var rule: R

    init(rule: R, isEqual: @escaping (R.Value, R.Value) -> Bool) {
        self.rule = rule
        super.init(value: nil, isEqual: isEqual)
    }

    override func evaluate(in graph: Graph, node: UInt32) -> Bool {
        let result = rule.value
        if graph.isCurrentFrameCancelled, graph.table.state[Int(node)] & NodeState.hasValue != 0 { return false }
        return store(result)
    }

    override func mutateRuleBody<Target>(as type: Target.Type, _ body: (inout Target) -> Void) -> Bool {
        guard R.self == Target.self else { return false }
        return withUnsafeMutablePointer(to: &rule) { ptr in
            ptr.withMemoryRebound(to: Target.self, capacity: 1) { targetPtr in
                body(&targetPtr.pointee)
                return true
            }
        }
    }
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
        if graph.isCurrentFrameCancelled, graph.table.state[Int(node)] & NodeState.hasValue != 0 { return false }
        return finish(context)
    }

    override func mutateRuleBody<Target>(as type: Target.Type, _ body: (inout Target) -> Void) -> Bool {
        guard R.self == Target.self else { return false }
        return withUnsafeMutablePointer(to: &rule) { ptr in
            ptr.withMemoryRebound(to: Target.self, capacity: 1) { targetPtr in
                body(&targetPtr.pointee)
                return true
            }
        }
    }
}

/// Type-erased base for ``IndirectNode`` so subgraph invalidation can reset an indirect attribute's source to its
/// initial source without knowing its generic value type.
class AnyIndirectNode: NodeBox {
    /// The attribute this indirect redirected to when it was first created.
    let initialSource: AttributeID
    /// The attribute this indirect currently redirects to.
    var source: AttributeID
    /// An optional producer attribute in the same subgraph that updates before `source` (and may call `setSource`).
    var dependency: AttributeID?
    /// Last verified version of `source` (0 until `source` has a value), used so a `dependency` run that does not
    /// change `source` or its value cuts downstream readers of the indirect attribute.
    var sourceSeenVersion: UInt32
    /// Set by `setSource(_:for:)` so `update(_:)` knows `source` was redirected since the indirect was last verified.
    var sourceRedirected = false

    init(source: AttributeID, sourceSeenVersion: UInt32) {
        self.initialSource = source
        self.source = source
        self.sourceSeenVersion = sourceSeenVersion
    }
}

/// A node that redirects to another attribute. It has no value of its own: reading
/// it reads the source, and writing it writes to the source (when the terminal source is an input).
final class IndirectNode<Value>: AnyIndirectNode {}

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
