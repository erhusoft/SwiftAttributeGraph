import Testing
@testable import SwiftAttributeGraph

@Suite("AppleNamesAccessorsTests")
struct AppleNamesAccessorsTests {
    @Test func attributeAccessorsMatchAppleSemantics() {
        let graph = Graph()
        let sub = graph.makeSubgraph(parent: graph.rootSubgraph)
        let a = graph.withCurrent(sub) { graph.makeInput(42) }
        let ind = graph.withCurrent(sub) { graph.makeIndirect(a) }

        // Test AnyAttribute accessors
        let anyA = a.erased
        #expect(anyA.graph === graph)
        #expect(anyA.subgraph == sub)
        #expect(anyA.subgraphOrNil == sub)
        #expect(anyA.hasValue == true)
        #expect(anyA.valueState.contains(.valueExists))

        // Test Attribute<Value> accessors
        #expect(a.graph === graph)
        #expect(a.subgraph == sub)
        #expect(a.subgraphOrNil == sub)
        #expect(a.hasValue == true)
        #expect(a.valueState.contains(.valueExists))

        // Test source getter/setter
        #expect(ind.source == a)
        let b = graph.withCurrent(sub) { graph.makeInput(99) }
        ind.source = b
        #expect(ind.source == b)

        let anyInd = ind.erased
        #expect(anyInd.source == b.erased)
        anyInd.source = a.erased
        #expect(anyInd.source == a.erased)
        #expect(ind.source == a)
    }

    @Test func subgraphShouldRecordTreeCanBeSetAndQueried() {
        #expect(Subgraph.shouldRecordTree == false)
        Subgraph.setShouldRecordTree()
        #expect(Subgraph.shouldRecordTree == true)
    }
}
