/// A rule: a type that computes the value of an attribute from other attributes.
///
/// Inside ``value`` the rule reads other attributes with ``Attribute/value`` (or ``Graph/value(of:)``); the engine
/// records what was read and uses it as the rule's dependencies. A rule must not write to the graph.
public protocol Rule: _AttributeBody {
    /// The type of the attribute the rule computes.
    associatedtype Value
    /// Computes the value. Called lazily, and only when an input changed.
    var value: Value { get }
}

extension Rule {
    /// Runs the rule stored at `pointer` and writes its value to `attribute` (`Rule._update(_:attribute:)` in native AttributeGraph): the
    /// function `Rule.cachedValue` hands to `_cachedValue` as the body of the attribute it creates.
    public static func _update(_ pointer: UnsafeMutableRawPointer, attribute: AnyAttribute) {
        let rule = pointer.assumingMemoryBound(to: Self.self).pointee
        RuleContext<Value>(attribute: attribute.unsafeCast(to: Value.self)).value = rule.value
    }
}
