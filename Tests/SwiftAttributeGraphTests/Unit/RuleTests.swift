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

    /// Native parity (`NativeProbe` scenarios `in-rule-invalidate-*`): Apple traps with "setting value during update".
    @Test func aRuleThatInvalidatesAValueStopsTheProgram() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            let input = graph.makeInput(1)
            let target = graph.makeRule { input.value + 1 }
            _ = graph.value(of: target)
            let output = graph.makeRule { graph.invalidateValue(of: target); return 0 }
            _ = graph.value(of: output)
        }
    }

    /// Native parity (`NativeProbe` scenario `in-rule-invalidate-inside-without-update`): inside `withoutUpdate` no rule
    /// is tracking reads, and Apple accepts the invalidation; the target runs again on its next read.
    @Test func aRuleMayInvalidateAValueInsideWithoutUpdate() {
        let graph = Graph()
        let input = graph.makeInput(1)
        let trigger = graph.makeInput(false)
        var salt = 10
        let counter = Counter()
        let salted = graph.makeRule { () -> Int in
            counter.runs += 1
            return input.value + salt
        }
        let writer = graph.makeRule { () -> Int in
            if trigger.value {
                salt = 50
                graph.withoutUpdate { graph.invalidateValue(of: salted) }
            }
            return 0
        }
        #expect(graph.value(of: salted) == 11)
        #expect(graph.value(of: writer) == 0)
        graph.setValue(true, for: trigger)
        #expect(graph.value(of: writer) == 0)
        #expect(graph.value(of: salted) == 51)
        #expect(counter.runs == 2)
    }

    @Test func writingToARuleStopsTheProgram() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            let rule = graph.makeRule { 1 }
            graph.setValue(2, for: rule)
        }
    }

    /// Native AttributeGraph reads it (oracle scenario `hueco-b2`); the old expectation of a crash was wrong.
    @Test func readingAnAttributeOutsideARuleWithTheImplicitSpellingReturnsItsValue() {
        let graph = Graph()
        let a = graph.makeInput(1)
        #expect(a.value == 1)
    }

    // MARK: Subgraph invalidation seen from outside

    @Test func invalidatingASubgraphDetachesEdgesToDependentsOutsideIt() {
        let graph = Graph()
        let sub = graph.makeSubgraph()
        let use = graph.makeInput(true)
        let inside = graph.withCurrent(sub) { graph.makeInput(5) }
        let outside = graph.makeRule { use.value ? inside.value : 0 }
        let downstream = graph.makeRule { outside.value + 1 }
        #expect(graph.value(of: downstream) == 6)

        sub.invalidate()
        #expect(!graph.isDirty(outside.id))
        #expect(!graph.isDirty(downstream.id))
        #expect(graph.inputs(of: outside.id) == [use.id], "the edge to the dead attribute is removed")

        graph.setValue(false, for: use)
        #expect(graph.value(of: downstream) == 1, "the rule no longer reads the dead attribute")
    }

    @Test func aRuleThatKeepsReadingAnInvalidatedAttributeStopsTheProgram() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            let sub = graph.makeSubgraph()
            let trigger = graph.makeInput(0)
            let inside = graph.withCurrent(sub) { graph.makeInput(5) }
            let outside = graph.makeRule { _ = trigger.value; return inside.value }
            _ = graph.value(of: outside)
            sub.invalidate()
            graph.setValue(1, for: trigger)
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
        (groups[0]).invalidate()
        #expect(graph.nodeCount == 398)
        for group in groups.dropFirst() { group.invalidate() }
        #expect(graph.nodeCount == 0)
    }

    // MARK: C25 — withoutUpdate

    @Test func withoutUpdateEvaluatesDirtyAttributeWithoutRecordingADependencyEdge() {
        let graph = Graph()
        let tracked = graph.makeInput(10)
        let rawUntracked = graph.makeInput(5)
        let untrackedCounter = Counter()
        let untracked = graph.makeRule {
            untrackedCounter.runs += 1
            return rawUntracked.value * 2
        }
        let outerCounter = Counter()
        let outer = graph.makeRule {
            outerCounter.runs += 1
            let a = tracked.value
            let b = Graph.withoutUpdate { untracked.value }
            return a + b
        }

        #expect(graph.value(of: outer) == 20)
        #expect(outerCounter.runs == 1)
        #expect(untrackedCounter.runs == 1)
        #expect(graph.inputs(of: outer.id) == [tracked.id])

        // Changing `rawUntracked` dirties `untracked`, NOT `outer`.
        graph.setValue(7, for: rawUntracked)
        #expect(graph.isDirty(untracked.id))
        #expect(!graph.isDirty(outer.id))
        #expect(graph.value(of: outer) == 20)
        #expect(outerCounter.runs == 1)

        // Changing `tracked` runs `outer`, which pulls the updated `untracked` via `withoutUpdate`.
        graph.setValue(20, for: tracked)
        #expect(graph.value(of: outer) == 34)
        #expect(outerCounter.runs == 2)
        #expect(untrackedCounter.runs == 2)
        #expect(graph.inputs(of: outer.id) == [tracked.id])
    }

    // MARK: C26 — mutateBody and invalidateValue

    private struct ScaledRule: Rule {
        var source: Attribute<Int>
        var factor: Int
        var value: Int { source.value * factor }
    }

    private struct ScaledStatefulRule: StatefulRule {
        typealias Value = Int
        static var initialValue: Int { 0 }
        var source: Attribute<Int>
        var bonus: Int
        mutating func updateValue(_ context: inout RuleContext<Int>) {
            context.value = source.value + bonus
        }
    }

    @Test func mutateBodyUpdatesRuleInPlaceAndOptionallyInvalidatesValue() {
        let graph = Graph()
        let input = graph.makeInput(3)
        let scaled = graph.makeRule(ScaledRule(source: input, factor: 10))
        let downCounter = Counter()
        let down = graph.makeRule {
            downCounter.runs += 1
            return scaled.value + 1
        }
        #expect(graph.value(of: down) == 31)
        #expect(downCounter.runs == 1)

        // Mutating without invalidating leaves `scaled` and `down` clean until `input` changes.
        graph.mutateBody(of: scaled, as: ScaledRule.self, invalidating: false) { $0.factor = 20 }
        #expect(!graph.isDirty(scaled.id))
        #expect(!graph.isDirty(down.id))
        #expect(graph.value(of: down) == 31)
        #expect(downCounter.runs == 1)

        graph.setValue(4, for: input)
        #expect(graph.value(of: down) == 81)
        #expect(downCounter.runs == 2)

        // Mutating with `invalidating: true` marks `scaled` dirty+pending and `down` dirty immediately.
        graph.mutateBody(of: scaled, as: ScaledRule.self, invalidating: true) { $0.factor = 30 }
        #expect(graph.isDirty(scaled.id))
        #expect(graph.isDirty(down.id))
        #expect(graph.value(of: down) == 121)
        #expect(downCounter.runs == 3)

        // Works for `StatefulRule` as well.
        let stateful = graph.makeStatefulRule(ScaledStatefulRule(source: input, bonus: 5))
        #expect(graph.value(of: stateful) == 9)
        graph.mutateBody(of: stateful, as: ScaledStatefulRule.self, invalidating: true) { $0.bonus = 50 }
        #expect(graph.isDirty(stateful.id))
        #expect(graph.value(of: stateful) == 54)
    }

    /// Native parity (`NativeProbe` scenario `in-rule-mutate-body-invalidating-input`): a rule that mutates, with
    /// invalidation, the body of a rule it has just read stays dirty after its run and runs again on the next read.
    @Test func mutateBodyInvalidatingInsideARuleKeepsTheRunningReaderDirty() {
        let graph = Graph()
        let input = graph.makeInput(3)
        let scaled = graph.makeRule(ScaledRule(source: input, factor: 10))
        let counter = Counter()
        var armed = true
        let reader = graph.makeRule { () -> Int in
            counter.runs += 1
            let value = scaled.value
            if armed {
                armed = false
                graph.mutateBody(of: scaled, as: ScaledRule.self, invalidating: true) { $0.factor = 20 }
            }
            return value
        }

        #expect(graph.value(of: reader) == 30)
        #expect(graph.isDirty(reader.id))
        #expect(graph.value(of: reader) == 60)
        #expect(graph.value(of: reader) == 60)
        #expect(graph.value(of: scaled) == 60)
        #expect(counter.runs == 2)
    }

    /// Native parity (`NativeProbe` scenario `in-rule-mutate-body-from-child-during-verification`): a reader that is on
    /// the update stack (verifying its inputs, not running) when one of its already verified inputs has its body
    /// mutated with invalidation keeps that update's value, stays dirty and runs on the next read.
    @Test func mutateBodyInvalidatingFromAChildKeepsTheStackedParentDirty() {
        let graph = Graph()
        let input = graph.makeInput(3)
        let trigger = graph.makeInput(0)
        let scaled = graph.makeRule(ScaledRule(source: input, factor: 10))
        let parentCounter = Counter(), childCounter = Counter()
        var armed = true
        let child = graph.makeRule { () -> Int in
            childCounter.runs += 1
            if trigger.value == 1 && armed {
                armed = false
                graph.mutateBody(of: scaled, as: ScaledRule.self, invalidating: true) { $0.factor = 20 }
            }
            return 0
        }
        let parent = graph.makeRule { () -> Int in
            parentCounter.runs += 1
            return scaled.value + child.value
        }

        #expect(graph.value(of: parent) == 30)
        graph.setValue(1, for: trigger)
        #expect(graph.value(of: parent) == 30)
        #expect((parentCounter.runs, childCounter.runs) == (1, 2))
        #expect(graph.isDirty(parent.id))
        #expect(graph.value(of: parent) == 60)
        #expect((parentCounter.runs, childCounter.runs) == (2, 2))
        #expect(graph.value(of: scaled) == 60)
        #expect(graph.value(of: parent) == 60)
        #expect(parentCounter.runs == 2)
    }

    @Test func invalidateValueForcesRuleRecalculationEvenWhenInputsDidNotChange() {
        let graph = Graph()
        let input = graph.makeInput(10)
        var externalSalt = 1
        let ruleCounter = Counter()
        let rule = graph.makeRule {
            ruleCounter.runs += 1
            return input.value + externalSalt
        }
        let downCounter = Counter()
        let down = graph.makeRule {
            downCounter.runs += 1
            return rule.value * 2
        }
        #expect(graph.value(of: down) == 22)
        #expect((ruleCounter.runs, downCounter.runs) == (1, 1))

        externalSalt = 5
        graph.invalidateValue(of: rule)
        #expect(graph.isDirty(rule.id) && graph.isDirty(down.id))
        #expect(graph.value(of: down) == 30)
        #expect((ruleCounter.runs, downCounter.runs) == (2, 2))
    }

    // MARK: C29 — hasValue, updateValue, validate

    @Test func hasValueValidateAndUpdateValueMatchNativeAttributeGraphSemantics() {
        let graph = Graph()
        let input = graph.makeInput(10)
        let ind = graph.makeIndirect(input)
        let innerCounter = Counter()
        let inner = graph.makeRule {
            innerCounter.runs += 1
            return input.value * 3
        }

        // Inputs and indirects start with `hasValue == true`; cold rules start with `hasValue == false`.
        #expect(graph.hasValue(of: input))
        #expect(graph.hasValue(of: ind))
        #expect(!graph.hasValue(of: inner))

        // `validate` on a cold rule (`hasValue == false`) does nothing.
        graph.validate(inner)
        #expect(innerCounter.runs == 0)
        #expect(!graph.hasValue(of: inner))

        // `updateValue` brings a cold or dirty rule up to date without recording a dependency on a running outer rule.
        let outerCounter = Counter()
        let outer = graph.makeRule {
            outerCounter.runs += 1
            graph.updateValue(of: inner)
            return input.value + 1
        }
        #expect(graph.value(of: outer) == 11)
        #expect(outerCounter.runs == 1)
        #expect(innerCounter.runs == 1)
        #expect(graph.hasValue(of: inner))
        #expect(graph.inputs(of: outer.id) == [input.id])

        // `validate` checks liveness without evaluating a dirty or warm rule; `updateValue` brings it up to date.
        graph.setValue(20, for: input)
        #expect(graph.isDirty(inner.id))
        graph.validate(inner)
        #expect(graph.isDirty(inner.id))
        #expect(innerCounter.runs == 1)
        graph.updateValue(of: inner)
        #expect(!graph.isDirty(inner.id))
        #expect(innerCounter.runs == 2)
        #expect(graph.value(of: inner) == 60)
        #expect(innerCounter.runs == 2)
    }
}
