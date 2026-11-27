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

    /// A child shared with a parent that stays alive dies together with its first parent; native
    /// `invalidate_now` then removes it from the other parent's child list with swap-remove. Oracle scenario
    /// `sibling-shared-child-cascade-from-parent-death` (native `afterInvalidateQ=[P, C, Q, X, Y]`).
    @Test func aSharedChildThatDiesWithOneParentLeavesTheOtherParentWithTheSwapRemoveOrder() {
        let graph = Graph()
        let p = graph.makeSubgraph(parent: graph.rootSubgraph)
        let q = graph.makeSubgraph(parent: graph.rootSubgraph)
        let c = graph.makeSubgraph(parent: p)
        graph.addChild(c, to: q)
        let x = graph.makeSubgraph(parent: q)
        let y = graph.makeSubgraph(parent: q)
        #expect(graph.children(of: q) == [c, x, y])

        graph.invalidate(p)

        #expect(graph.children(of: q) == [y, x])
    }

    /// While native `invalidate_now` processes a dying parent it swap-removes each same-context child from the child
    /// lists of the child's other parents, even when such a parent is itself part of the cascade and has not been
    /// processed yet; that parent then walks its already-modified list. A child in another context is only detached
    /// from the dying parent: it is not invalidated and stays in the other parent's list. Oracle fuzzer seed 230
    /// (reduced): native notices `[s1, s0, s5, s4, s6, s8, s7, s3]`, and `s2` (context B) survives.
    @Test func aDyingParentWalksTheListSwapRemovedWhileItsParentWasProcessed() {
        let graph = Graph()
        let contextB = graph.makeSharedContext()
        let s0 = graph.makeSubgraph(parent: graph.rootSubgraph)
        let s1 = graph.makeSubgraph(parent: graph.rootSubgraph)
        // s0 → [s2 (context B), s3, s4, s5, s6].
        let s2 = contextB.makeSubgraph(parent: s0)
        let s3 = graph.makeSubgraph(parent: s0)
        let s4 = graph.makeSubgraph(parent: s0)
        let s5 = graph.makeSubgraph(parent: s0)
        let s6 = graph.makeSubgraph(parent: s0)
        // s1 → [s2, s3, s7, s8, s0]: s2 and s3 are shared with s0, and s0 itself is a child of s1.
        graph.addChild(s2, to: s1)
        graph.addChild(s3, to: s1)
        let s7 = graph.makeSubgraph(parent: s1)
        let s8 = graph.makeSubgraph(parent: s1)
        graph.addChild(s0, to: s1)
        #expect(graph.children(of: s0) == [s2, s3, s4, s5, s6])
        #expect(graph.children(of: s1) == [s2, s3, s7, s8, s0])

        var notices: [String] = []
        let names: [(String, Subgraph)] = [("s0", s0), ("s1", s1), ("s3", s3), ("s4", s4), ("s5", s5), ("s6", s6), ("s7", s7), ("s8", s8)]
        for (name, subgraph) in names { _ = graph.observe(subgraph) { notices.append(name) } }

        graph.invalidate(s1)

        #expect(notices == ["s1", "s0", "s5", "s4", "s6", "s8", "s7", "s3"])
        #expect(s2.isValid)
    }

    /// The two-bit tag of a child moves with the child when swap-remove fills the freed slot (native moves the whole
    /// tagged entry, `*slot = last`).
    @Test func swapRemoveMovesTheTagTogetherWithTheChild() {
        let graph = Graph()
        let parent = graph.makeSubgraph(parent: graph.rootSubgraph)
        let a = graph.makeSubgraph(parent: parent)
        let b = graph.makeSubgraph()
        let c = graph.makeSubgraph()
        let d = graph.makeSubgraph()
        graph.addChild(b, to: parent, tag: 2)
        graph.addChild(c, to: parent, tag: 3)
        graph.addChild(d, to: parent, tag: 1)
        // [a:0, b:2, c:3, d:1]
        #expect(graph.child(of: parent, at: 3).tag == 1)

        graph.removeChild(b, from: parent)

        let entries = (0..<graph.childCount(of: parent)).map { graph.child(of: parent, at: $0) }
        #expect(entries.map(\.subgraph) == [a, d, c])
        #expect(entries.map(\.tag) == [0, 1, 3])
    }

    @Test func aChildThatDiesLeavesTheOtherTagsWithTheirChildren() {
        let graph = Graph()
        let parent = graph.makeSubgraph(parent: graph.rootSubgraph)
        let a = graph.makeSubgraph(parent: parent)
        let b = graph.makeSubgraph()
        let c = graph.makeSubgraph()
        let d = graph.makeSubgraph()
        graph.addChild(b, to: parent, tag: 2)
        graph.addChild(c, to: parent, tag: 3)
        graph.addChild(d, to: parent, tag: 1)

        graph.invalidate(a)

        let entries = (0..<graph.childCount(of: parent)).map { graph.child(of: parent, at: $0) }
        #expect(entries.map(\.subgraph) == [d, b, c])
        #expect(entries.map(\.tag) == [1, 2, 3])
    }
}
