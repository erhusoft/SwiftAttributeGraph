import Testing
@testable import SwiftAttributeGraph

/// Removing a child moves the last child into the removed slot (native `AG::Subgraph::remove_child`, swap-remove), so the
/// sibling order is [A, B, C, D] → [A, D, C] after removing B. Oracle scenario `subgraph-sibling-order-after-remove`.
@Suite struct SubgraphSwapRemoveTests {
    @Test func removingAMiddleChildMovesTheLastChildIntoItsSlot() {
        let graph = Graph()
        let parent = graph.makeSubgraph(parent: graph.rootSubgraph)
        let a = graph.makeSubgraph(parent: parent)
        let b = graph.makeSubgraph(parent: parent)
        let c = graph.makeSubgraph(parent: parent)
        let d = graph.makeSubgraph(parent: parent)
        #expect(graph.children(of: parent) == [a, b, c, d])

        graph.removeChild(b, from: parent)

        #expect(graph.children(of: parent) == [a, d, c])
    }

    @Test func removingTheLastChildKeepsTheOthersInOrder() {
        let graph = Graph()
        let parent = graph.makeSubgraph(parent: graph.rootSubgraph)
        let a = graph.makeSubgraph(parent: parent)
        let b = graph.makeSubgraph(parent: parent)
        let c = graph.makeSubgraph(parent: parent)

        graph.removeChild(c, from: parent)

        #expect(graph.children(of: parent) == [a, b])
    }
}
