import Testing
@testable import SwiftAttributeGraph

/// Apple's `AGGraphSetIndirectDependency(attribute1, attribute2)`, the setter of `AGAttribute._indirectDependency`. The
/// engine's ``Graph/setDependency(_:for:)`` already implements it; this checks the Apple-named method. Only the setter
/// is imported by SwiftUICore; the getter is not imported by any framework measured so far.
@Suite struct AppleNamesIndirectDependencyTests {
    @Test func setIndirectDependencyAttachesAndDetachesTheProducer() {
        let graph = Graph()
        let source = graph.makeInput(1)
        let producer = graph.makeInput(2)
        let indirect = source.createIndirect()

        indirect.setIndirectDependency(producer.erased)
        #expect(graph.dependency(of: indirect) == producer.erased)

        indirect.setIndirectDependency(nil)
        #expect(graph.dependency(of: indirect) == nil)
    }
}
