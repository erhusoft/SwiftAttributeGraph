/// Measured on macOS 15.8 (read-options-runs, inside a rule, source changed): raw 0 and raw 2 re-run the rule (a dependency
/// edge is recorded); raw 4 and raw 6 do not (no edge). So the header name of bit 2 (`inputOptionsSyncMainRef`) does not
/// describe its effect, and bit 4 (`incrementGraphVersion`) suppresses the edge. The names are the header's; the behaviour
/// is the measured one.
///
/// The options of a value read (`AGValueOptions` in native AttributeGraph; the header gives it no Swift name, so the C
/// name is the Swift name).
public struct AGValueOptions: OptionSet, Hashable, Sendable {
    /// The raw value, with the input options in the low two bits.
    public let rawValue: UInt32

    /// Creates options from their raw value.
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    /// Read the input without prefetching it (`AGValueOptionsInputOptionsUnprefetched`, bit 0).
    public static let inputOptionsUnprefetched = AGValueOptions(rawValue: 1 << 0)
    /// Read the input synchronously on the main thread (`AGValueOptionsInputOptionsSyncMainRef`, bit 1).
    public static let inputOptionsSyncMainRef = AGValueOptions(rawValue: 1 << 1)
    /// Mask of the two input options (`AGValueOptionsInputOptionsMask`).
    public static let inputOptionsMask = AGValueOptions(rawValue: 0x03)
    /// Increment the graph version when read as a top-level output (`AGValueOptionsIncrementGraphVersion`, bit 2).
    public static let incrementGraphVersion = AGValueOptions(rawValue: 1 << 2)
}
