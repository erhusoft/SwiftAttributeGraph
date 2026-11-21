import Testing
@testable import SwiftAttributeGraph

/// `AGGraphGetAttributeSubgraph` (`AGAttribute.subgraph`): the subgraph that owns an attribute, the one current when it
/// was created. Measured with the `attribute-subgraph` oracle scenario.
@Suite struct AttributeSubgraphTests {
    @Test func attributeReportsTheSubgraphThatCreatedIt() {
        let graph = Graph()
        let a = graph.makeSubgraph()
        let b = graph.makeSubgraph()
        let inA = graph.withCurrent(a) { graph.makeInput(1) }
        #expect(inA.subgraph == a)
        #expect(inA.subgraph != b)
    }

    @Test func attributeCreatedOutsideAnySubgraphIsOwnedByTheRootSubgraph() {
        let graph = Graph()
        let outside = graph.makeInput(3)
        #expect(outside.subgraph == graph.rootSubgraph)
    }
}
