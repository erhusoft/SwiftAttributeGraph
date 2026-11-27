

/// The base protocol for all rule, map, focus, and stateful bodies attached to attributes
/// in AttributeGraph (`AttributeGraph._AttributeBody`).
public protocol _AttributeBody {
    /// The flags type, as native names it (`_AttributeBody.Flags`).
    typealias Flags = _AttributeType.Flags

    /// The comparison mode used when computing or storing values with this body.
    static var comparisonMode: ComparisonMode { get }

    /// Static type flags governing the allocation and lifecycle of this attribute body.
    static var flags: Flags { get }

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
    /// The default mode is `equatableUnlessPOD`, measured on macOS 15.8.3 for a bare body, a rule, a stateful rule and an observed
    /// attribute (oracle scenarios `f1` to `f6`).
    public static var comparisonMode: ComparisonMode {
        .equatableUnlessPOD
    }

    /// Bodies run on the main thread by default (raw 8), whatever their kind; `External`, `Map` and `Focus` do not (oracle scenarios
    /// `f1` to `f6`). An override is returned as it is and does not touch the comparison mode (`f7`).
    public static var flags: Flags {
        [.mainThread]
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
