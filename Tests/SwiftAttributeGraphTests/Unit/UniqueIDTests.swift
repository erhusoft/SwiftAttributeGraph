import Testing
@testable import SwiftAttributeGraph

/// `AGMakeUniqueID` (`makeUniqueID()`). Measured with the `unique-id` oracle scenario on macOS 15.8: the IDs are non-zero,
/// distinct, and each call returns the previous value plus one. Creating a graph also consumes IDs on Apple, so the
/// sequence is process-wide and only the relative order is part of the contract.
@Suite struct UniqueIDTests {
    @Test func idsAreNonZeroAndConsecutive() {
        let a = makeUniqueID()
        let b = makeUniqueID()
        let c = makeUniqueID()
        #expect(a != 0)
        #expect(b == a &+ 1)
        #expect(c == b &+ 1)
    }

    @Test func idsStayUniqueAcrossGraphs() {
        let first = makeUniqueID()
        _ = Graph()
        let second = makeUniqueID()
        #expect(second > first)
    }
}
