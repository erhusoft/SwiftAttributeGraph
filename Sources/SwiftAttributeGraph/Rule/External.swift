
/// An attribute body representing an externally provided value
/// (`AttributeGraph.External`).
public struct External<Value>: _AttributeBody, CustomStringConvertible {
    /// Creates the body of an external input.
    public init() {}

    /// An external input is not a main-thread body (native raw 0, oracle scenario `f4`).
    public static var flags: Flags { [] }
    /// An external input compares with `equatableAlways` (native raw 3, oracle scenario `f4`).
    public static var comparisonMode: ComparisonMode { .equatableAlways }

    /// Does nothing: an external input changes by being written, not by running.
    public static func _update(_ pointer: UnsafeMutableRawPointer, attribute: AnyAttribute) {
        // External attributes are updated via direct mutation rather than rule execution
    }

    /// `External<Value>`, with the name of the value type.
    public var description: String {
        "External<\(Value.self)>"
    }
}

/// Type-erased representation of an external attribute body
/// (`AttributeGraph._External`).
public struct _External: _AttributeBody, CustomStringConvertible {
    /// Creates the body of a type-erased external input.
    public init() {}

    /// `_External`.
    public var description: String {
        "_External"
    }
}
