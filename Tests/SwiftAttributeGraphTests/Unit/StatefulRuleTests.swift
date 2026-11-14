import Testing
@testable import SwiftAttributeGraph

/// Rules with state (M3, `docs/DISENO-M3.md`): the previous value, the right not to change it, which inputs changed and
/// state of the rule's own.
@Suite struct StatefulRuleTests {
    private final class Counter { var runs = 0 }

    // MARK: The two acceptance tests of the plan

    private struct Sum: StatefulRule {
        let input: Attribute<Int>
        static var initialValue: Int? { 0 }
        mutating func updateValue(_ context: inout RuleContext<Int>) { context.value += input.value }
    }

    /// A rule that accumulates: it adds the input to its previous value each time it runs.
    @Test func aRuleThatAccumulatesSeesItsPreviousValue() {
        let graph = Graph()
        let input = graph.makeInput(0)
        let sum = graph.makeStatefulRule(Sum(input: input))
        #expect(graph.value(of: sum) == 0)
        graph.setValue(1, for: input)
        #expect(graph.value(of: sum) == 1)
        graph.setValue(2, for: input)
        #expect(graph.value(of: sum) == 3)
    }

    /// Two writes before a read run the rule once and it sees the last value: it does not see every write.
    @Test func twoWritesBeforeAReadRunTheRuleOnce() {
        let graph = Graph()
        let input = graph.makeInput(0)
        let sum = graph.makeStatefulRule(Sum(input: input))
        _ = graph.value(of: sum)
        graph.setValue(3, for: input)
        graph.setValue(4, for: input)
        #expect(graph.value(of: sum) == 4)
    }

    /// A rule that reads `a` and `b` but only reacts to `a`: when `b` changes it runs, keeps its value, and nothing
    /// that depends on it runs.
    @Test func aRuleThatOnlyReactsToOneOfItsInputs() {
        let graph = Graph()
        let a = graph.makeInput(0), b = graph.makeInput(0)
        let rule = Counter(), dependent = Counter()
        let reactions = graph.makeStatefulRule(initialValue: 0) { (context: inout RuleContext<Int>) in
            rule.runs += 1
            _ = a.value; _ = b.value
            if context.hasChanged(a) { context.value += 1 }
        }
        let downstream = graph.makeRule { dependent.runs += 1; return reactions.value * 10 }
        #expect(graph.value(of: downstream) == 10)               // first run: `a` counts as changed
        graph.setValue(5, for: b)
        let versionBefore = graph.version(of: reactions.id)
        #expect(graph.value(of: downstream) == 10)
        #expect((rule.runs, dependent.runs) == (2, 1))           // the rule ran because `b` changed; nothing downstream
        #expect(graph.version(of: reactions.id) == versionBefore)
        graph.setValue(5, for: a)
        #expect(graph.value(of: downstream) == 20)
        #expect((rule.runs, dependent.runs) == (3, 2))
    }

    // MARK: The first run and the initial value

    @Test func theInitialValueIsKeptWhenTheFirstRunDoesNotWrite() {
        let graph = Graph()
        let input = graph.makeInput(1)
        let rule = graph.makeStatefulRule(initialValue: 7) { (_: inout RuleContext<Int>) in _ = input.value }
        let created = graph.version(of: rule.id)
        #expect(graph.value(of: rule) == 7)
        #expect(graph.version(of: rule.id) == created)
    }

    @Test func hasValueIsFalseOnTheFirstRunWithoutAnInitialValue() {
        let graph = Graph()
        let seen = Seen()
        let withInitial = graph.makeStatefulRule(initialValue: 1) { (c: inout RuleContext<Int>) in seen.log.append(c.hasValue) }
        let without = graph.makeStatefulRule { (c: inout RuleContext<Int>) in seen.log.append(c.hasValue); c.value = 2 }
        _ = graph.value(of: withInitial); _ = graph.value(of: without)
        #expect(seen.log == [true, false])
    }
    private final class Seen { var log: [Bool] = [] }

