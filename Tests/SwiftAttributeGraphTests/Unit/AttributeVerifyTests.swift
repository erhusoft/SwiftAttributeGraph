import Testing
@testable import SwiftAttributeGraph

/// `AGGraphVerifyType` (`Attribute.verify(type:)`). Measured on macOS 15.8 with `verify-correct-type` and `verify-wrong-type`:
/// the matching type passes; a different type aborts the process without a message. A trap cannot be tested in-process,
/// so only the matching case is a test here.
@Suite struct AttributeVerifyTests {
    @Test func theMatchingTypePasses() {
        let graph = Graph()
        let input = graph.makeInput(7)
        input.verify(type: Int.self)
        #expect(graph.value(of: input) == 7)
    }
}
