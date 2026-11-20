import Testing
@testable import SwiftAttributeGraph

@Suite("SubgraphDAGTests")
struct SubgraphDAGTests {
    @Test func diamondDAGNotifiesAndReleasesSharedChildOnce() {
        let graph = Graph()
        let r = graph.makeSubgraph()
        let a = graph.makeSubgraph(parent: r)
        let b = graph.makeSubgraph(parent: r)
        let c = graph.makeSubgraph(parent: a)
        b.addChild(c)

        var notifications: [Subgraph] = []
        graph.observe(r) { notifications.append(r) }
        graph.observe(a) { notifications.append(a) }
        graph.observe(b) { notifications.append(b) }
        graph.observe(c) { notifications.append(c) }

        let baseline = graph.liveSubgraphCount - 4
        r.invalidate()

        #expect(graph.liveSubgraphCount == baseline)
        #expect(notifications.count == 4)
        #expect(Set(notifications) == Set([r, a, b, c]))
        #expect(notifications.first == r)
        #expect(!c.isValid)
    }

    @Test func sharedChildInSameContextDiesAndUnlinksFromLivingParent() {
        let graph = Graph()
        let p1 = graph.makeSubgraph()
        let p2 = graph.makeSubgraph()
        let c = graph.makeSubgraph(parent: p1)
        p2.addChild(c)

        let attr = graph.withCurrent(c) { graph.makeInput(42) }
        var cInvalidated = 0
        graph.observe(c) { cInvalidated += 1 }

        p1.invalidate()

        #expect(!p1.isValid)
        #expect(!c.isValid)
        #expect(p2.isValid)
        #expect(cInvalidated == 1)
        #expect(graph.subgraphs.children(of: p2.id.index).isEmpty)
        #expect(!graph.table.isLive(attr.id))
    }

    @Test func sharedChildInDifferentContextSurvivesAndKeepsLivingParent() {
        let graph = Graph()
        let p1 = graph.makeSubgraph()
        let ctx2 = graph.makeSubgraphContext()
        let p2 = graph.makeSubgraph(context: ctx2)
        let c = graph.makeSubgraph(parent: p2) // inherits ctx2 != root context
        p1.addChild(c)

        let attr = graph.withCurrent(c) { graph.makeInput(99) }
        var cInvalidated = 0
        graph.observe(c) { cInvalidated += 1 }

        p1.invalidate()

        #expect(!p1.isValid)
        #expect(p2.isValid)
        #expect(c.isValid)
        #expect(cInvalidated == 0)
        #expect(graph.value(of: attr) == 99)
        #expect(graph.subgraphs.parents(of: c.id.index) == [p2.id.index])
    }

    @Test func deferredInvalidationMarksSameContextFallingAndPreservesDifferentContext() {
        let graph = Graph()
        let p1 = graph.makeSubgraph()
        let ctx2 = graph.makeSubgraphContext()
        let p2 = graph.makeSubgraph(context: ctx2)
        let sameCtxChild = graph.makeSubgraph(parent: p1)
        let diffCtxChild = graph.makeSubgraph(parent: p2)
        p1.addChild(diffCtxChild)

        var sameNotices = 0
        var diffNotices = 0
        graph.observe(sameCtxChild) { sameNotices += 1 }
        graph.observe(diffCtxChild) { diffNotices += 1 }

        graph.withoutSubgraphInvalidation {
            p1.invalidate()
            #expect(!p1.isValid)
            #expect(!sameCtxChild.isValid)
            #expect(diffCtxChild.isValid)
            #expect(sameNotices == 0)
            #expect(diffNotices == 0)
        }

        #expect(sameNotices == 1)
        #expect(diffNotices == 0)
        #expect(diffCtxChild.isValid)
    }

    @Test func reusedSubgraphSlotBumpsGenerationInDAG() {
        let graph = Graph()
        let p = graph.makeSubgraph()
        let c = graph.makeSubgraph(parent: p)
        c.invalidate()

        let reused = graph.makeSubgraph(parent: p)
        #expect(reused.id.index == c.id.index)
        #expect(reused.id.generation != c.id.generation)
        #expect(!c.isValid)
        #expect(reused.isValid)
        #expect(!graph.isAncestor(c, of: p))
        #expect(graph.isAncestor(p, of: reused))
    }

