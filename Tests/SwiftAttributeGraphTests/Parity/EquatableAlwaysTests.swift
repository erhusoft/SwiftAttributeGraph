import Testing
@testable import SwiftAttributeGraph

/// The `equatableAlways` policy (`AGCompareValues` mode 3, options `0x103`) against the values measured on macOS 15.7.9
/// with the `compare-values-103-102` scenario (debug, one pass, warm). Mode 3 uses `==` whenever the type is
/// `Equatable`, POD included; this is the difference from `equatableUnlessPOD` (mode 2).
@Suite struct EquatableAlwaysTests {
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
        let attribute = graph.makeInput(a, comparison: .equatableAlways)
        let before = graph.version(of: attribute.id)
        graph.setValue(b, for: attribute)
        return graph.version(of: attribute.id) == before
    }

    @Test func podWithCustomEqualityUsesEquals() {
        #expect(equal(IgnoresB(a: 1, b: 1), IgnoresB(a: 1, b: 2)) == true)
    }
    @Test func podWithoutEqualityComparesBytes() {
        #expect(equal(PlainPOD(a: 1, b: 2), PlainPOD(a: 1, b: 2)) == true)
        #expect(equal(PlainPOD(a: 1, b: 2), PlainPOD(a: 1, b: 3)) == false)
    }
    @Test func doubleUsesEqualsSoNaNDiffersAndNegativeZeroIsEqual() {
        #expect(equal(Double.nan, Double.nan) == false)
        #expect(equal(0.0, -0.0) == true)
    }
    @Test func nonPODEquatableUsesEquals() {
        #expect(equal("\u{00E9}", "e\u{0301}") == true)
        #expect(equal(EqClass(1), EqClass(2)) == true)
    }
    @Test func nonEquatableReferenceDiffers() {
        #expect(equal(PlainClass(), PlainClass()) == false)
    }
}
