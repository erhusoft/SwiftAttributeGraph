/// Names an attribute of a ``Graph``: a slot index (low 32 bits) plus a generation (high 32 bits).
///
/// The generation changes every time a slot is reused, so the ID of a dead attribute never resolves to the attribute
/// that later takes its slot. The null ID (`rawValue == 0`) is never handed out because generations start at 1.
///
/// Idea adapted from Salsa (index + generation) and measured in the SwiftGraph storage study (G1).
public struct AttributeID: Hashable, Sendable {
    /// The packed representation: generation in the high half, slot index in the low half.
    public let rawValue: UInt64

    /// Creates an ID from its packed representation.
    public init(rawValue: UInt64) { self.rawValue = rawValue }

    /// The null attribute identifier (`AGAttributeNil`).
    public static let `nil` = AttributeID(rawValue: 0)

    init(index: UInt32, generation: UInt32) {
        rawValue = (UInt64(generation) << 32) | UInt64(index)
    }

    @inlinable var index: UInt32 { UInt32(truncatingIfNeeded: rawValue) }
    var generation: UInt32 { UInt32(truncatingIfNeeded: rawValue >> 32) }

    /// The tag of the graph that created the attribute, `0` if the graph had none (see `GraphRegistry`).
    var graphTag: UInt32 { generation >> 16 }
}
