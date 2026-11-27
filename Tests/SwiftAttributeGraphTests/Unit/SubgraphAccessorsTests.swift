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

    /// A subgraph created without an explicit parent has no parents in native AttributeGraph (the engine hangs it from
    /// its root internally, but the root is not reported). Oracle scenarios `parents-lone-default-context`,
    /// `parents-lone-other-context`.
    @Test func aSubgraphCreatedWithoutAParentHasNoParents() {
        let graph = Graph()
        let contextB = graph.makeSharedContext()
        let lone = graph.makeSubgraph()
        #expect(lone.parentCount == 0)
        #expect(contextB.makeSubgraph().parentCount == 0)
    }

    /// Oracle scenario `parents-linked-one-parent`: the child has the linked parent, the parent has none.
    @Test func aLinkedChildHasOnlyItsLinkedParent() {
        let graph = Graph()
        let parent = graph.makeSubgraph()
        let child = graph.makeSubgraph()
        parent.addChild(child)
        #expect(child.parentCount == 1)
        #expect(child.parent(at: 0) == parent)
        #expect(parent.parentCount == 0)
    }

    /// Parents are listed in link order and the implicit root is not one of them (oracle scenario
    /// `parents-two-parents-one-dies`: native counts 2, then 1, then 0 as the parents go away).
    @Test func parentsAreListedInLinkOrderWithoutTheImplicitRoot() {
        let graph = Graph()
        let first = graph.makeSubgraph()
        let second = graph.makeSubgraph()
        let contextB = graph.makeSharedContext()
        let child = contextB.makeSubgraph()
        first.addChild(child)
        second.addChild(child)
        #expect(child.parentCount == 2)
        #expect(child.parent(at: 0) == first)
        #expect(child.parent(at: 1) == second)

        graph.invalidate(first)
        #expect(child.parentCount == 1)
        #expect(child.parent(at: 0) == second)

        graph.invalidate(second)
        #expect(child.isValid)
        #expect(child.parentCount == 0)
    }

    /// A subgraph created under an explicit parent (here the current subgraph) reports it (oracle scenario
    /// `parents-via-d-makeSubgraph`).
    @Test func aSubgraphCreatedUnderAnExplicitParentReportsIt() {
        let graph = Graph()
        let scope = graph.makeSubgraph()
        let child = graph.makeSubgraph(parent: scope)
        #expect(child.parentCount == 1)
        #expect(child.parent(at: 0) == scope)
    }
}
