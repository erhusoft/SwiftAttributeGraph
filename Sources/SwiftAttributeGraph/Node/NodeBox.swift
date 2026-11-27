/// Type-erased holder of the value of a node. The common, non-generic parts of a node live in `NodeTable` arrays;
/// only the typed value (and the rule, if any) lives here.
@usableFromInline class NodeBox {
    /// The type of the value the node holds (`AnyAttribute.valueType` in native AttributeGraph).
    var valueType: Any.Type { Void.self }

    /// Runs the rule, stores its result and reports whether the value changed. Only rules override this.
    func evaluate(in graph: Graph, node: UInt32) -> Bool { fatalError("evaluate() called on a node that is not a rule") }
    /// Performs one step; only resumable rule nodes override this.
    func resume(in graph: Graph, node: AttributeID, firstStep: Bool) -> (step: RuleStep, changed: Bool) {
        preconditionFailure("resume() called on a node that is not resumable")
    }
    /// Mutates the stored rule body in place if its type is `R`, returning `true` when matched.
    func mutateRuleBody<R>(as type: R.Type, _ body: (inout R) -> Void) -> Bool { false }

    /// Returns the boxed value as `Any?` if available.
    func boxedValue() -> Any? { nil }

    /// Hands the stored body of a rule that is a typed ``Rule`` or ``StatefulRule`` to `visitor`, with its real type
    /// (`AnyAttribute.visitBody` in native AttributeGraph). A node without a typed body, such as an input or a rule given
    /// as a closure, visits nothing.
    func visitBody<V: AttributeBodyVisitor>(_ visitor: inout V) {}

    @usableFromInline init() {}
}

/// A box holding a value of a known type.
@usableFromInline class TypedNode<Value>: NodeBox {
    override func boxedValue() -> Any? { value }
    // Release builds skip the dynamic exclusivity check on the value, read on every attribute read (see `Graph`).
    // Every access copies the value in or out; none stays open while user code runs.
    #if DEBUG && !SAG_UNCHECKED
    @usableFromInline final var value: Value?
    #else
    @exclusivity(unchecked) @usableFromInline final var value: Value?
    #endif
    /// What the node shares with every node of its value type and comparison policy in the graph (the comparison, and
    /// how a closure rule runs).
    ///
    /// Shared rather than stored per node: a function per node for running a closure rule made each node 16 bytes
    /// larger, and creating 100,000 closure rules 7 % slower [O]; the shared descriptor also takes the place of the
    /// comparison function the node used to store (16 bytes and a retain of its context).
    @usableFromInline let type: NodeType<Value>

    override var valueType: Any.Type { Value.self }

    /// Whether two values count as the same, resolved from the attribute's policy and the type when it was created.
    @inlinable var isEqual: (Value, Value) -> Bool { type.isEqual }

    // `@inlinable` (like `store(_:)`) so that a caller specialized for `Value` builds and fills the node with static
    // types: compiled once here, generic, it asked the runtime for the metadata of `Optional<Value>` on every node
    // created or stored (7 % and 6 % of the `fan-out` profile) [O].
    @inlinable
    init(value: Value?, type: NodeType<Value>) {
        self.value = value
        self.type = type
    }

    /// Stores `new` and returns whether it counts as a change.
    @inlinable
    @inline(__always)
    final func store(_ new: Value) -> Bool {
        if let old = value {
            if type.isEqual(old, new) { return false }
        }
        value = new
        return true
    }
}

/// A leaf whose value is written from outside.
@usableFromInline final class InputNode<Value>: TypedNode<Value> {
    @inlinable
    override init(value: Value?, type: NodeType<Value>) {
        super.init(value: value, type: type)
    }
}

/// A rule given as a closure.
@usableFromInline final class ClosureRuleNode<Value>: TypedNode<Value> {
    @usableFromInline let body: () -> Value

    /// Creates the node. `type` must already hold ``NodeType/runClosureRule`` (see `Graph.makeRule`).
    @inlinable
    init(body: @escaping () -> Value, type: NodeType<Value>) {
        self.body = body
        super.init(value: nil, type: type)
    }

