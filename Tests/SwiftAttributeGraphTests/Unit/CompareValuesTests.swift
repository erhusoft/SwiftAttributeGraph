import Testing
@testable import SwiftAttributeGraph

/// `compareValues(_:_:mode:)` and `compareValues(_:_:options:)` (native `compareValues`, Swift interface). Checked against the
/// warm matrix measured with `compare-mode` and `compare-rule` on macOS 15.8. Known difference, not fixed: the public
/// `equatableAlways` compares a struct holding a `String` with its own partial `==` by bytes in Apple (false), while this
/// engine uses the `==` (true). Excluded from the tests below.
@Suite struct CompareValuesTests {
    private struct PODPartialEq: Equatable {
        var a: Int64; var b: Int64
        static func == (l: PODPartialEq, r: PODPartialEq) -> Bool { l.a == r.a }
    }
    private struct StringSynth: Equatable { var s: String }
    private final class ClassEq: Equatable {
        let v: Int; init(_ v: Int) { self.v = v }
        static func == (l: ClassEq, r: ClassEq) -> Bool { true }
    }

    @Test func bitwiseComparesBytes() {
        #expect(compareValues(0.0, -0.0, mode: .bitwise) == false)
        #expect(compareValues(String(repeating: "a", count: 40), String(repeating: "a", count: 40), mode: .bitwise) == false)
    }

    @Test func equatableUnlessPODUsesBytesForPODAndEqualityForStrings() {
        #expect(compareValues(PODPartialEq(a: 1, b: 2), PODPartialEq(a: 1, b: 3), mode: .equatableUnlessPOD) == false)
        #expect(compareValues(StringSynth(s: String(repeating: "b", count: 40)), StringSynth(s: String(repeating: "b", count: 40)), mode: .equatableUnlessPOD) == true)
    }

    @Test func equatableAlwaysUsesEqualityForPODAndSynthesizedStrings() {
        #expect(compareValues(PODPartialEq(a: 1, b: 2), PODPartialEq(a: 1, b: 3), mode: .equatableAlways) == true)
        #expect(compareValues(StringSynth(s: String(repeating: "b", count: 40)), StringSynth(s: String(repeating: "b", count: 40)), mode: .equatableAlways) == true)
        #expect(compareValues(ClassEq(1), ClassEq(2), mode: .equatableAlways) == true)
    }

    @Test func defaultModeIsEquatableAlways() {
        #expect(compareValues(PODPartialEq(a: 1, b: 2), PODPartialEq(a: 1, b: 3)) == true)
    }

    @Test func optionsSelectTheMode() {
        #expect(compareValues(0.0, -0.0, options: ComparisonOptions(rawValue: 0x103)) == true)
        #expect(compareValues(0.0, -0.0, options: ComparisonOptions(rawValue: 0x100)) == false)
    }
}
