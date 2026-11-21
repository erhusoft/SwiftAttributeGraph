/// The flags of a value read (`AGChangedValueFlags` in native AttributeGraph; the header gives it no Swift name).
public struct AGChangedValueFlags: OptionSet, Hashable, Sendable {
    /// The raw value.
    public let rawValue: UInt32

    /// Creates flags from their raw value.
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    /// The value changed since the running rule last read it (`AGChangedValueFlagsChanged`, bit 0).
    public static let changed = AGChangedValueFlags(rawValue: 1 << 0)
    /// The value must be read on the main thread (`AGChangedValueFlagsRequiresMainThread`, bit 1).
    public static let requiresMainThread = AGChangedValueFlags(rawValue: 1 << 1)
}
