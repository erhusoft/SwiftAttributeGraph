import Testing
@testable import SwiftAttributeGraph

/// Aging of the `Rule.cachedValue` cache. Measured on macOS 15.8.3 (oracle scenarios `z0`, `p1`/`p2`/`p3`, `e-*`, `m3`): an
/// entry is parked with age 1, each pass adds 1 and it is freed at 255 (254 passes after parking); a new key of the same type
/// takes over the oldest parked entry of age 2 or more. A pass is an invalidation, `update(_:)` or the end of a deferral;
/// leaving `withCurrent` or reading a top-level rule is not.
@Suite struct RuleCachedValueAgingTests {
    final class Counter { var runs = 0 }

    struct K: Rule, Hashable {
        let id: Int
        let counter: Counter
        var value: Int { counter.runs += 1; return id * 10 }
        static func == (l: K, r: K) -> Bool { l.id == r.id }
        func hash(into h: inout Hasher) { h.combine(id) }
    }

    enum Form { case invalidate, update, deferral }

    private func pass(_ graph: Graph, _ sg: Subgraph, _ form: Form) {
        switch form {
        case .invalidate: graph.invalidate(graph.makeSubgraph())
        case .update: graph.update(sg)
        case .deferral:
            let was = graph.beginDeferringSubgraphInvalidation()
            graph.endDeferringSubgraphInvalidation(wasDeferring: was)
        }
    }

    private func value(_ graph: Graph, _ sg: Subgraph, _ k: K) -> Int {
        graph.withCurrent(sg) { k.cachedValue(owner: nil) }
    }

    @Test func withoutAPassANewKeyDoesNotTakeOverAnEntry() { // z0 [10, 20, 10, 1, 2, 2]
        let graph = Graph(); let sg = graph.makeSubgraph(); let c = Counter()
        #expect(value(graph, sg, K(id: 1, counter: c)) == 10)
        #expect(value(graph, sg, K(id: 2, counter: c)) == 20)
        #expect(value(graph, sg, K(id: 1, counter: c)) == 10)
        #expect(c.runs == 2)
    }

    @Test(arguments: [Form.invalidate, .update, .deferral])
    func aNewKeyTakesOverTheOldestParkedEntryAfterOnePass(_ form: Form) { // p*-k2-1 [10, 20, 10, 1, 2, 3]
        let graph = Graph(); let sg = graph.makeSubgraph(); let c = Counter()
        #expect(value(graph, sg, K(id: 1, counter: c)) == 10)
        pass(graph, sg, form)
        #expect(value(graph, sg, K(id: 2, counter: c)) == 20)
        #expect(c.runs == 2)
        #expect(value(graph, sg, K(id: 1, counter: c)) == 10)
        #expect(c.runs == 3)
    }

    @Test(arguments: [Form.invalidate, .update, .deferral])
    func anEntryStaysAfterFewPassesIfNobodyTakesItOver(_ form: Form) { // p*-k1-1..3 [10, 10, 1, 1]
        let graph = Graph(); let sg = graph.makeSubgraph(); let c = Counter()
        #expect(value(graph, sg, K(id: 1, counter: c)) == 10)
        for _ in 0..<3 { pass(graph, sg, form) }
        #expect(value(graph, sg, K(id: 1, counter: c)) == 10)
        #expect(c.runs == 1)
    }

    @Test func anEntryIsFreedAfter254PassesButNotAfter253() { // e-apply-253 [1, 1], e-apply-254 [1, 2]
        for (passes, expectedRuns) in [(253, 1), (254, 2)] {
            let graph = Graph(); let sg = graph.makeSubgraph(); let c = Counter()
            #expect(value(graph, sg, K(id: 1, counter: c)) == 10)
            for _ in 0..<passes { pass(graph, sg, .invalidate) }
            #expect(value(graph, sg, K(id: 1, counter: c)) == 10)
            #expect(c.runs == expectedRuns)
        }
    }

    @Test func readingATopLevelRuleManyTimesDoesNotAge() { // c12e-300 [10, 10, 1, 1]
        let graph = Graph(); let sg = graph.makeSubgraph(); let c = Counter()
        let input = graph.withCurrent(sg) { graph.makeInput(0) }
        let top = graph.withCurrent(sg) { graph.makeRule { input.value + 1 } }
        #expect(value(graph, sg, K(id: 1, counter: c)) == 10)
        for i in 1...300 { graph.setValue(i, for: input); _ = graph.value(of: top) }
        #expect(value(graph, sg, K(id: 1, counter: c)) == 10)
        #expect(c.runs == 1)
    }

    @Test func theOldestParkedEntryIsTakenOverFirst() { // m3-recycle-order [1, 2, 3, 4, 5, 6, 7]
        let graph = Graph(); let sg = graph.makeSubgraph(); let c = Counter()
        var runs: [Int] = []
        for id in 1...3 { _ = value(graph, sg, K(id: id, counter: c)); runs.append(c.runs) }
        pass(graph, sg, .invalidate)
        _ = value(graph, sg, K(id: 4, counter: c)); runs.append(c.runs)
        for id in 1...3 { _ = value(graph, sg, K(id: id, counter: c)); runs.append(c.runs) }
        #expect(runs == [1, 2, 3, 4, 5, 6, 7])
    }
}