    @Test func observerOrderInDAGIsParentsBeforeChildrenInReverseCreationOrder() {
        let graph = Graph()
        let root = graph.makeSubgraph()
        let first = graph.makeSubgraph(parent: root)
        let second = graph.makeSubgraph(parent: root)
        let leaf = graph.makeSubgraph(parent: first)
        second.addChild(leaf)

        var order: [String] = []
        graph.observe(root) { order.append("root") }
        graph.observe(first) { order.append("first") }
        graph.observe(second) { order.append("second") }
        graph.observe(leaf) { order.append("leaf") }

        root.invalidate()

        // LIFO stack pops `root`, then `second` (last linked), then `leaf`, then `first`.
        #expect(order == ["root", "second", "leaf", "first"])
    }

    @Test func subgraphForCreatingPicksLivingNonFallingParentInDAG() {
        let graph = Graph()
        let fallingParent = graph.makeSubgraph()
        let livingParent = graph.makeSubgraph(context: graph.makeSubgraphContext())
        let child = graph.makeSubgraph(parent: livingParent)
        fallingParent.addChild(child)

        graph.withoutSubgraphInvalidation {
            fallingParent.invalidate()
            graph.setFallingForTesting(child, true)
            let chosen = graph.subgraphForCreating(in: child.id.index)
            #expect(chosen == livingParent.id)
        }
    }

    @Test func flagsFollowReverseCreationOrderAcrossDAGAndStopWhenUnlinked() {
        let graph = Graph()
        let p1 = graph.makeSubgraph()
        let p2 = graph.makeSubgraph()
        let shared = graph.makeSubgraph(parent: p1)
        p2.addChild(shared)

        let a = graph.withCurrent(shared) { graph.makeInput(1) }
        graph.setFlags([.init(rawValue: 1 << 0)], for: a)

        var visitedFromP2: [Int] = []
        graph.forEach(in: p2, flags: [.init(rawValue: 1 << 0)]) { attr in
            visitedFromP2.append(Int(attr.id.index))
        }
        #expect(visitedFromP2 == [Int(a.id.index)])

        p2.removeChild(shared)
        var visitedAfterUnlink: [Int] = []
        graph.forEach(in: p2, flags: [.init(rawValue: 1 << 0)]) { attr in
            visitedAfterUnlink.append(Int(attr.id.index))
        }
        #expect(visitedAfterUnlink.isEmpty)
    }

    @Test func addingCycleStopsTheProgram() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            let p = graph.makeSubgraph()
            let c = graph.makeSubgraph(parent: p)
            c.addChild(p)
        }
    }

    @Test func repeatedAddChildDoesNotDuplicateEdge() {
        let graph = Graph()
        let p = graph.makeSubgraph()
        let c = graph.makeSubgraph(parent: p)

        p.addChild(c)
        p.addChild(c)

        #expect(graph.subgraphs.children(of: p.id.index) == [c.id.index])
        #expect(graph.subgraphs.parents(of: c.id.index) == [p.id.index])
    }

    @Test func removingNonExistentChildIsNoOp() {
        let graph = Graph()
        let p1 = graph.makeSubgraph()
        let p2 = graph.makeSubgraph()
        let c = graph.makeSubgraph(parent: p1)

        p2.removeChild(c)

        #expect(graph.subgraphs.parents(of: c.id.index) == [p1.id.index])
        #expect(graph.subgraphs.children(of: p2.id.index).isEmpty)
    }

    @Test func invalidatingBothParentsInSequenceWithDifferentContextKillsChildOnSecondParent() {
        let graph = Graph()
        let p1 = graph.makeSubgraph()
        let ctx2 = graph.makeSubgraphContext()
        let p2 = graph.makeSubgraph(context: ctx2)
        let c = graph.makeSubgraph(parent: p2)
        p1.addChild(c)

        var cNotices = 0
        graph.observe(c) { cNotices += 1 }

        p1.invalidate()
        #expect(c.isValid)
        #expect(cNotices == 0)

        p2.invalidate()
        #expect(!c.isValid)
        #expect(cNotices == 1)
    }
}

private extension Graph {
    func setFallingForTesting(_ subgraph: Subgraph, _ value: Bool) {
        subgraphs.setFalling(index: subgraph.id.index, value)
    }
}
