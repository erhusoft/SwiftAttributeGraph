

/// The base protocol for all rule, map, focus, and stateful bodies attached to attributes
/// in AttributeGraph (`AttributeGraph._AttributeBody`).
public protocol _AttributeBody {
    /// The comparison mode used when computing or storing values with this body.
    static var comparisonMode: ComparisonMode { get }

    /// Static type flags governing the allocation and lifecycle of this attribute body.
    static var flags: AttributeTypeFlags { get }

    /// Whether this body implements custom in-place memory destruction.
    static var _hasDestroySelf: Bool { get }

    /// Destroys the body instance stored in raw memory.
    static func _destroySelf(_ pointer: UnsafeMutableRawPointer)

    /// Performs the default update pass on the body instance stored in raw memory.
    static func _updateDefault(_ pointer: UnsafeMutableRawPointer)

    /// Whether the ongoing update of this body was cooperatively cancelled.
    var updateWasCancelled: Bool { get }
}

extension _AttributeBody {
    public static var comparisonMode: ComparisonMode {
        .equatableAlways
    }

    public static var flags: AttributeTypeFlags {
        []
    }

    public static var _hasDestroySelf: Bool {
        false
    }

    public static func _destroySelf(_ pointer: UnsafeMutableRawPointer) {
        pointer.assumingMemoryBound(to: Self.self).deinitialize(count: 1)
    }

    public static func _updateDefault(_ pointer: UnsafeMutableRawPointer) {
        // Default no-op update pass
    }

    public var updateWasCancelled: Bool {
        false
    }
}

/// Visitor protocol for inspecting the stored body of an attribute
/// (`AttributeGraph.AttributeBodyVisitor`).
public protocol AttributeBodyVisitor {
    /// Visits the typed attribute body stored in memory.
    mutating func visit<Body: _AttributeBody>(body: UnsafePointer<Body>)
}
