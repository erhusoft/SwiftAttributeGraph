/// A rule that sees its previous value and which of its inputs changed.
///
/// A plain ``Rule`` computes its value from scratch. A stateful rule runs when an input changed (and the first time),
/// receives a ``RuleContext`` with the value it had, and may keep that value by not writing a new one: then the
/// attribute's version does not rise and nothing downstream runs. The struct itself is stored in the node, so what the
/// rule keeps in its own properties survives between runs and is released with the node's subgraph.
///
/// Inside ``updateValue(_:)`` the rule reads other attributes with ``Attribute/value``, as a plain rule does. If
/// several writes happen before the attribute is read, the rule runs once and sees the last values.
public protocol StatefulRule: _AttributeBody {
    /// The type of the attribute the rule computes.
    associatedtype Value
    /// The value before the first run, if the rule has one. Without it, the first run must write a value.
    static var initialValue: Value? { get }
    /// Runs when an input changed. Set ``RuleContext/value`` to change the attribute; leave it alone to keep it.
    mutating func updateValue(_ context: inout RuleContext<Value>)
}

extension StatefulRule {
    /// No initial value by default: the first run must write one.
    public static var initialValue: Value? { nil }
}

extension StatefulRule {
    /// Runs ``updateValue(_:)`` on the rule stored at `pointer`, with a context for `attribute` (`StatefulRule._update(_:attribute:)` in
    /// native AttributeGraph). What the rule writes to the context becomes the value of `attribute`.
    public static func _update(_ pointer: UnsafeMutableRawPointer, attribute: AnyAttribute) {
        var context = RuleContext<Value>(attribute: attribute.unsafeCast(to: Value.self))
        pointer.assumingMemoryBound(to: Self.self).pointee.updateValue(&context)
    }
}
