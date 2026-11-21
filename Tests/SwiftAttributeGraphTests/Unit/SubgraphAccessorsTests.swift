import Testing
@testable import SwiftAttributeGraph

/// `AGSubgraphAddChild2` and the accessors `AGSubgraphGetChild`, `GetChildCount`, `GetParent`, `GetParentCount`. Measured
/// with the `subgraph-accessors` and `subgraph-tags` oracle scenarios on macOS 15.8: children keep their insertion order,
/// a child's tag is stored in two bits (tags 0 to 3 are kept, 5 and 9 become 1), and parents are listed in the order they
/// were linked, with the root subgraph first.
@Suite struct SubgraphAccessorsTests {
    @Test func childrenKeepTheirOrderAndTags() {
        let graph = Graph()
        let parent = graph.makeSubgraph()
        let first = graph.makeSubgraph()
        let second = graph.makeSubgraph()
        parent.addChild(first)
        parent.addChild(second, tag: 3)
        #expect(parent.childCount == 2)
        let (c0, t0) = parent.child(at: 0)
        let (c1, t1) = parent.child(at: 1)
        #expect(c0 == first)
        #expect(t0 == 0)
        #expect(c1 == second)
        #expect(t1 == 3)
    }

    @Test func tagsAreStoredInTwoBits() {
        let graph = Graph()
        let parent = graph.makeSubgraph()
        let child = graph.makeSubgraph()
        parent.addChild(child, tag: 5)
        #expect(parent.child(at: 0).tag == 1)
    }

    @Test func parentsAreListedInLinkOrderWithTheRootFirst() {
        let graph = Graph()
        let first = graph.makeSubgraph()
        let second = graph.makeSubgraph()
        let child = graph.makeSubgraph()
        first.addChild(child)
        second.addChild(child)
        #expect(child.parentCount == 3)
        #expect(child.parent(at: 0) == graph.rootSubgraph)
        #expect(child.parent(at: 1) == first)
        #expect(child.parent(at: 2) == second)
    }
}
