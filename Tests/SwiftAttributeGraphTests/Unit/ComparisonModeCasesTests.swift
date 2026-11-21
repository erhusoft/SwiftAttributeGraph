import Testing
@testable import SwiftAttributeGraph

/// `AGComparisonMode` (`ComparisonMode`): the four native cases with their raw values. Measured with `compare-mode`: mode 0
/// (`bitwise`) compares by bytes, and mode 1 (`indirect`) gave the same results as mode 0 in every probe.
@Suite struct ComparisonModeCasesTests {
    @Test func rawValuesMatchTheHeader() {
        #expect(ComparisonMode.bitwise.rawValue == 0)
        #expect(ComparisonMode.indirect.rawValue == 1)
        #expect(ComparisonMode.equatableUnlessPOD.rawValue == 2)
        #expect(ComparisonMode.equatableAlways.rawValue == 3)
    }

    @Test func bitwiseComparesAStringByItsBytes() {
        let graph = Graph()
        let input = graph.makeInput(String(repeating: "a", count: 40), comparison: .comparison(.bitwise))
        #expect(input.setValue(String(repeating: "a", count: 40)) == true)
    }

    @Test func optionsReadTheBitwiseAndIndirectModes() {
        #expect(ComparisonOptions(rawValue: 0x100).mode == .bitwise)
        #expect(ComparisonOptions(rawValue: 0x101).mode == .indirect)
    }
}
