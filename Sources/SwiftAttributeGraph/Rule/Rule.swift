/// A rule: a type that computes the value of an attribute from other attributes.
///
/// Inside ``value`` the rule reads other attributes with ``Attribute/value`` (or ``Graph/value(of:)``); the engine
/// records what was read and uses it as the rule's dependencies. A rule must not write to the graph.
public protocol Rule: _AttributeBody {
    /// The type of the attribute the rule computes.
    associatedtype Value
    /// The value before the first run, if the rule has one (`Rule.initialValue` in native AttributeGraph).
    static var initialValue: Value? { get }
    /// Computes the value. Called lazily, and only when an input changed.
    var value: Value { get }
}

extension Rule {
    /// No initial value by default.
    public static var initialValue: Value? { nil }

    /// The attribute this rule computes: the one being updated (`Rule.attribute` in native AttributeGraph). Only inside ``value``.
    public var attribute: Attribute<Value> {
        guard let current = Graph.currentAttribute else { preconditionFailure("Rule.attribute used outside a rule") }
        return current.unsafeCast(to: Value.self)
    }

    /// A context for the attribute being updated (`Rule.context` in native AttributeGraph). Only inside ``value``.
    public var context: RuleContext<Value> { RuleContext(attribute: attribute) }
}

extension Rule {
    /// Runs the rule stored at `pointer` and writes its value to `attribute` (`Rule._update(_:attribute:)` in native AttributeGraph): the
    /// function `Rule.cachedValue` hands to `_cachedValue` as the body of the attribute it creates.
    public static func _update(_ pointer: UnsafeMutableRawPointer, attribute: AnyAttribute) {
        let rule = pointer.assumingMemoryBound(to: Self.self).pointee
        RuleContext<Value>(attribute: attribute.unsafeCast(to: Value.self)).value = rule.value
    }
}
