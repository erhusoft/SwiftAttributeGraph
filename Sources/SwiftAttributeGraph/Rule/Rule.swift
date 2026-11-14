/// A rule: a type that computes the value of an attribute from other attributes.
///
/// Inside ``value`` the rule reads other attributes with ``Attribute/value`` (or ``Graph/value(of:)``); the engine
/// records what was read and uses it as the rule's dependencies. A rule must not write to the graph.
public protocol Rule {
    /// The type of the attribute the rule computes.
    associatedtype Value
    /// Computes the value. Called lazily, and only when an input changed.
    var value: Value { get }
}
