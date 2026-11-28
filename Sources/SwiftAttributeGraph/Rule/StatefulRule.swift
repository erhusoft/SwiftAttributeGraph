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
    /// Runs when an input changed. Set ``value`` (or ``context``'s value) to change the attribute; leave it alone to keep it.
    mutating func updateValue()
}

extension StatefulRule {
    /// No initial value by default: the first run must write one.
    public static var initialValue: Value? { nil }
}

extension StatefulRule {
    /// Runs ``updateValue(_:)`` on the rule stored at `pointer`, with a context for `attribute` (`StatefulRule._update(_:attribute:)` in
    /// native AttributeGraph). What the rule writes to the context becomes the value of `attribute`.
    public static func _update(_ pointer: UnsafeMutableRawPointer, attribute: AnyAttribute) {
        let context = RuleContext<Value>(attribute: attribute.unsafeCast(to: Value.self))
        guard let graph = ThreadLocalGraph.current() else {
            pointer.assumingMemoryBound(to: Self.self).pointee.updateValue()
            return
        }
        graph.withActiveContext(context) { pointer.assumingMemoryBound(to: Self.self).pointee.updateValue() }
    }
}

extension StatefulRule {
    /// The attribute this rule computes (`StatefulRule.attribute` in native AttributeGraph). Only inside ``updateValue()``.
    public var attribute: Attribute<Value> { context.attribute }

    /// The context of the running update (`StatefulRule.context` in native AttributeGraph). Only inside ``updateValue()``.
    public var context: RuleContext<Value> {
        guard let graph = ThreadLocalGraph.current(), let active = graph.activeRuleContext as? RuleContext<Value> else {
            preconditionFailure("StatefulRule.context used outside updateValue()")
        }
        return active
    }

    /// The value of the attribute; the previous one when the rule starts. Setting it makes the attribute take the new
    /// value (`StatefulRule.value` in native AttributeGraph).
    public var value: Value {
        get { context.value }
        nonmutating set { context.value = newValue }
    }

    /// Whether the attribute has a value to read: false only on a first run without an ``initialValue``.
    public var hasValue: Bool { context.hasValue }
}
