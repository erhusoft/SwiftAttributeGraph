import Testing
@testable import SwiftAttributeGraph

/// Rules: lazy evaluation, the cut by version, dynamic dependencies and their pruning, order and cycles.
@Suite struct RuleTests {
    /// A counter the rule closures can bump without capturing a mutable local from several places.
    private final class Counter { var runs = 0 }

    @Test func aRuleIsLazyAndRunsOnlyWhenRead() {
        let graph = Graph()
        let input = graph.makeInput(2)
        let counter = Counter()
        let output = graph.makeRule { counter.runs += 1; return input.value * 3 }

        #expect(counter.runs == 0)
        graph.setValue(4, for: input)
        #expect(counter.runs == 0, "a write must not run rules")
        #expect(graph.value(of: output) == 12)
        #expect(counter.runs == 1)
        #expect(graph.value(of: output) == 12)
        #expect(counter.runs == 1, "a clean read does no work")
    }

    @Test func aRuleCanBeAType() {
        struct Doubled: Rule {
            let source: Attribute<Int>
            var value: Int { source.value * 2 }
        }
        let graph = Graph()
        let input = graph.makeInput(5)
        let output = graph.makeRule(Doubled(source: input))
        #expect(graph.value(of: output) == 10)
        graph.setValue(6, for: input)
        #expect(graph.value(of: output) == 12)
    }

    @Test func readsInsideARuleWorkWithBothSpellings() {
        let graph = Graph()
        let input = graph.makeInput(3)
        let viaProperty = graph.makeRule { input.value + 1 }
        let viaGraph = graph.makeRule { graph.value(of: input) + 1 }
        #expect(graph.value(of: viaProperty) == 4)
        #expect(graph.value(of: viaGraph) == 4)
    }

    /// E1: a dependent whose input did not change in value is not run, even though it was marked dirty.
    @Test func aDependentIsNotRunWhenItsInputRecomputedToTheSameValue() {
        let graph = Graph()
        let input = graph.makeInput(2)
        let parity = Counter(), label = Counter()
        let evenOrOdd = graph.makeRule { parity.runs += 1; return input.value % 2 }
        let text = graph.makeRule { label.runs += 1; return evenOrOdd.value == 0 ? "even" : "odd" }

        #expect(graph.value(of: text) == "even")
        #expect((parity.runs, label.runs) == (1, 1))
        graph.setValue(4, for: input)          // still even
        #expect(graph.value(of: text) == "even")
        #expect((parity.runs, label.runs) == (2, 1), "the second rule must be skipped")
        graph.setValue(5, for: input)
        #expect(graph.value(of: text) == "odd")
        #expect((parity.runs, label.runs) == (3, 2))
    }

    @Test func onlyTheRequestedBranchesRecompute() {
        let graph = Graph()
        let root = graph.makeInput(1)
        let counter = Counter()
        let leaves = (0..<50).map { _ in graph.makeRule { counter.runs += 1; return root.value + 1 } }
        graph.setValue(2, for: root)
        #expect(counter.runs == 0)
        #expect(graph.value(of: leaves[0]) == 3)
        #expect(counter.runs == 1)
        #expect(graph.value(of: leaves[1]) == 3)
        #expect(counter.runs == 2)
    }

    @Test func dependenciesAreDiscoveredAndPrunedWhenNoLongerRead() {
        let graph = Graph()
        let selector = graph.makeInput(0)
        let left = graph.makeInput(11)
        let right = graph.makeInput(22)
        let counter = Counter()
        let output = graph.makeRule { counter.runs += 1; return selector.value == 0 ? left.value : right.value }

        #expect(graph.value(of: output) == 11)
        #expect(graph.inputs(of: output.id) == [selector.id, left.id])
        graph.setValue(1, for: selector)
        #expect(graph.value(of: output) == 22)
        #expect(graph.inputs(of: output.id) == [selector.id, right.id], "the edge to left must be pruned")

        let before = counter.runs
        graph.setValue(99, for: left)           // no longer read
        #expect(!graph.isDirty(output.id))
        #expect(graph.value(of: output) == 22)
        #expect(counter.runs == before)
        graph.setValue(33, for: right)
        #expect(graph.value(of: output) == 33)
    }

    /// C5 / C17: inputs are kept sorted by ascending attribute index, regardless of read order.
    @Test func inputsAreKeptInAscendingAttributeIDOrder() {
        let graph = Graph()
        let a = graph.makeInput(1), b = graph.makeInput(2), c = graph.makeInput(3)
        let flip = graph.makeInput(false)
        let output = graph.makeRule { flip.value ? c.value + a.value : a.value + b.value + c.value }
        _ = graph.value(of: output)
        #expect(graph.inputs(of: output.id) == [a.id, b.id, c.id, flip.id])
        graph.setValue(true, for: flip)
        _ = graph.value(of: output)
        #expect(graph.inputs(of: output.id) == [a.id, c.id, flip.id])
    }

