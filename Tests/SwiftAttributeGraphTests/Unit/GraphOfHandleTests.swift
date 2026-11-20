import Testing
@testable import SwiftAttributeGraph

/// `Attribute.graph`, `AnyAttribute.graph`, `Subgraph.graph` and `Graph.graph(of:)`: the graph a handle belongs to
/// (`AGGraphGetAttributeGraph` and `AGSubgraphGetGraph` in native AttributeGraph). Native returns the very graph object
/// the attribute or subgraph was created with, also with two graphs in the process; asking a dead handle traps [O].
@Suite struct GraphOfHandleTests {
    @Test func anAttributeKnowsItsGraph() {
        let graph = Graph()
        let input = graph.makeInput(1)
        let rule = graph.makeRule { graph.value(of: input) + 1 }
        #expect(input.graph === graph)
        #expect(rule.graph === graph)
        #expect(input.erased.graph === graph)
        #expect(Graph.graph(of: rule.erased) === graph)
    }

    @Test func twoGraphsInTheSameProcessDoNotMix() {
        let g1 = Graph()
        let g2 = Graph()
        let s1 = g1.makeSubgraph()
        let s1b = g1.makeSubgraph()
        let s2 = g2.makeSubgraph()
        let a1 = g1.withCurrent(s1) { g1.makeInput(1) }
        let a2 = g2.withCurrent(s2) { g2.makeInput(2) }
        let b1 = g1.withCurrent(s1b) { g1.makeInput(3) }
        #expect(a1.id.index == a2.id.index, "the same slot index in two graphs")
        #expect(a1.graph === g1 && a2.graph === g2 && b1.graph === g1)
        #expect(a1.graph !== g2 && a1.graph !== a2.graph)
        #expect(s1.graph === g1 && s1b.graph === g1 && s2.graph === g2 && s1.graph !== g2)
        #expect(g1.rootSubgraph.graph === g1)
        #expect(a1.id != a2.id, "IDs of different graphs differ even in the same slot")
        #expect(s1.id != s2.id)
    }

    @Test func aRecycledSlotStillBelongsToTheSameGraph() {
        let graph = Graph()
        let sub = graph.makeSubgraph()
        let old = graph.withCurrent(sub) { graph.makeInput(1) }
        sub.invalidate()
        let fresh = graph.makeInput(2)
        #expect(fresh.id.index == old.id.index)
        #expect(fresh.graph === graph)
        #expect(Graph.graph(of: old.erased) == nil, "a dead attribute belongs to no graph")
        let again = graph.makeSubgraph()
        #expect(again.graph === graph)
        again.invalidate()
        #expect(Graph.graph(of: again) == nil)
    }

    @Test func aSlotReusedManyTimesKeepsResolvingToItsGraph() {
        let graph = Graph()
        var last = graph.makeInput(0)
        let sub = graph.makeSubgraph()
        var current = sub
        // More cycles than the 16 bits of generation that one slot can use: the slot is retired, never wrapped.
        for i in 0..<70_000 {
            let attribute = graph.withCurrent(current) { graph.makeInput(i) }
            #expect(attribute.graph === graph)
            current.invalidate()
            #expect(Graph.graph(of: attribute.erased) == nil)
            #expect(Graph.graph(of: current) == nil)
            current = graph.makeSubgraph()
            last = attribute
        }
        #expect(Graph.graph(of: last.erased) == nil)
        let survivor = graph.withCurrent(current) { graph.makeInput(1) }
        #expect(survivor.graph === graph)
        #expect(graph.value(of: survivor) == 1)
    }

    @Test func aHandleOfAGraphThatIsGoneBelongsToNothing() {
        var attribute: Attribute<Int>?
        var subgraph: Subgraph?
        do {
            let graph = Graph()
            attribute = graph.makeInput(1)
            subgraph = graph.makeSubgraph()
        }
        let later = Graph()
        _ = later.makeInput(1)
        #expect(Graph.graph(of: attribute!.erased) == nil)
        #expect(Graph.graph(of: subgraph!) == nil)
    }
}
