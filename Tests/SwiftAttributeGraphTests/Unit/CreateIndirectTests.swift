import Testing
@testable import SwiftAttributeGraph

/// `AGGraphCreateIndirectAttribute` (`AGAttribute.createIndirect(self:)`). The indirect attribute reads its source, so it
/// follows writes to the source. Its behaviour is the one the `indirect-*` oracle scenarios already measure through
/// `IndirectHandle`; this checks the Apple-named method.
@Suite struct CreateIndirectTests {
    @Test func theIndirectAttributeFollowsItsSource() {
        let graph = Graph()
        let source = graph.makeInput(1)
        let indirect = source.createIndirect()
        #expect(graph.value(of: indirect) == 1)
        graph.setValue(2, for: source)
        #expect(graph.value(of: indirect) == 2)
    }
}
