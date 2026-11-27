/// What a ``StatefulRule`` sees while it runs: its value so far and which inputs changed since its previous run.
///
/// "Changed" means the version of the source differs from the one the rule saw the last time it ran. An attribute the
/// rule reads for the first time counts as changed, and so does every input on the first run. The context lives for one
/// call of `updateValue` and must not be kept.
public struct RuleContext<Value> {
    private unowned(unsafe) let graph: Graph
    private let node: UInt32
    /// The value and whether it was written live in a box, so that `value` can be set through a context that is not a
    /// variable (`RuleContext(attribute:).value = x`, as native allows).
    private final class State {
        var current: Value?
        var wasWritten = false
        init(_ current: Value?) { self.current = current }
    }
    private let state: State
    private var current: Value? {
        get { state.current }
        nonmutating set { state.current = newValue }
    }
    private(set) var wasWritten: Bool {
        get { state.wasWritten }
        nonmutating set { state.wasWritten = newValue }
    }
    /// Set by ``init(attribute:)``: a write is also handed to the node that is evaluating, if it takes writes made this way.
    private var forwardsWrites = false

    init(graph: Graph, node: UInt32, value: Value?) {
        self.graph = graph
        self.node = node
        self.state = State(value)
    }

    /// Creates a rule context referencing `attribute` directly (`RuleContext.init(attribute:)`).
    public init(attribute: Attribute<Value>) {
        guard let graph = GraphRegistry.graph(forTag: attribute.id.graphTag) else {
            preconditionFailure("RuleContext created after graph was released")
        }
        precondition(graph.table.isLive(attribute.id), "RuleContext: the attribute is dead")
        self.graph = graph
        self.node = attribute.id.index
        // Only refers to the attribute: its stored value is taken as it is, without evaluating it. Reading it through the
        // graph would make a rule that builds a context for itself read itself (a cycle); native does not read it either
        // (oracle scenario `cov79-a-unsafe-cast`).
        self.state = State((graph.table.box(at: attribute.id.index) as? TypedNode<Value>)?.value)
        self.forwardsWrites = true
    }

    /// The attribute that owns this context (`RuleContext.attribute`).
    public var attribute: Attribute<Value> {
        get {
            Attribute<Value>(id: AttributeID(index: node, generation: graph.table.generations[Int(node)]))
        }
        set {
            // Re-pointing the context to another attribute
            precondition(graph.contains(newValue.id), "RuleContext: attribute is dead")
        }
    }

    /// The value the attribute has: the previous one when the rule starts. Writing it makes the attribute take the
    /// new value, which raises its version only if it counts as different under the attribute's comparison policy.
    public var value: Value {
        get {
            guard let current else { preconditionFailure("RuleContext.value: the rule has no value yet (first run without an initialValue)") }
            return current
        }
        nonmutating set {
            current = newValue
            wasWritten = true
            if forwardsWrites, graph.evaluatingNode == node,
               let raw = graph.table.box(at: node) as? RawCachedRuleNode<Value> { raw.written = newValue }
        }
    }

    /// The value after the rule ran, or `nil` if it never had one.
    var result: Value? { current }

    /// Whether the attribute has a value to read: false only on a first run without an `initialValue`.
    public var hasValue: Bool { current != nil }

    /// Whether `attribute`, which the rule read in its previous run (or already in this one), changed. An attribute the
    /// rule never read gives `false` and does not become a dependency.
    @inline(__always)
    public func hasChanged<T>(_ attribute: Attribute<T>) -> Bool {
        precondition(graph.contains(attribute.id), "hasChanged: the attribute is dead")
        return graph.inputChanged(of: node, attribute: attribute)
    }

    /// Whether any input changed, except the ones listed. True on the first run.
    public func anyInputsChanged(excluding excluded: [AnyAttribute] = []) -> Bool {
        graph.anyInputChanged(of: node, excluding: excluded.map { $0.id.index })
    }

    /// Reads `attribute` (it becomes a dependency) and reports whether it changed since the previous run.
    public func changedValue<T>(of attribute: Attribute<T>, options: AGValueOptions = []) -> (value: T, changed: Bool) {
        let value = graph.value(of: attribute, options: Graph.ReadOptions(rawValue: options.rawValue))
        return (value, graph.inputChanged(of: node, source: attribute.id.index) ?? true)
    }

    /// Runs `body` as part of this context's attribute: inside it the current attribute and the dependencies read are this
    /// attribute's, even when the body runs from another rule (`RuleContext.update(body:)` in native AttributeGraph; measured
    /// in two steps on macOS 15.8).
    public func update(body: () -> Void) {
        let previous = graph.evaluatingNode
        graph.evaluatingNode = node
        defer { graph.evaluatingNode = previous }
        body()
    }

    /// Reads `attribute` as a dependency of this rule and returns its value and flags (`RuleContext.valueAndFlags` in
    /// native AttributeGraph). The `changed` flag is the one ``changedValue(of:options:)`` reports.
    public func valueAndFlags<T>(of attribute: Attribute<T>, options: AGValueOptions = []) -> (value: T, flags: AGChangedValueFlags) {
        let read = changedValue(of: attribute, options: options)
        return (read.value, read.changed ? .changed : [])
    }

    /// Reads `weakAttribute` if its target is still alive (recording a dependency) and reports whether it changed
    /// since the previous run, or returns `nil` if the target was freed.
    public func changedValue<T>(of weakAttribute: WeakAttribute<T>) -> (value: T, changed: Bool)? {
        guard let id = weakAttribute.id, graph.contains(id) else { return nil }
        let attribute = Attribute<T>(id: id)
        let value = graph.read(attribute)
        return (value, graph.inputChanged(of: node, attribute: attribute))
    }

    /// Reads `attribute` as a dependency of this rule (`RuleContext.subscript(Attribute)`).
    public subscript<T>(attribute: Attribute<T>) -> T {
        graph.value(of: attribute)
    }

    /// Reads `weakAttribute` if live as a dependency of this rule (`RuleContext.subscript(WeakAttribute)`).
    public subscript<T>(weakAttribute: WeakAttribute<T>) -> T? {
        graph.value(of: weakAttribute)
    }

    /// Reads `optionalAttribute` if present as a dependency of this rule (`RuleContext.subscript(OptionalAttribute)`).
    public subscript<T>(optionalAttribute: OptionalAttribute<T>) -> T? {
        graph.value(of: optionalAttribute)
    }
}

extension RuleContext: Equatable {
    /// Whether both contexts are for the same node of the same graph.
    public static func == (lhs: RuleContext<Value>, rhs: RuleContext<Value>) -> Bool {
        lhs.graph === rhs.graph && lhs.node == rhs.node
    }
}
