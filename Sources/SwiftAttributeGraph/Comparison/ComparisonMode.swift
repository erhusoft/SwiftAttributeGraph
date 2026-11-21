/// The comparison modes of native AttributeGraph (`AGComparisonMode`, the `mode:` of `compareValues`). The engine uses
/// them through ``ValuePolicy/comparison(_:)``.
public enum ComparisonMode: UInt8, Hashable, Sendable {
    /// Compares the bytes of the value (`AGComparisonModeBitwise`, raw 0). Measured with `compare-mode`.
    case bitwise = 0
    /// Like `bitwise` in every measured case (`AGComparisonModeIndirect`, raw 1). Its own path is not modeled.
    case indirect = 1
/// Corresponds to `AGComparisonMode` 2 (EquatableUnlessPOD) in its warm state, i.e. with the type layouts already
/// built (measured on macOS 15.8.3 with options `0x302`). A trivial (POD) type is compared by its bytes, so an
/// `==` of its own is ignored, `Double.nan` equals itself and `0.0` differs from `-0.0`. A non-trivial `Equatable`
/// type uses its `==`. A non-trivial type that is not `Equatable` (a class without `==`, a closure) is compared by
/// its bytes, that is, by identity.
///
/// The cold behaviour of the native function (the first call, with asynchronous layouts, compares by bytes) is
/// deliberately not reproduced.
case equatableUnlessPOD
/// Corresponds to `AGComparisonMode` 3 (EquatableAlways, options `0x103`), measured on macOS 15.7.9 with the
/// `compare-values-103-102` scenario. An `Equatable` type is compared with its `==`, POD included (so `Double.nan`
/// differs from itself and `0.0` equals `-0.0`). A type that is not `Equatable` is compared by its bytes, that is,
/// by identity for references. It differs from ``equatableUnlessPOD`` only for POD types.
case equatableAlways
}
