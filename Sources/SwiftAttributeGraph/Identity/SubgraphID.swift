/// Names a subgraph of a ``Graph``: a slot index (low 32 bits) plus a generation (high 32 bits).
public struct SubgraphID: Hashable, Sendable {
    /// The packed representation: generation in the high half, slot index in the low half.
    public let rawValue: UInt64

    init(index: UInt32, generation: UInt32) {
        rawValue = (UInt64(generation) << 32) | UInt64(index)
    }

    var index: UInt32 { UInt32(truncatingIfNeeded: rawValue) }
    var generation: UInt32 { UInt32(truncatingIfNeeded: rawValue >> 32) }
}
