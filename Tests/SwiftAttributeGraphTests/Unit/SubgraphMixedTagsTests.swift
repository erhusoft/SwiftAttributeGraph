import Testing
@testable import SwiftAttributeGraph

/// Child tags stay with their children when untagged and tagged links are mixed, and when the untagged ones come after a
/// tagged one. Tags are stored only once a non-zero tag is used, so this covers the switch from untagged to tagged.
@Suite struct SubgraphMixedTagsTests {
    @Test func tagsStayWithTheirChildrenWhenUntaggedAndTaggedLinksAreMixed() {
        let graph = Graph()
        let parent = Subgraph(graph: graph)
        let a = Subgraph(graph: graph)
        let b = Subgraph(graph: graph)
        let c = Subgraph(graph: graph)

        parent.addChild(a)
        parent.addChild(b, tag: 2)
        parent.addChild(c)

        #expect(parent.childCount == 3)
        #expect(parent.child(at: 0).subgraph == a)
        #expect(parent.child(at: 0).tag == 0)
        #expect(parent.child(at: 1).subgraph == b)
        #expect(parent.child(at: 1).tag == 2)
        #expect(parent.child(at: 2).subgraph == c)
        #expect(parent.child(at: 2).tag == 0)
    }
}
