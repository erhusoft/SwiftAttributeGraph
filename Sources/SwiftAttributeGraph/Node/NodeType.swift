/// What all the nodes of one value type and comparison policy share inside a graph: the comparison and, once a closure
/// rule of the type has been created, the function that runs one. Each graph resolves it once per (type, policy) in
/// `ValueComparator.Cache` and every node keeps a reference to it.
///
/// It plays the part of the per-type attribute descriptor of native AttributeGraph [?]: the node stays small and the
/// typed work lives in functions specialized for `Value`.
@usableFromInline final class NodeType<Value> {
    /// Whether two values count as the same under the policy.
    @usableFromInline let isEqual: (Value, Value) -> Bool

    /// Runs a ``ClosureRuleNode`` of this type (given as its base class) and stores its result; returns whether the
    /// value changed. `nil` until the first closure rule of the type is created.
    ///
    /// The type does not name `Value`: an optional function whose type depends on `Value` made the unspecialized
    /// `ClosureRuleNode.evaluate` ask the runtime for its metadata on every run [O].
    ///
    /// It is set by `Graph.makeRule` (closure form), which is `@inlinable`: the function is compiled in the caller's
    /// specialization, so a run neither asks the runtime for the metadata of `Optional<Value>` nor copies the value
    /// through value witnesses [O]. Every function stored here does the same thing, so which caller sets it does not
    /// matter. The graph is used from one thread, so the lazy write is not a race.
    #if DEBUG && !SAG_UNCHECKED
    @usableFromInline var runClosureRule: ((NodeBox) -> Bool)?
    #else
    @exclusivity(unchecked) @usableFromInline var runClosureRule: ((NodeBox) -> Bool)?
    #endif

    init(isEqual: @escaping (Value, Value) -> Bool) {
        self.isEqual = isEqual
    }
}