    @Test func aFirstRunThatNeverSetsAValueStopsTheProgram() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            let rule = graph.makeStatefulRule { (_: inout RuleContext<Int>) in }
            _ = graph.value(of: rule)
        }
    }

    @Test func readingTheValueOfAFirstRunWithoutOneStopsTheProgram() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            let rule = graph.makeStatefulRule { (c: inout RuleContext<Int>) in c.value = c.value + 1 }
            _ = graph.value(of: rule)
        }
    }

    // MARK: Which inputs changed

    @Test func anyInputsChangedAndItsExclusions() {
        let graph = Graph()
        let a = graph.makeInput(0), b = graph.makeInput(0)
        let log = Seen()
        let rule = graph.makeStatefulRule(initialValue: 0) { (c: inout RuleContext<Int>) in
            _ = a.value; _ = b.value
            log.log += [c.anyInputsChanged(), c.anyInputsChanged(excluding: [a.erased]), c.anyInputsChanged(excluding: [b.erased])]
            c.value += 1
        }
        _ = graph.value(of: rule)                                // first run: every input is new
        #expect(log.log == [true, true, true])
        log.log = []
        graph.setValue(1, for: b)
        _ = graph.value(of: rule)
        #expect(log.log == [true, true, false])                  // only `b` changed
    }

    @Test func changedValueReportsANewInputAsChangedAndAnOldOneByItsVersion() {
        let graph = Graph()
        let flag = graph.makeInput(false), extra = graph.makeInput(0), tick = graph.makeInput(0)
        let log = Changes()
        let rule = graph.makeStatefulRule { (c: inout RuleContext<Int>) in
            _ = tick.value
            if flag.value { log.values.append(c.changedValue(of: extra).changed) }
            c.value = 0
        }
        _ = graph.value(of: rule)
        graph.setValue(true, for: flag)
        _ = graph.value(of: rule)                                // `extra` is read for the first time: changed
        graph.setValue(1, for: tick)
        _ = graph.value(of: rule)                                // `extra` did not change
        graph.setValue(9, for: extra)
        _ = graph.value(of: rule)                                // `extra` changed
        #expect(log.values == [true, false, true])
    }
    private final class Changes { var values: [Bool] = [] }

    @Test func hasChangedOfAnAttributeTheRuleNeverReadIsFalseAndDoesNotReadIt() {
        let graph = Graph()
        let a = graph.makeInput(0), other = graph.makeInput(0)
        let log = Seen()
        let rule = graph.makeStatefulRule { (c: inout RuleContext<Int>) in
            _ = a.value
            log.log.append(c.hasChanged(other))
            c.value = 0
        }
        _ = graph.value(of: rule)
        #expect(log.log == [false])
        #expect(graph.inputs(of: rule.id) == [a.id])             // asking did not make it a dependency
    }

    // MARK: Not writing means not changing

    @Test func aRuleThatDoesNotWriteKeepsItsVersionAndTheCutStopsTheDependents() {
        let graph = Graph()
        let input = graph.makeInput(0)
        let dependent = Counter()
        let rule = graph.makeStatefulRule(initialValue: 0) { (c: inout RuleContext<Int>) in
            if input.value % 2 == 0 { c.value = input.value }    // odd values leave it alone
        }
        let downstream = graph.makeRule { dependent.runs += 1; return rule.value }
        _ = graph.value(of: downstream)
        let version = graph.version(of: rule.id)
        graph.setValue(3, for: input)
        _ = graph.value(of: downstream)
        #expect(graph.version(of: rule.id) == version)
        #expect(dependent.runs == 1)
        graph.setValue(4, for: input)
        #expect(graph.value(of: downstream) == 4)
        #expect(dependent.runs == 2)
    }

    @Test func theWrittenValuePassesThroughTheComparisonPolicy() {
        for (policy, expectedChange) in [(Comparison.stateWrite, false), (.viewValue, true)] {
            let graph = Graph()
            let input = graph.makeInput(0.0)
            let rule = graph.makeStatefulRule(initialValue: 0.0, comparison: policy) { (c: inout RuleContext<Double>) in
                c.value = input.value == 0 ? 0.0 : -0.0
            }
            _ = graph.value(of: rule)
            let version = graph.version(of: rule.id)
            graph.setValue(1, for: input)
            _ = graph.value(of: rule)
            #expect((graph.version(of: rule.id) != version) == expectedChange, "\(policy)")
        }
    }

    // MARK: The rule's own state

    private struct RunCounter: StatefulRule {
        let input: Attribute<Int>
        var runs = 0
        mutating func updateValue(_ context: inout RuleContext<Int>) { _ = input.value; runs += 1; context.value = runs }
    }

    @Test func aRuleKeepsItsOwnStateBetweenRuns() {
        let graph = Graph()
        let input = graph.makeInput(0)
        let rule = graph.makeStatefulRule(RunCounter(input: input))
        #expect(graph.value(of: rule) == 1)
        graph.setValue(1, for: input)
        #expect(graph.value(of: rule) == 2)
        graph.setValue(2, for: input)
        #expect(graph.value(of: rule) == 3)
    }

    /// An earlier input changed and a later one is dirty but ends up unchanged: the rule must still run. (The update
    /// loop leaves the frame to bring the later input up to date and must remember what it already found.)
    @Test func aChangeInAnEarlierInputIsNotForgottenWhileALaterInputIsBroughtUpToDate() {
        let graph = Graph()
        let a = graph.makeInput(0), b = graph.makeInput(0)
        let parity = graph.makeRule { b.value % 2 }
        let runs = Counter()
        let rule = graph.makeStatefulRule(initialValue: 0) { (c: inout RuleContext<Int>) in
            runs.runs += 1
            c.value = a.value * 10 + parity.value
        }
        #expect(graph.value(of: rule) == 0)
        graph.setValue(1, for: a)
        graph.setValue(2, for: b)                                // `parity` is dirty and will still be 0
        #expect(graph.value(of: rule) == 10)
        #expect(runs.runs == 2)
    }

    // MARK: Depth, life

    /// Each rule reads the root first (which changes) and then the previous rule. Stopping at the first changed
    /// input would run the rule and read the previous one from inside it, 20,000 levels deep on the native stack.
    @Test func aChainOfTwentyThousandStatefulRulesIsUpdatedWithoutRecursion() {
        let graph = Graph()
        let root = graph.makeInput(0)
        var chain: [Attribute<Int>] = []
        var previous = root
        for _ in 0..<20_000 {
            let before = previous
            let rule = graph.makeStatefulRule { (c: inout RuleContext<Int>) in
                let r = root.value
                let p = before.value
                if c.anyInputsChanged() { c.value = r &+ p &+ 1 }
            }
            chain.append(rule)
            previous = rule
        }
        for rule in chain { _ = graph.value(of: rule) }          // warm the chain one node at a time (the M4 limit)
        graph.setValue(1, for: root)
        // rule k: r + previous + 1, with previous(0) = root = 1 now: rule 1 = 3, rule 2 = 5, ...
        #expect(graph.value(of: chain[chain.count - 1]) == 2 * 20_000 + 1)
    }

    private final class Tracker { nonisolated(unsafe) static var alive = 0; init() { Self.alive += 1 }; deinit { Self.alive -= 1 } }
    private struct Holding: StatefulRule {
        let tracker = Tracker()
        mutating func updateValue(_ context: inout RuleContext<Int>) { context.value = 1 }
    }

    @Test func theStateOfARuleIsReleasedWithItsSubgraph() {
        let graph = Graph()
        let base = graph.nodeCount
        let before = Tracker.alive
        for _ in 0..<50 {
            let sub = graph.makeSubgraph()
            graph.withCurrent(sub) { _ = graph.value(of: graph.makeStatefulRule(Holding())) }
            #expect(Tracker.alive == before + 1)
            graph.invalidate(sub)
            #expect(Tracker.alive == before)
        }
        #expect(graph.nodeCount == base)
    }

    @Test func aStatefulRuleCannotWriteTheGraph() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            let input = graph.makeInput(0)
            let rule = graph.makeStatefulRule { (c: inout RuleContext<Int>) in graph.setValue(1, for: input); c.value = 0 }
            _ = graph.value(of: rule)
        }
    }
}
