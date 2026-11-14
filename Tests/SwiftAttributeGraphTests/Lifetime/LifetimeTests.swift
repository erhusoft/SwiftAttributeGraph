import Testing
@testable import SwiftAttributeGraph

/// Principle 2: nothing persists without an owner. After invalidating subgraphs, `nodeCount` is back to its base and
/// no edge, output or observer of a dead attribute is left behind.
@Suite struct LifetimeTests {
    @Test func creatingAndDestroyingManySubgraphsLeavesNoNodes() {
        let graph = Graph()
        let base = graph.makeInput(0)
        for round in 0..<20 {
            let subgraphs = (0..<1_000).map { _ in graph.makeSubgraph() }
            for subgraph in subgraphs {
                graph.withCurrent(subgraph) {
                    let state = graph.makeInput(round)
                    let body = graph.makeRule { state.value + base.value }
                    _ = graph.value(of: body)
                }
            }
            for subgraph in subgraphs { graph.invalidate(subgraph) }
            #expect(graph.nodeCount == 1)
        }
        #expect(graph.table.outputs[Int(base.id.index)].isEmpty, "the survivor keeps no reader of a dead rule")
    }

    @Test func invalidatingRemovesTheEdgesInBothDirections() {
        let graph = Graph()
        let outsideSource = graph.makeInput(1)
        let sub = graph.makeSubgraph()
        let inside = graph.withCurrent(sub) { graph.makeRule { outsideSource.value + 1 } }
        _ = graph.value(of: inside)
        #expect(graph.table.outputs[Int(outsideSource.id.index)].count == 1)
        graph.invalidate(sub)
        #expect(graph.table.outputs[Int(outsideSource.id.index)].isEmpty)
    }

    @Test func invalidatingASubgraphWhoseRulesReadEachOtherLeavesNothing() {
        let graph = Graph()
        let sub = graph.makeSubgraph()
        graph.withCurrent(sub) {
            let a = graph.makeInput(1)
            let b = graph.makeRule { a.value + 1 }
            let c = graph.makeRule { b.value + a.value }
            _ = graph.value(of: c)
        }
        graph.invalidate(sub)
        #expect(graph.nodeCount == 0)
    }

    @Test func observersOfADeadAttributeAreDropped() {
        final class Counter { var count = 0 }
        let graph = Graph()
        let sub = graph.makeSubgraph()
        let told = Counter()
        let dead = graph.withCurrent(sub) { graph.makeInput(1) }
        graph.observe(dead.erased) { told.count += 1 }
        graph.invalidate(sub)
        let reborn = graph.makeInput(2)           // takes the freed slot
        graph.setValue(3, for: reborn)
        #expect(told.count == 0, "an observer must not follow the slot to the attribute that reuses it")
        #expect(graph.observers.isEmpty)
    }

    @Test func aWholeGraphCanBeDroppedWithItsSubgraphs() {
        weak var weakGraph: Graph?
        do {
            let graph = Graph()
            weakGraph = graph
            let sub = graph.makeSubgraph()
            graph.withCurrent(sub) { _ = graph.makeRule { 1 } }
        }
        #expect(weakGraph == nil, "a graph must not be kept alive by its own attributes or rules")
    }

    // MARK: M5

    @Test func branchesAndRowsLeaveNothingBehindEvenWhenInvalidatedInsideRules() {
        let graph = Graph()
        let switcher = graph.makeInput(0)
        let baseNodes = graph.nodeCount, baseSubgraphs = graph.liveSubgraphCount
        var branch = graph.makeSubgraph()
        let host = graph.makeRule { () -> Int in
            let round = switcher.value
            if round > 0 {                                                      // the view body swaps its branch
                let old = branch
                branch = graph.makeSubgraph()
                graph.withCurrent(branch) {
                    for _ in 0..<10 { _ = graph.makeSubgraph() }
                    _ = graph.makeInput(round)
                }
                graph.invalidate(old)
            }
            return round
        }
        _ = graph.value(of: host)
        for round in 1...200 {
            graph.setValue(round, for: switcher)
            #expect(graph.value(of: host) == round)
        }
        graph.invalidate(branch)
        #expect(graph.nodeCount == baseNodes + 1)                               // `host` is the only addition
        #expect(graph.liveSubgraphCount == baseSubgraphs)
        #expect(graph.subgraphs.slotCount < 40, "the slots of dead subgraphs are reused")
    }
}