    /// Runs the rule through ``NodeType/runClosureRule``, which was compiled where a rule of this type was created,
    /// specialized for `Value`.
    ///
    /// Storing the result here, in a generic class compiled once and unspecialized, asked the runtime for the metadata
    /// of `Optional<Value>` and copied the value through value witnesses on every run [O].
    override func evaluate(in graph: Graph, node: UInt32) -> Bool {
        // `if let`, not `unsafelyUnwrapped`: the generic accessor returned the function at its most general
        // representation, and adapting it back allocated a context on every run [O].
        guard let run = type.runClosureRule else { preconditionFailure("a closure rule node without its run function") }
        return run(self)
    }
}

/// A rule given as a type that conforms to ``Rule``.
@usableFromInline final class TypeRuleNode<R: Rule>: TypedNode<R.Value> {
    @usableFromInline var rule: R
    @usableFromInline let runTypeRule: (TypeRuleNode<R>) -> Bool

    @inlinable
    init(rule: R, type: NodeType<R.Value>) {
        self.rule = rule
        self.runTypeRule = { node in
            let result = node.rule.value
            return node.store(result)
        }
        super.init(value: nil, type: type)
    }

    override func evaluate(in graph: Graph, node: UInt32) -> Bool {
        runTypeRule(self)
    }

    override func visitBody<V: AttributeBodyVisitor>(_ visitor: inout V) {
        withUnsafePointer(to: &rule) { visitor.visit(body: $0) }
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

    init(rule: R, type: NodeType<R.Value>) {
        self.rule = rule
        super.init(value: nil, type: type)
    }

    override func evaluate(in graph: Graph, node: UInt32) -> Bool {
        var context = RuleContext<R.Value>(graph: graph, node: node, value: value ?? R.initialValue)
        rule.updateValue(&context)
        return finish(context)
    }

    override func visitBody<V: AttributeBodyVisitor>(_ visitor: inout V) {
        withUnsafePointer(to: &rule) { visitor.visit(body: $0) }
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

    init(initialValue: Value?, body: @escaping (inout RuleContext<Value>) -> Void, type: NodeType<Value>) {
        self.body = body
        self.initialValue = initialValue
        super.init(value: nil, type: type)
    }

    override func evaluate(in graph: Graph, node: UInt32) -> Bool {
        var context = RuleContext<Value>(graph: graph, node: node, value: value ?? initialValue)
        body(&context)
        return finish(context)
    }
}

/// The attribute `Rule._cachedValue` creates: its body is a closure that gets a copy of the rule's storage and the attribute,
/// and writes the value through a ``RuleContext`` built from that attribute (`c13` in the oracle).
final class RawCachedRuleNode<Value>: TypedNode<Value> {
    let storage: UnsafeMutableRawPointer
    let destroyStorage: (UnsafeMutableRawPointer) -> Void
    let update: (UnsafeMutableRawPointer, AnyAttribute) -> Void
    let typeName: String
    /// A heap copy of the value that ``Rule/_cachedValue(options:owner:hashValue:bodyPtr:update:)`` hands out as a pointer.
    private var exported: UnsafeMutablePointer<Value>?
    /// The value a ``RuleContext`` built from this attribute wrote while the body ran (`RuleContext.init(attribute:)`).
    var written: Value?

    init(storage: UnsafeMutableRawPointer, destroyStorage: @escaping (UnsafeMutableRawPointer) -> Void,
         update: @escaping (UnsafeMutableRawPointer, AnyAttribute) -> Void, typeName: String, type: NodeType<Value>) {
        self.storage = storage
        self.destroyStorage = destroyStorage
        self.update = update
        self.typeName = typeName
        super.init(value: nil, type: type)
    }

    deinit {
        destroyStorage(storage)
        if let exported {
            exported.deinitialize(count: 1)
            exported.deallocate()
        }
    }

    override func evaluate(in graph: Graph, node: UInt32) -> Bool {
        written = nil
        update(storage, AnyAttribute(id: AttributeID(index: node, generation: graph.table.generations[Int(node)])))
        guard let new = written else {
            precondition(value != nil, "attribute failed to set an initial value: \(node), \(typeName)")
            return false
        }
        written = nil
        return store(new)
    }

    /// A pointer to a copy of the current value, valid until the next call or until the node dies.
    func exportedPointer() -> UnsafePointer<Value> {
        if let exported {
            exported.pointee = value.unsafelyUnwrapped
        } else {
            let pointer = UnsafeMutablePointer<Value>.allocate(capacity: 1)
            pointer.initialize(to: value.unsafelyUnwrapped)
            exported = pointer
        }
        return UnsafePointer(exported.unsafelyUnwrapped)
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
