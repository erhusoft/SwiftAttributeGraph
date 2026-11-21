import Testing
@testable import SwiftAttributeGraph

/// `AGComparisonOptions` (`ComparisonOptions`). Raw values from the native header, and the mode in the low byte. Measured
/// on macOS 15.8 with the `compare-options` scenario: `fetchLayoutsSynchronously` (bit 9) changes the result of mode 3 for
/// a `String` (`0x303` compares by `==`, `0x103` by bytes until the layout is ready), and does not change mode 2.
@Suite struct ComparisonOptionsTests {
    @Test func flagsHaveTheNativeBits() {
        #expect(ComparisonOptions.copyOnWrite.rawValue == 1 << 8)
        #expect(ComparisonOptions.fetchLayoutsSynchronously.rawValue == 1 << 9)
        #expect(ComparisonOptions.traceCompareFailed.rawValue == 1 << 31)
    }

    @Test func modeIsTheLowByte() {
        #expect(ComparisonOptions(rawValue: 0x102).mode == .equatableUnlessPOD)
        #expect(ComparisonOptions(rawValue: 0x103).mode == .equatableAlways)
        #expect(ComparisonOptions(rawValue: 0x303).mode == .equatableAlways)
        #expect(ComparisonOptions(rawValue: 0x100).mode == .bitwise)
    }
}
