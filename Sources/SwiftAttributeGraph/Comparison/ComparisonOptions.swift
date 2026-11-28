/// The options of a comparison (`AGComparisonOptions` in native AttributeGraph). The low byte holds a ``ComparisonMode``;
/// the other bits are flags. Bit 9 (`fetchLayoutsSynchronously`) matters for mode 3: without it a `String` is compared by
/// bytes until its layout is ready (measured on macOS 15.8).
public struct ComparisonOptions: OptionSet, Hashable, Sendable {
    /// The raw value, with the mode in the low byte.
    public let rawValue: UInt32

    /// Creates options from their raw value.
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    /// Options for `mode`: the raw value of the mode, nothing else (`ComparisonOptions.init(mode:)` in native AttributeGraph; measured on macOS 15.8.3:
    /// raw 0, 1, 2 and 3 for the four modes).
    public init(mode: ComparisonMode) { self.rawValue = UInt32(mode.rawValue) }

    /// Copy on write (`AGComparisonOptionsCopyOnWrite`, bit 8).
    public static let copyOnWrite = ComparisonOptions(rawValue: 1 << 8)
    /// Fetch the layouts synchronously, so mode 3 uses `==` at once (`AGComparisonOptionsFetchLayoutsSynchronously`, bit 9).
    public static let fetchLayoutsSynchronously = ComparisonOptions(rawValue: 1 << 9)
    /// Trace a failed comparison (`AGComparisonOptionsTraceCompareFailed`, bit 31).
    public static let traceCompareFailed = ComparisonOptions(rawValue: 1 << 31)

    /// The comparison mode in the low byte, or `nil` when it is a mode this engine does not model (bitwise or indirect).
    public var mode: ComparisonMode? {
        switch rawValue & 0xff {
        case 0: return .bitwise
        case 1: return .indirect
        case 2: return .equatableUnlessPOD
        case 3: return .equatableAlways
        default: return nil
        }
    }
}
