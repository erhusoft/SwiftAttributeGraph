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

    /// A child that dies is unlinked from its parents with the same swap-remove as `removeChild` (native
    /// `invalidate_and_delete_` calls `remove_child` on each parent). Oracle scenarios `child-death-middle-then-invalidate-parent`
    /// (native `[B, P, C, D, A]`) and `child-death-first-then-invalidate-parent`.
    @Test func aChildThatIsInvalidatedLeavesItsParentWithTheSwapRemoveOrder() {
        let graph = Graph()
        let parent = graph.makeSubgraph(parent: graph.rootSubgraph)
        let a = graph.makeSubgraph(parent: parent)
        let b = graph.makeSubgraph(parent: parent)
        let c = graph.makeSubgraph(parent: parent)
        let d = graph.makeSubgraph(parent: parent)
        #expect(graph.children(of: parent) == [a, b, c, d])

        graph.invalidate(b)

        #expect(graph.children(of: parent) == [a, d, c])
    }

    @Test func invalidatingTheFirstChildMovesTheLastIntoItsSlot() {
        let graph = Graph()
        let parent = graph.makeSubgraph(parent: graph.rootSubgraph)
        let a = graph.makeSubgraph(parent: parent)
        let b = graph.makeSubgraph(parent: parent)
        let c = graph.makeSubgraph(parent: parent)
        let d = graph.makeSubgraph(parent: parent)

        graph.invalidate(a)

        #expect(graph.children(of: parent) == [d, b, c])
        _ = (b, c, d)
    }
}
