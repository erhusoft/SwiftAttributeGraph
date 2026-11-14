import Testing
@testable import SwiftAttributeGraph

@Test func versionIsBelowOneUntilThePlanIsDone() {
    #expect(SwiftAttributeGraph.version.hasPrefix("0."))
}
