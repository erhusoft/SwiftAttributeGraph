/// How the engine decides whether a new value of an attribute counts as a change.
///
/// Parity measurements against SwiftUI show that the comparison is not one function: the value of a view is compared
/// by its bits and ignores `==`, while the environment and `@State` writes use other rules (see
/// `docs/DISENO-M0.md` §5). M0 provides the two policies that need no type information; M2 adds the rest.
public enum Comparison: Sendable {
    /// Equal when every byte of the value is equal (references by identity). The default.
    case bits
    /// Every new value counts as a change.
    case alwaysDifferent

    /// Whether `old` and `new` are the same under this policy.
    @inline(__always)
    func isEqual<Value>(_ old: Value, _ new: Value) -> Bool {
        switch self {
        case .alwaysDifferent: return false
        case .bits: return bitwiseEqual(old, new)
        }
    }
}

/// Compares the bytes of two values of the same type, eight at a time.
///
/// Padding bytes are not guaranteed to be equal for equal values, so a type with padding can report "changed" when
/// nothing changed. That error is on the safe side: a rule runs once more, never once less.
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
