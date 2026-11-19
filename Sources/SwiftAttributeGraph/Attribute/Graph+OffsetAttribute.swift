extension Graph {
    private static let maxOffsetAttributeOffset = 0x3fff_ffff

    /// Projects a raw byte slice `[offset, offset + size)` from a `BitwiseCopyable` source attribute as `[UInt8]`.
    ///
    /// - Note: Unlike native `AGGraphCreateOffsetAttribute` + `loadUnaligned`, this never constructs an arbitrary
    ///   typed `Projected` value from raw bytes (which would be undefined behavior for `Bool`, `enum`s, or `Optional`
    ///   with invalid bit patterns). All `UInt8` bit patterns are valid. For typed projections, use ``makeFocus(_:keyPath:)``
    ///   or ``makeMap(_:_:)``. Note also that `withUnsafeBytes` includes any struct padding bytes at `[offset, offset + size)`.
    public func makeByteRangeAttribute<Source: BitwiseCopyable>(
        of source: Attribute<Source>,
        offset: Int,
        size: Int
    ) -> Attribute<[UInt8]> {
        assertOwnThread()
        let sourceSize = MemoryLayout<Source>.size
        precondition(offset >= 0 && offset < Graph.maxOffsetAttributeOffset, "invalid offset: \(offset)")
        precondition(size >= 0, "invalid negative size: \(size)")
        let (end, overflow) = offset.addingReportingOverflow(size)
        precondition(!overflow && end <= sourceSize, "offset range [\(offset), +\(size)) exceeds \(sourceSize)")

        if size == 0 {
            return makeRule {
                _ = source.value
                return []
            }
        }

        return makeRule {
            let value = source.value
            return withUnsafeBytes(of: value) { raw in
                guard let base = raw.baseAddress else { return [] }
                return Array(UnsafeBufferPointer(start: base.assumingMemoryBound(to: UInt8.self).advanced(by: offset),
                                                 count: size))
            }
        }
    }
}
