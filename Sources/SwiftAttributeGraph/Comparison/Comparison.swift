/// How the engine decides whether a new value of an attribute counts as a change.
///
/// SwiftUI does not compare with one function. The measured rules (macOS 15.7.9, steady state; see
/// `docs/DISENO-M2.md` §2) are resolved once, when the attribute is created, from the type of its value:
public enum Comparison: Sendable {
    /// The properties of a view, and the default. A trivial value is compared by its bytes (an `==` of its own is
    /// ignored); otherwise each field by its own rule: `Equatable` fields with `==`, references by identity.
    case viewValue
    /// An environment value: equal if the bytes are equal or if the `@State` rule says equal.
    case environment
    /// A `@State` write: `Equatable` values (and the `Equatable` fields of the rest, trivial ones included) with `==`;
    /// references by identity.
    case stateWrite
    /// Every new value counts as a change.
    case alwaysDifferent
    /// Only the bytes of the value (references by identity), without looking at the type: the policy of M0. A safe
    /// floor: it can run a rule that SwiftUI would skip, never skip one that SwiftUI would run.
    case bits
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

/// Compares the bytes of two values of the same type, eight at a time.
///
/// Padding bytes (and the unused words of an existential) are not guaranteed to be equal for equal values, so this
/// can report "changed" when nothing changed. That is on the safe side: a rule runs once more, never once less. The
/// policies other than `.bits` use a ``ComparisonPlan``, which never reads padding.
@inline(__always)
func bitwiseEqual<Value>(_ a: Value, _ b: Value) -> Bool {
    withUnsafeBytes(of: a) { left in
        withUnsafeBytes(of: b) { right in
            let count = left.count
            var offset = 0
            while offset + 8 <= count {
                if left.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
                    != right.loadUnaligned(fromByteOffset: offset, as: UInt64.self) { return false }
                offset += 8
            }
            while offset < count {
                if left[offset] != right[offset] { return false }
                offset += 1
            }
            return true
        }
    }
}

/// Whether two ranges of memory hold the same bytes.
@inline(__always)
func bytesEqual(_ left: UnsafeRawPointer, _ right: UnsafeRawPointer, _ count: Int) -> Bool {
    var offset = 0
    while offset + 8 <= count {
        if left.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
            != right.loadUnaligned(fromByteOffset: offset, as: UInt64.self) { return false }
        offset += 8
    }
    while offset < count {
        if left.load(fromByteOffset: offset, as: UInt8.self) != right.load(fromByteOffset: offset, as: UInt8.self) { return false }
        offset += 1
    }
    return true
}
