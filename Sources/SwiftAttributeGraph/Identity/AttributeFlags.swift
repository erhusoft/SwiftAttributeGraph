/// An 8-bit set of caller-defined flags attached to an attribute (`AGAttributeFlags` in native AttributeGraph).
///
/// Subgraph operations such as ``Graph/intersects(_:flags:)``, ``Graph/isDirty(_:flags:)``,
/// ``Graph/forEach(in:flags:_:)``, and ``Graph/update(_:flags:)`` filter attributes by bitwise intersection with their
/// flags.
public struct AttributeFlags: OptionSet, Hashable, Sendable {
    /// The underlying 8-bit bitmask.
    public var rawValue: UInt8

    /// Creates a flag set from its raw 8-bit bitmask.
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// Matches every non-empty flag bit (`0xFF`).
    public static let all = AttributeFlags(rawValue: 0xFF)
}
