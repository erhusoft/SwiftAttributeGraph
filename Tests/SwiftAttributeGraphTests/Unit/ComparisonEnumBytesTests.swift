import Testing
@testable import SwiftAttributeGraph

/// A non-`Equatable` enum with a payload is compared by its bytes, as native AttributeGraph does (measured with the
/// `compare-plan` probe in all four modes: two equal `String`s stored separately compare different). The value of the
/// payload is not inspected, so no reflection (`Mirror`) is involved.
@Suite struct ComparisonEnumBytesTests {
    enum Payload { case text(String), number(Int) }

    @Test func equalStringsStoredSeparatelyCompareDifferentLikeNative() {
        let compare = ValueComparator.make(.viewValue, for: Payload.self)
        let long = String(repeating: "x", count: 40)
        #expect(compare(.text(long), .text(String(repeating: "x", count: 40))) == false)
    }

    @Test func theSameValueComparesEqual() {
        let compare = ValueComparator.make(.viewValue, for: Payload.self)
        let value = Payload.number(7)
        #expect(compare(value, value))
    }

    @Test func differentCasesCompareDifferent() {
        let compare = ValueComparator.make(.viewValue, for: Payload.self)
        #expect(compare(.number(1), .text("1")) == false)
    }
}