    /// C5 / C17: before running a dirty rule, all its dirty previous inputs are brought up to date in ascending
    /// attribute index order (no early exit on the first changed input).
    @Test func updateVerifiesAllDirtyPreviousInputsInAttributeIDOrderBeforeRunning() {
        final class Log { var events: [String] = [] }
        let log = Log()
        let graph = Graph()

        let in1 = graph.makeInput(1), in2 = graph.makeInput(2), in3 = graph.makeInput(3)
        let e1 = graph.makeRule { log.events.append("E1"); return in1.value }
        let e2 = graph.makeRule { log.events.append("E2"); return in2.value }
        let e3 = graph.makeRule { log.events.append("E3"); return in3.value }
        // Read in non-monotonic order: E2, E3, E1
        let r = graph.makeRule {
            log.events.append("R")
            return e2.value + e3.value + e1.value
        }
        _ = graph.value(of: r)
        #expect(log.events == ["R", "E2", "E3", "E1"])

        log.events.removeAll()
        graph.setValue(10, for: in1)
        graph.setValue(20, for: in2)
        graph.setValue(30, for: in3)
        #expect(graph.value(of: r) == 60)
        #expect(log.events == ["E1", "E2", "E3", "R"])

        // Selector + dirty old branch: even when `sel` (lower index) already changed, `branchA` is updated before `selRule` runs.
        log.events.removeAll()
        let sel = graph.makeInput(0)
        let rawA = graph.makeInput(1), rawB = graph.makeInput(2)
        let branchA = graph.makeRule { log.events.append("branchA"); return rawA.value * 10 }
        let branchB = graph.makeRule { log.events.append("branchB"); return rawB.value * 10 }
        let selectorRule = graph.makeRule {
            log.events.append("selectorRule")
            return sel.value == 0 ? branchA.value : branchB.value
        }
        #expect(graph.value(of: selectorRule) == 10)
        log.events.removeAll()
        graph.setValue(1, for: sel)
        graph.setValue(5, for: rawA)
        #expect(graph.value(of: selectorRule) == 20)
        #expect(log.events == ["branchA", "selectorRule", "branchB"])
    }

    /// E10: rules run from the top down, children in the order they were read.
    @Test func rulesRunInReadOrderFromTheTopDown() {
        final class Log { var entries: [String] = [] }
        let log = Log()
        let graph = Graph()
        let seed = graph.makeInput(0)
        // Data flows downwards: the parent's output feeds the middle rule, which feeds both leaves.
        let parent = graph.makeRule { log.entries.append("parent"); return seed.value }
        let middle = graph.makeRule { log.entries.append("middle"); return parent.value + 1 }
        let leafA = graph.makeRule { log.entries.append("a"); return middle.value + 1 }
        let leafB = graph.makeRule { log.entries.append("b"); return middle.value + 2 }

        _ = graph.value(of: leafA); _ = graph.value(of: leafB)   // first run: discovers the edges
        log.entries = []
        graph.setValue(1, for: seed)
        _ = graph.value(of: leafA); _ = graph.value(of: leafB)
        // On an update the dirty sources are brought up to date before the rules that read them start (E10).
        #expect(log.entries == ["parent", "middle", "a", "b"])
    }

    @Test func aChainIsUpdatedFromItsSources() {
        let graph = Graph()
        let a = graph.makeInput(1)
        let b = graph.makeRule { a.value + 1 }
        let c = graph.makeRule { b.value + 1 }
        #expect(graph.value(of: c) == 3)
        graph.setValue(10, for: a)
        #expect(graph.isDirty(b.id) && graph.isDirty(c.id))
        #expect(graph.value(of: c) == 12)
        #expect(!graph.isDirty(b.id) && !graph.isDirty(c.id))
    }

    @Test func twoRulesThatReadEachOtherStopTheProgram() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            final class Slot { var other: Attribute<Int>? }
            let slot = Slot()
            let a = graph.makeRule { (slot.other?.value ?? 0) + 1 }
            let b = graph.makeRule { a.value + 1 }
            slot.other = b
            _ = graph.value(of: a)
        }
    }

    @Test func aRuleThatWritesStopsTheProgram() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            let target = graph.makeInput(0)
            let output = graph.makeRule { graph.setValue(1, for: target); return 0 }
            _ = graph.value(of: output)
        }
    }

    @Test func writingToARuleStopsTheProgram() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            let rule = graph.makeRule { 1 }
            graph.setValue(2, for: rule)
        }
    }

    @Test func readingAnAttributeOutsideARuleWithTheImplicitSpellingStopsTheProgram() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            let a = graph.makeInput(1)
            _ = a.value
        }
    }

    // MARK: Subgraph invalidation seen from outside

    @Test func invalidatingASubgraphDirtiesTheDependentsOutsideIt() {
        let graph = Graph()
        let sub = graph.makeSubgraph()
        let use = graph.makeInput(true)
        let inside = graph.withCurrent(sub) { graph.makeInput(5) }
        let outside = graph.makeRule { use.value ? inside.value : 0 }
        let downstream = graph.makeRule { outside.value + 1 }
        #expect(graph.value(of: downstream) == 6)

        graph.invalidate(sub)
        #expect(graph.isDirty(outside.id))
        #expect(graph.isDirty(downstream.id), "descendants too, not only children")
        #expect(graph.inputs(of: outside.id) == [use.id], "the edge to the dead attribute is removed")

        graph.setValue(false, for: use)
        #expect(graph.value(of: downstream) == 1, "the rule no longer reads the dead attribute")
    }

    @Test func aRuleThatKeepsReadingAnInvalidatedAttributeStopsTheProgram() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            let sub = graph.makeSubgraph()
            let inside = graph.withCurrent(sub) { graph.makeInput(5) }
            let outside = graph.makeRule { inside.value }
            _ = graph.value(of: outside)
            graph.invalidate(sub)
            _ = graph.value(of: outside)
        }
    }

    @Test func invalidatingASubgraphLeavesOtherSubgraphsIntact() {
        let graph = Graph()
        let groups = (0..<200).map { _ in graph.makeSubgraph() }
        for group in groups {
            graph.withCurrent(group) {
                let a = graph.makeInput(1)
                _ = graph.makeRule { a.value + 1 }
            }
        }
        #expect(graph.nodeCount == 400)
        graph.invalidate(groups[0])
        #expect(graph.nodeCount == 398)
        for group in groups.dropFirst() { graph.invalidate(group) }
        #expect(graph.nodeCount == 0)
    }
}
