import Testing
@testable import SwiftAttributeGraph

@Suite("AppleNamesTests")
struct AppleNamesTests {
    /// Apple's subgraph methods (AGSubgraphRef.addChild / removeChild / invalidate / isValid) are available on the
    /// handle itself, resolving the graph from the subgraph's tag [O, native headers AGSubgraph.h].
    @Test func subgraphMethodsMatchTheAppleNames() {
        let graph = Graph()
        let parent = graph.makeSubgraph()
        let child = graph.makeSubgraph()
        #expect(parent.isValid)

        parent.addChild(child)
        #expect(child.isValid)

        parent.invalidate()
        #expect(parent.isValid == false)
        #expect(child.isValid == false)
    }

    @Test func removeChildOnTheParentHandle() {
        let graph = Graph()
        let parent = graph.makeSubgraph()
        let child = graph.makeSubgraph()
        parent.addChild(child)
        parent.removeChild(child)
        #expect(child.isValid)
    }
}
