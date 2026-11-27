import Testing
@testable import SwiftAttributeGraph

/// `Rule.cachedValue(options:owner:)` and `cachedValueIfExists(options:owner:)`. Expected values measured on macOS 15.8.3
/// by oracle scenarios `c0` to `c10` (native lines in comments). `_cachedValue`, the options bits and aging are not covered.
@Suite struct RuleCachedValueTests {
    final class Counter { var runs = 0 }

    /// Equal and hashed by `id` only: `tag` does not count.
    struct K: Rule, Hashable {
        let id: Int
        let tag: Int
        let counter: Counter
        var value: Int { counter.runs += 1; return id * 10 }
        static func == (l: K, r: K) -> Bool { l.id == r.id }
        func hash(into h: inout Hasher) { h.combine(id) }
    }

    /// Reads an input, so changing it must re-evaluate.
    struct KDep: Rule, Hashable {
        let id: Int
        let src: Attribute<Int>
        let counter: Counter
        var value: Int { counter.runs += 1; return src.value * 10 }
        static func == (l: KDep, r: KDep) -> Bool { l.id == r.id }
        func hash(into h: inout Hasher) { h.combine(id) }
    }

    @Test func theFirstCallRunsTheBodyOnce() { // c0 [10, 1]
        let graph = Graph(); let sg = graph.makeSubgraph(); let c = Counter()
        let v = graph.withCurrent(sg) { K(id: 1, tag: 0, counter: c).cachedValue(owner: nil) }
        #expect(v == 10); #expect(c.runs == 1)
    }

    @Test func theSameInstanceTwiceRunsTheBodyOnce() { // c1 [10, 10, 1, 1]
        let graph = Graph(); let sg = graph.makeSubgraph(); let c = Counter()
        let k = K(id: 1, tag: 0, counter: c)
        graph.withCurrent(sg) {
            #expect(k.cachedValue(owner: nil) == 10)
            #expect(k.cachedValue(owner: nil) == 10)
        }
        #expect(c.runs == 1)
    }

    @Test func anEqualRuleWithADifferentTagHitsTheCache() { // c2 [10, 10, 1, 1]
        let graph = Graph(); let sg = graph.makeSubgraph(); let c = Counter()
        graph.withCurrent(sg) {
            #expect(K(id: 1, tag: 0, counter: c).cachedValue(owner: nil) == 10)
            #expect(K(id: 1, tag: 99, counter: c).cachedValue(owner: nil) == 10)
        }
        #expect(c.runs == 1)
    }

    @Test func aRuleThatIsNotEqualRunsItsOwnBody() { // c3 [10, 20, 1, 2]
        let graph = Graph(); let sg = graph.makeSubgraph(); let c = Counter()
        graph.withCurrent(sg) {
            #expect(K(id: 1, tag: 0, counter: c).cachedValue(owner: nil) == 10)
            #expect(K(id: 2, tag: 0, counter: c).cachedValue(owner: nil) == 20)
        }
        #expect(c.runs == 2)
    }

    @Test func ifExistsFindsACachedRule() { // c4 [10, Optional(10), 1, 1]
        let graph = Graph(); let sg = graph.makeSubgraph(); let c = Counter()
        let k = K(id: 1, tag: 0, counter: c)
        graph.withCurrent(sg) {
            #expect(k.cachedValue(owner: nil) == 10)
            #expect(k.cachedValueIfExists(owner: nil) == 10)
        }
        #expect(c.runs == 1)
    }

    @Test func ifExistsGivesNilForANewKeyAndRunsNothing() { // c5 [10, nil, 1, 1]
        let graph = Graph(); let sg = graph.makeSubgraph(); let c = Counter()
        graph.withCurrent(sg) {
            #expect(K(id: 1, tag: 0, counter: c).cachedValue(owner: nil) == 10)
            #expect(K(id: 2, tag: 0, counter: c).cachedValueIfExists(owner: nil) == nil)
        }
        #expect(c.runs == 1)
    }

    @Test func theCacheIsPerSubgraph() { // c6 [10, 10, 1, 2]
        let graph = Graph(); let a = graph.makeSubgraph(); let b = graph.makeSubgraph(); let c = Counter()
        let k = K(id: 1, tag: 0, counter: c)
        graph.withCurrent(a) { #expect(k.cachedValue(owner: nil) == 10) }
        #expect(c.runs == 1)
        graph.withCurrent(b) { #expect(k.cachedValue(owner: nil) == 10) }
        #expect(c.runs == 2)
    }

    @Test func theOwnerChoosesTheSubgraphThatHoldsTheEntry() { // c7 [10, 10, 10, 1, 2, 2]
        let graph = Graph(); let a = graph.makeSubgraph(); let b = graph.makeSubgraph(); let c = Counter()
        let ownerInB = graph.withCurrent(b) { graph.makeInput(0) }
        let k = K(id: 1, tag: 0, counter: c)
        graph.withCurrent(a) { #expect(k.cachedValue(owner: ownerInB.erased) == 10) }
        #expect(c.runs == 1)
        graph.withCurrent(a) { #expect(k.cachedValue(owner: nil) == 10) }
        #expect(c.runs == 2)
        graph.withCurrent(b) { #expect(k.cachedValue(owner: nil) == 10) }
        #expect(c.runs == 2)
    }

    @Test func aChangedInputReEvaluatesOutsideARule() { // c9 outside [10, 20, 1, 2]
        let graph = Graph(); let sg = graph.makeSubgraph(); let c = Counter()
        let x = graph.withCurrent(sg) { graph.makeInput(1) }
        let k = KDep(id: 1, src: x, counter: c)
        graph.withCurrent(sg) {
            #expect(k.cachedValue(owner: nil) == 10)
            graph.setValue(2, for: x)
            #expect(k.cachedValue(owner: nil) == 20)
        }
        #expect(c.runs == 2)
    }

    @Test func aChangedInputReEvaluatesInsideARule() { // c9 in rule [10, 20, 1, 2]
        let graph = Graph(); let sg = graph.makeSubgraph(); let c = Counter()
        let x = graph.withCurrent(sg) { graph.makeInput(1) }
        let r = graph.withCurrent(sg) {
            graph.makeRule { KDep(id: 1, src: x, counter: c).cachedValue(owner: nil) }
        }
        #expect(graph.value(of: r) == 10)
        graph.setValue(2, for: x)
        #expect(graph.value(of: r) == 20)
        #expect(c.runs == 2)
    }

    @Test func callingWithoutACurrentSubgraphStopsTheProgram() async { // c10 SIGABRT "no subgraph"
        await #expect(processExitsWith: .failure) {
            let c = Counter()
            _ = K(id: 1, tag: 0, counter: c).cachedValue(owner: nil)
        }
    }
}
