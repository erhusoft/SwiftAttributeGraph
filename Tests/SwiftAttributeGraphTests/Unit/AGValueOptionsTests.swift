import Testing
@testable import SwiftAttributeGraph

/// `AGValueOptions` (no Swift name in the header, so the Swift name is the C name). Raw values from `AGValueOptions.h`.
@Suite struct AGValueOptionsTests {
    @Test func rawValuesMatchTheHeader() {
        #expect(AGValueOptions.inputOptionsUnprefetched.rawValue == 1 << 0)
        #expect(AGValueOptions.inputOptionsSyncMainRef.rawValue == 1 << 1)
        #expect(AGValueOptions.inputOptionsMask.rawValue == 0x03)
        #expect(AGValueOptions.incrementGraphVersion.rawValue == 1 << 2)
    }
}
