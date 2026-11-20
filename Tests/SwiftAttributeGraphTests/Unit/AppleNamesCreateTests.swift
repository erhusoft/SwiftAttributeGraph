import Testing
@testable import SwiftAttributeGraph

@Suite("AppleNamesCreateTests")
struct AppleNamesCreateTests {
    /// Apple's `AGSubgraphRef.init(graph:)`: a subgraph owned by the current subgraph, like `makeSubgraph()` [O,
    /// native headers AGSubgraph.h].
    @Test func initWithGraphCreatesASubgraphOwnedByTheCurrentOne() {
        let graph = Graph()
        let parent = graph.makeSubgraph()
        let child = graph.withCurrent(parent) { Subgraph(graph: graph) }
        #expect(child.isValid)

        parent.invalidate()
        #expect(child.isValid == false)
    }
}
