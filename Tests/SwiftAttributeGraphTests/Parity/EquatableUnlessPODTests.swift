import Testing
@testable import SwiftAttributeGraph

/// The `equatableUnlessPOD` policy against values measured on macOS 15.8.3 with `AGCompareValues` mode 2 and options
/// `0x302` (warm: layouts already built). These align one policy with measured values; they do not claim parity.
@Suite struct EquatableUnlessPODTests {
    private struct IgnoresB: Equatable { var a: Int; var b: Int; static func == (l: Self, r: Self) -> Bool { l.a == r.a } }
    private struct PlainPOD { var a: Int; var b: Double }
    private final class EqClass: Equatable {
        let v: Int; init(_ v: Int) { self.v = v }
        static func == (l: EqClass, r: EqClass) -> Bool { true }
    }
    private final class PlainClass { let v = 0 }

    /// `true` when the two values compare equal under the policy (the version does not rise).
    private func equal<V>(_ a: V, _ b: V) -> Bool {
        let graph = Graph()
        let attribute = graph.makeInput(a, comparison: .comparison(.equatableUnlessPOD))
        let before = graph.version(of: attribute.id)
        graph.setValue(b, for: attribute)
        return graph.version(of: attribute.id) == before
    }

    @Test func podWithCustomEqualityComparesBytes() {
        #expect(equal(IgnoresB(a: 1, b: 1), IgnoresB(a: 1, b: 2)) == false)   // custom_eq, local_custom_eq
    }
    @Test func doubleNaNIsEqualAndNegativeZeroIsNot() {
        #expect(equal(Double.nan, Double.nan) == true)
        #expect(equal(0.0, -0.0) == false)
    }
    @Test func podSameBytesIsEqual() {
        #expect(equal(PlainPOD(a: 1, b: 2), PlainPOD(a: 1, b: 2)) == true)
    }
    @Test func nonPODEquatableUsesEquals() {
        #expect(equal("\u{00E9}", "e\u{0301}") == true)                       // str_nfc_nfd
        #expect(equal([1, 2, 3], [1, 2, 3]) == true)                          // array_eq
        #expect(equal(EqClass(1), EqClass(2)) == true)                        // eq_class_diff
    }
    @Test func nonEquatableReferencesAndClosuresDiffer() {
        #expect(equal(PlainClass(), PlainClass()) == false)
        let one: () -> Int = { 1 }
        let two: () -> Int = { 2 }
        #expect(equal(one, two) == false)
    }
    @Test func optionalPODComparesBytes() {
        #expect(equal(Optional<Int>.some(1), nil) == false)
    }
}
