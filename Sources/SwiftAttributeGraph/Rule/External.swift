
/// An attribute body representing an externally provided value
/// (`AttributeGraph.External`).
public struct External<Value>: _AttributeBody, CustomStringConvertible {
    public init() {}

    public static func _update(_ pointer: UnsafeMutableRawPointer, attribute: AnyAttribute) {
        // External attributes are updated via direct mutation rather than rule execution
    }

    public var description: String {
        "External<\(Value.self)>"
    }
}

/// Type-erased representation of an external attribute body
/// (`AttributeGraph._External`).
public struct _External: _AttributeBody, CustomStringConvertible {
    public init() {}

    public var description: String {
        "_External"
    }
}
