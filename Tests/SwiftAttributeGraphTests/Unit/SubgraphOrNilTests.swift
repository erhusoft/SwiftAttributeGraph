import Testing
@testable import SwiftAttributeGraph

/// `AGGraphGetAttributeSubgraph2` (`AGAttribute.subgraphOrNil`). Measured with the `subgraph-or-nil` oracle scenario on
/// macOS 15.8: a live attribute has its subgraph, and an attribute whose subgraph was freed returns nil instead of trapping.
@Suite struct SubgraphOrNilTests {
    @Test func aLiveAttributeReportsItsSubgraph() {
        let graph = Graph()
        let subgraph = graph.makeSubgraph()
        let input = graph.withCurrent(subgraph) { graph.makeInput(1) }
        #expect(input.subgraphOrNil == subgraph)
    }

    @Test func aFreedAttributeReportsNil() {
        let graph = Graph()
        let subgraph = graph.makeSubgraph()
        let input = graph.withCurrent(subgraph) { graph.makeInput(1) }
        subgraph.invalidate()
        #expect(input.subgraphOrNil == nil)
    }
}
