/// A rule that transforms an input attribute `arg` with a closure `body` (matching native `AttributeGraph.Map`).
///
/// Because `Map` is a ``Rule``, its output value goes through the attribute's comparison policy: when `arg` changes
/// to a new value whose mapped result `body(arg.value)` is equal to the previous output, downstream dependents of the
/// `Map` attribute are cut.
public struct Map<Source, Value>: Rule, CustomStringConvertible {
    /// The source attribute read by the rule.
    public var arg: Attribute<Source>
    /// The transformation applied to `arg.value`.
    public let body: (Source) -> Value

    /// Creates a transformation rule over `arg` using `body`.
    public init(_ arg: Attribute<Source>, _ body: @escaping (Source) -> Value) {
        self.arg = arg
        self.body = body
    }

    /// Reads `arg` in the current graph and transforms its value with `body`.
    public var value: Value {
        body(arg.value)
    }

    /// A human-readable description of the map rule.
    public var description: String {
        "Map(\(arg.id))"
    }
}

extension Graph {
    /// Creates a rule attribute that transforms `arg` with `body`, in the current subgraph.
    ///
    /// Changes to `arg` whose transformed result remains equal under `comparison` do not raise the mapped attribute's
    /// version, cutting downstream dependents.
    public func makeMap<Source, Value>(_ arg: Attribute<Source>, comparison: ValuePolicy = .viewValue,
                                       _ body: @escaping (Source) -> Value) -> Attribute<Value> {
        assertOwnThread()
        precondition(table.isLive(arg.id), "makeMap: the source attribute is dead")
        return makeRule(Map(arg, body), comparison: comparison)
    }
}
