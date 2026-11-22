/// A protocol for attribute bodies that observe lifecycle events and clean up resources (`AttributeGraph.ObservedAttribute`).
///
/// Types conforming to `ObservedAttribute` inherit from `_AttributeBody` and provide a `destroy()` method
/// that is invoked when the attribute is removed or deallocated.
public protocol ObservedAttribute: _AttributeBody {
    /// Cleans up resources or observers attached to this attribute body.
    mutating func destroy()
}

extension ObservedAttribute {
    /// Indicates to the graph runtime whether this attribute body defines a custom destructor.
    public static var _hasDestroySelf: Bool { true }

    /// Default implementation that invokes `destroy()` on the pointee.
    public static func _destroySelf(_ pointer: UnsafeMutableRawPointer) {
        pointer.assumingMemoryBound(to: Self.self).pointee.destroy()
    }
}
