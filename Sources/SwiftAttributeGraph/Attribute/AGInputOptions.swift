/// The options of an input edge (`AGInputOptions` in native AttributeGraph).
///
/// The engine accepts them and does not act on them: the effect of each bit on an edge was not measured.
public struct AGInputOptions: OptionSet, Hashable, Sendable {
    /// The raw value.
    public let rawValue: UInt32

    /// Creates options from their raw value.
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    /// The input is not prefetched (`AGInputOptionsUnprefetched`, bit 0).
    public static let unprefetched = AGInputOptions(rawValue: 1 << 0)
    /// The input is read synchronously on the main thread (`AGInputOptionsSyncMainRef`, bit 1).
    public static let syncMainRef = AGInputOptions(rawValue: 1 << 1)
}
