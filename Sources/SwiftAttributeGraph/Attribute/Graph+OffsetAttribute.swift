extension Graph {
    private static let maxOffsetAttributeOffset = 0x3fff_ffff

    /// Projects a byte-range `[offset, offset + MemoryLayout<Projected>.size)` from a `BitwiseCopyable` source
    /// attribute (safe Swift equivalent of `AGGraphCreateOffsetAttribute` + `compare_edge_values`).
    ///
    /// - Note: Both `Source` and `Projected` must conform to `BitwiseCopyable` so inline byte slicing never inspects
    ///   reference-counted headers or non-trivial storage. For non-trivial types, use typed `Focus` / `Map` instead.
    public func makeOffsetAttribute<Source: BitwiseCopyable, Projected: BitwiseCopyable>(
        of source: Attribute<Source>,
        offset: Int,
        as projectedType: Projected.Type = Projected.self
    ) -> Attribute<Projected> {
        assertOwnThread()
        let sourceSize = MemoryLayout<Source>.size
        let projectedSize = MemoryLayout<Projected>.size
        precondition(offset >= 0 && offset < Graph.maxOffsetAttributeOffset, "invalid offset: \(offset)")
        let (end, overflow) = offset.addingReportingOverflow(projectedSize)
        precondition(!overflow && end <= sourceSize, "offset range [\(offset), +\(projectedSize)) exceeds \(sourceSize)")

        if offset == 0 && projectedSize == sourceSize && Source.self == Projected.self {
            return Attribute<Projected>(id: source.id)
        }

        return makeRule {
            let value = source.value
            return withUnsafeBytes(of: value) { raw in
                raw.baseAddress!.advanced(by: offset).loadUnaligned(as: Projected.self)
            }
        }
    }

    /// Projects a zero-sized range from `source`, which never reports a change (matching `compare_edge_values` when
    /// `size == 0`).
    public func makeZeroSizeOffsetAttribute<Source: BitwiseCopyable>(
        of source: Attribute<Source>,
        offset: Int = 0
    ) -> Attribute<Int> {
        assertOwnThread()
        let sourceSize = MemoryLayout<Source>.size
        precondition(offset >= 0 && offset < Graph.maxOffsetAttributeOffset && offset <= sourceSize,
                     "invalid zero-size offset: \(offset)")
        return makeRule {
            _ = source.value
            return 0
        }
    }
}
