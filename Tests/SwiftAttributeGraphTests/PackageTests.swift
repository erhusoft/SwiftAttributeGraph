import XCTest
@testable import SwiftAttributeGraph

final class PackageTests: XCTestCase {
    func testVersionIsBelowOneUntilThePlanIsDone() {
        XCTAssertTrue(SwiftAttributeGraph.version.hasPrefix("0."))
    }
}
