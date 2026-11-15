import Testing
@testable import SwiftAttributeGraph

/// The measured behaviour of SwiftUI (macOS 15.7.9) expressed as engine behaviour. Here a "view body" is a rule that
/// reads the attribute holding the *value of the view*; the child's body must run exactly when SwiftUI runs it.
///
/// Rows already covered elsewhere, for reference:
/// E4, E14, E15 and the long-`String` case of E16 are in `ValueTests`; E5, E6 and R3-6 (invalidation goes to the
/// readers, never the owner) are in `PropagationTests`; E9 is in `ObservationTests`; E10 is in `RuleTests`;
/// E11 is the sibling-isolation test of `PropagationTests` (a rule that read `a` is not touched by a write to `b`).
@Suite struct ParityTests {
    private final class Counter { var runs = 0 }

    /// A child view value that carries a closure, as the E2 and E18 probes did.
    private struct ChildValue { let label: String; let action: () -> Void }

    /// E1: the parent re-evaluates; the child whose value did not change is skipped; the one that changed runs.
    @Test func aChildWhoseValueDidNotChangeIsSkippedWhenTheParentReevaluates() {
        let graph = Graph()
        let state = graph.makeInput(0)
        let dependsRuns = Counter(), staticRuns = Counter()
        // The parent produces one value per child, each a rule of the parent's state.
        let childValueA = graph.makeRule { state.value }                    // carries n
        let childValueB = graph.makeRule { "x" }                            // constant label
        let childA = graph.makeRule { dependsRuns.runs += 1; return childValueA.value }
        let childB = graph.makeRule { staticRuns.runs += 1; return childValueB.value }
        _ = graph.value(of: childA); _ = graph.value(of: childB)

        graph.setValue(1, for: state)
        _ = graph.value(of: childA); _ = graph.value(of: childB)
        #expect((dependsRuns.runs, staticRuns.runs) == (2, 1))
    }

    /// E2: a closure without captures has the same bits every time, so the child is skipped.
    @Test func aClosureWithoutCapturesDoesNotChangeTheViewValue() {
        let graph = Graph()
        let tick = graph.makeInput(0)
        let childRuns = Counter()
        let value = graph.makeRule { _ = tick.value; return ChildValue(label: "c", action: { }) }
        let child = graph.makeRule { childRuns.runs += 1; return value.value.label }
        _ = graph.value(of: child)
        graph.setValue(1, for: tick)
        _ = graph.value(of: child)
        #expect(childRuns.runs == 1)
    }

    /// E18: a closure that captures a value that changes does change the bits, so the child runs.
    @Test func aClosureThatCapturesAChangingValueChangesTheViewValue() {
        let graph = Graph()
        let tick = graph.makeInput(0)
        let childRuns = Counter()
        let value = graph.makeRule { () -> ChildValue in
            let captured = tick.value
            return ChildValue(label: "c", action: { print(captured) })
        }
        let child = graph.makeRule { childRuns.runs += 1; return value.value.label }
        _ = graph.value(of: child)
        graph.setValue(1, for: tick)
        _ = graph.value(of: child)
        #expect(childRuns.runs == 2)
    }

    /// E3 / E16, steady state: an array rebuilt on every evaluation with the same content is skipped (`Array` is
    /// `Equatable` and the property of a view uses `==` for such a field), and so is the same stored array. Round 1
    /// measured "a rebuilt array runs" in a fresh process (the cold state, `docs/DISENO-M2.md` §0); `.bits` keeps that.
    @Test func anArrayRebuiltWithTheSameContentIsSkippedUnderTheDefaultPolicy() {
        #expect(arrayRuns(comparison: .viewValue) == (1, 1))
    }

    @Test func anArrayRebuiltOnEveryEvaluationRunsTheChildUnderBitsAndAStoredOneDoesNot() {
        #expect(arrayRuns(comparison: .bits) == (2, 1))
    }

    private func arrayRuns(comparison: Comparison) -> (Int, Int) {
        let graph = Graph()
        let tick = graph.makeInput(0)
        let stored = [Int](repeating: 7, count: 16)
        let rebuiltRuns = Counter(), storedRuns = Counter()
        let rebuilt = graph.makeRule({ _ = tick.value; return [Int](repeating: 7, count: 16) }, comparison: comparison)
        let keeps = graph.makeRule({ _ = tick.value; return stored }, comparison: comparison)
        let childRebuilt = graph.makeRule { rebuiltRuns.runs += 1; return rebuilt.value.count }
        let childStored = graph.makeRule { storedRuns.runs += 1; return keeps.value.count }
        _ = graph.value(of: childRebuilt); _ = graph.value(of: childStored)
        graph.setValue(1, for: tick)
        _ = graph.value(of: childRebuilt); _ = graph.value(of: childStored)
        return (rebuiltRuns.runs, storedRuns.runs)
    }

    /// E7: leaving a branch destroys its state; coming back starts from the initial value and the old state is gone.
    @Test func switchingBranchDestroysTheStateAndComingBackStartsFromScratch() {
        let graph = Graph()
        var branchA = graph.makeSubgraph()
        var stateA = graph.withCurrent(branchA) { graph.makeInput(0) }
        graph.setValue(5, for: stateA)                      // a tap in branch A
        #expect(graph.value(of: stateA) == 5)

        graph.invalidate(branchA)                           // switch to B: A disappears
        let oldID = stateA.id
        branchA = graph.makeSubgraph()                      // back to A: new subgraph, new state
        stateA = graph.withCurrent(branchA) { graph.makeInput(0) }
        #expect(graph.value(of: stateA) == 0)
        #expect(!graph.contains(oldID) || oldID != stateA.id)
    }

    /// E8 / E19: with one subgraph per element id, reordering the list creates and runs nothing.
    @Test func reorderingElementsKeyedBySubgraphDoesNotRunTheirRules() {
        let graph = Graph()
        let runs = Counter()
        var rows: [Int: Attribute<Int>] = [:]
        for id in 1...3 {
            let subgraph = graph.makeSubgraph()
            rows[id] = graph.withCurrent(subgraph) {
                let state = graph.makeInput(id)
                return graph.makeRule { runs.runs += 1; return state.value }
            }
        }
        for id in 1...3 { _ = graph.value(of: rows[id]!) }
        runs.runs = 0
        for id in [3, 1, 2] { _ = graph.value(of: rows[id]!) }   // "reordered": the same attributes, read again
        #expect(runs.runs == 0)
    }

    /// R3-1: the state of a view is part of its value. A fresh random initial value changes the bits of the view
    /// value on every evaluation; a constant one does not.
    @Test func aStateInsideTheViewValueChangesItsBitsOnlyWhenItsInitialValueChanges() {
        struct ViewWithState { let id: Int; let initialState: Int }
        let graph = Graph()
        let tick = graph.makeInput(0)
        let constantRuns = Counter(), randomRuns = Counter()
        let constant = graph.makeRule { _ = tick.value; return ViewWithState(id: 1, initialState: 0) }
        let random = graph.makeRule { _ = tick.value; return ViewWithState(id: 1, initialState: Int.random(in: 0..<1_000_000_000)) }
        let childConstant = graph.makeRule { constantRuns.runs += 1; return constant.value.id }
        let childRandom = graph.makeRule { randomRuns.runs += 1; return random.value.id }
        _ = graph.value(of: childConstant); _ = graph.value(of: childRandom)
        graph.setValue(1, for: tick)
        _ = graph.value(of: childConstant); _ = graph.value(of: childRandom)
        #expect((constantRuns.runs, randomRuns.runs) == (1, 2))
    }

    @Test func branchSwitchAndInvalidateBeforeReadWorksInEitherOrder() {
        func runOrder(switchFirst: Bool) -> (Int, Int, Int, Int, Int) {
            let graph = Graph()
            let subA = graph.makeSubgraph()
            let aRuns = Counter(), bRuns = Counter(), outRuns = Counter()
            let inputA = graph.withCurrent(subA) { graph.makeInput(10) }
            let branchA = graph.withCurrent(subA) {
                graph.makeRule { aRuns.runs += 1; return inputA.value + 1 }
            }
            let inputB = graph.makeInput(200)
            let branchB = graph.makeRule { bRuns.runs += 1; return inputB.value + 2 }
            let useB = graph.makeInput(false)
            let out = graph.makeRule {
                outRuns.runs += 1
                return useB.value ? branchB.value : branchA.value
            }

            let v1 = graph.value(of: out)
            if switchFirst {
                graph.setValue(true, for: useB)
                graph.invalidate(subA)
            } else {
                graph.invalidate(subA)
                graph.setValue(true, for: useB)
            }
            let v2 = graph.value(of: out)
            return (v1, v2, aRuns.runs, bRuns.runs, outRuns.runs)
        }

        #expect(runOrder(switchFirst: true) == (11, 202, 1, 1, 2))
        #expect(runOrder(switchFirst: false) == (11, 202, 1, 1, 2))
    }

    @Test func indirectSurvivesDeathOfOriginalSourceWhileRedirected() {
        let graph = Graph()
        let subA = graph.makeSubgraph()
        let srcA = graph.withCurrent(subA) { graph.makeInput(10) }
        let srcB = graph.makeInput(200)
        let ind = graph.makeIndirect(srcA)
        let readerRuns = Counter()
        let reader = graph.makeRule { readerRuns.runs += 1; return ind.value + 1 }

        let v1 = graph.value(of: reader)
        graph.setSource(srcB, for: ind)
        let v2 = graph.value(of: reader)
        graph.invalidate(subA)
        let v3 = graph.value(of: reader)
        graph.setValue(205, for: srcB)
        let v4 = graph.value(of: reader)

        #expect([v1, v2, v3, v4] == [11, 201, 201, 206])
        #expect(readerRuns.runs == 3)
    }

    @Test func statefulRulePrunesOldDependencyEvenWhenNoNewValueIsWritten() {
        let graph = Graph()
        let a = graph.makeInput(10)
        let b = graph.makeInput(20)
        let useB = graph.makeInput(false)
        let runs = Counter()

        struct PruneWithoutWriteRule: StatefulRule {
            typealias Value = Int
            let a: Attribute<Int>
            let b: Attribute<Int>
            let useB: Attribute<Bool>
            let runs: Counter

            mutating func updateValue(_ context: inout RuleContext<Int>) {
                runs.runs += 1
                if useB.value {
                    _ = b.value
                    // Preserve previous value (100) without assigning `context.value`.
                } else {
                    _ = a.value
                    context.value = 100
                }
            }
        }

        let rule = graph.makeStatefulRule(
            PruneWithoutWriteRule(a: a, b: b, useB: useB, runs: runs)
        )

        #expect(graph.value(of: rule) == 100 && runs.runs == 1)
        graph.setValue(true, for: useB)
        #expect(graph.value(of: rule) == 100 && runs.runs == 2)
        graph.setValue(999, for: a)
        #expect(graph.value(of: rule) == 100 && runs.runs == 2)
        graph.setValue(222, for: b)
        #expect(graph.value(of: rule) == 100 && runs.runs == 3)
    }

    @Test func initialValueRuleWithoutFirstWriteHasValueFalseBeforeEvaluationAndCutsDownstream() {
        struct InitialNoFirstWriteRule: StatefulRule {
            static var initialValue: Int? { 77 }
            typealias Value = Int
            let input: Attribute<Int>
            let runs: Counter

            mutating func updateValue(_ context: inout RuleContext<Int>) {
                runs.runs += 1
                let x = input.value
                if x != 10 && x != 15 {
                    context.value = x * 2
                }
            }
        }

        let graph = Graph()
        let input = graph.makeInput(10)
        let rRuns = Counter(), downRuns = Counter()
        let rule = graph.makeStatefulRule(InitialNoFirstWriteRule(input: input, runs: rRuns))
        let down = graph.makeRule { downRuns.runs += 1; return rule.value + 1 }

        #expect(!graph.hasValue(of: rule))
        #expect(graph.value(of: down) == 78)
        #expect(graph.hasValue(of: rule))
        #expect((rRuns.runs, downRuns.runs) == (1, 1))

        graph.setValue(15, for: input)
        #expect(graph.value(of: down) == 78)
        #expect((rRuns.runs, downRuns.runs) == (2, 1))

        graph.setValue(20, for: input)
        #expect(graph.value(of: down) == 41)
        #expect((rRuns.runs, downRuns.runs) == (3, 2))
    }

    @Test func nestedWithoutUpdateAndWithoutSubgraphInvalidationRestoreContext() {
        let graph = Graph()
        let a = graph.makeInput(1), b = graph.makeInput(100), c = graph.makeInput(1000)
        let runs = Counter()
        let out = graph.makeRule {
            runs.runs += 1
            let va = a.value
            let vb = graph.withoutUpdate {
                graph.withoutUpdate { b.value }
            }
            let vc = c.value
            return va + vb + vc
        }

        #expect(graph.value(of: out) == 1101 && runs.runs == 1)
        graph.setValue(200, for: b)
        #expect(graph.value(of: out) == 1101 && runs.runs == 1)
        graph.setValue(2000, for: c)
        #expect(graph.value(of: out) == 2201 && runs.runs == 2)

        let sub1 = graph.makeSubgraph()
        let sub2 = graph.makeSubgraph()
        let x1 = graph.withCurrent(sub1) { graph.makeInput(11) }
        let x2 = graph.withCurrent(sub2) { graph.makeInput(22) }
        let w1 = WeakAttribute(x1), w2 = WeakAttribute(x2)
        var between: [Int?] = []

        graph.withoutSubgraphInvalidation {
            graph.invalidate(sub1)
            graph.withoutSubgraphInvalidation {
                graph.invalidate(sub2)
            }
            between = [graph.value(of: w1), graph.value(of: w2)]
        }

        #expect(between == [11, 22])
        #expect(graph.value(of: w1) == nil && graph.value(of: w2) == nil)
    }

    @Test func reentrantSubgraphInvalidationInObserverRunsSeriallyWithoutDuplicates() {
        final class TrackedDeinit {
            let name: String
            let log: (String) -> Void
            init(_ name: String, log: @escaping (String) -> Void) { self.name = name; self.log = log }
            deinit { log("deinit(\(name))") }
        }

        let graph = Graph()
        var events: [String] = []
        let sub1 = graph.makeSubgraph()
        let sub2 = graph.makeSubgraph()
        let sub3 = graph.makeSubgraph()

        func makeTracked(_ name: String, in sub: Subgraph, value: Int) -> Attribute<Int> {
            let obj = TrackedDeinit(name) { events.append($0) }
            return graph.withCurrent(sub) { graph.makeRule { _ = obj; return value } }
        }

        let r1 = makeTracked("obj1", in: sub1, value: 1)
        let r2 = makeTracked("obj2", in: sub2, value: 2)
        let r3 = makeTracked("obj3", in: sub3, value: 3)
        _ = (graph.value(of: r1), graph.value(of: r2), graph.value(of: r3))

        let t1 = graph.observe(sub1) {
            events.append("notice1-start")
            graph.invalidate(sub2)
            events.append("notice1-end")
        }
        let t2 = graph.observe(sub2) {
            events.append("notice2-start")
            graph.invalidate(sub3)
            events.append("notice2-end")
        }
        let t3 = graph.observe(sub3) {
            events.append("notice3")
        }
        _ = (t1, t2, t3)

        graph.invalidate(sub1)
        #expect(!graph.isValid(sub1) && !graph.isValid(sub2) && !graph.isValid(sub3))
        #expect(graph.nodeCount == 0)
        #expect(events == [
            "notice1-start", "notice1-end", "deinit(obj1)",
            "notice2-start", "notice2-end", "deinit(obj2)",
            "notice3", "deinit(obj3)",
        ])
    }

    @Test func weakAttributeNeverResurrectsAcrossTwoThousandSubgraphReuseCycles() {
        let graph = Graph()
        let sub0 = graph.makeSubgraph()
        let a0 = graph.withCurrent(sub0) { graph.makeInput(999) }
        let w0 = WeakAttribute(a0)
        var staleWeaks = [w0]
        graph.invalidate(sub0)

        for i in 0..<2_000 {
            let sub = graph.makeSubgraph()
            let (x, r) = graph.withCurrent(sub) {
                let x = graph.makeInput(i)
                let r = graph.makeRule { x.value + 1 }
                return (x, r)
            }
            _ = graph.value(of: r)
            if i % 20 == 0 {
                staleWeaks.append(WeakAttribute(x))
            }
            graph.invalidate(sub)
            #expect(graph.value(of: w0) == nil)
        }

        #expect(staleWeaks.allSatisfy { graph.value(of: $0) == nil })
        #expect(graph.nodeCount == 0)
        #expect(graph.liveSubgraphCount == 1)
    }

    private struct ClosureStateful<Value>: StatefulRule {
        let body: (inout RuleContext<Value>) -> Void
        mutating func updateValue(_ context: inout RuleContext<Value>) { body(&context) }
    }

    @Test func resetSourceRevertsToInitialAfterMultipleRedirects() {
        let graph = Graph()
        let a = graph.makeInput(10)
        let b = graph.makeInput(20)
        let c = graph.makeInput(30)
        let ind = graph.makeIndirect(a)
        var runs = 0
        let reader = graph.makeRule { runs += 1; return ind.value + 1 }

        #expect(graph.value(of: reader) == 11)
        graph.setSource(b, for: ind)
        #expect(graph.value(of: reader) == 21)
        graph.setSource(c, for: ind)
        #expect(graph.value(of: reader) == 31)
        graph.resetSource(for: ind)
        #expect(graph.value(of: reader) == 11)
        graph.setValue(15, for: a)
        #expect(graph.value(of: reader) == 16)
        #expect(runs == 5)
    }

    @Test func indirectChainAndIntermediateSubgraphDeath() {
        let graph = Graph()
        let a = graph.makeInput(10)
        let aSame = graph.makeInput(10)
        let b = graph.makeInput(20)
        let child = graph.makeSubgraph()
        let c = graph.withCurrent(child) { graph.makeInput(30) }

        var dep1Runs = 0
        let dep1 = graph.makeRule { dep1Runs += 1; return a.value * 10 }
        var dep2Runs = 0
        let dep2 = graph.makeRule { dep2Runs += 1; return b.value * 100 }

        let ind1 = graph.makeIndirect(a)
        graph.setDependency(dep1.erased, for: ind1)
        let ind2 = graph.makeIndirect(ind1)
        graph.setDependency(dep2.erased, for: ind2)

        var readerRuns = 0
        let reader = graph.makeRule { readerRuns += 1; return ind2.value + 1 }

        #expect(graph.value(of: reader) == 11)
        #expect(readerRuns == 1)
        graph.setSource(aSame, for: ind1)
        #expect(graph.value(of: reader) == 11)
        #expect(readerRuns == 2)
        graph.setSource(c, for: ind1)
        #expect(graph.value(of: reader) == 31)
        #expect(readerRuns == 3)
        graph.invalidate(child)
        #expect(graph.value(of: reader) == 31)
        #expect(readerRuns == 3 && dep1Runs == 1 && dep2Runs == 1)
    }

    @Test func changedValueReportsChangedAfterSkippedReadsAndSameValueRedirect() {
        let graph = Graph()
        let flag = graph.makeInput(true)
        let x = graph.makeInput(10)
        let y = graph.makeInput(99)
        var changedLog: [(Int, Bool)] = []
        let sr = graph.makeStatefulRule(ClosureStateful<Int> { ctx in
            if flag.value {
                let cv = ctx.changedValue(of: x)
                changedLog.append(cv)
                ctx.value = cv.value
            } else {
                ctx.value = ctx.changedValue(of: y).value
            }
        })
        #expect(graph.value(of: sr) == 10)
        graph.setValue(false, for: flag)
        #expect(graph.value(of: sr) == 99)
        graph.setValue(50, for: x)
        graph.setValue(10, for: x)
        graph.setValue(true, for: flag)
        #expect(graph.value(of: sr) == 10)
        #expect(changedLog.map { "\($0.0):\($0.1)" } == ["10:true", "10:true"])

        let s1 = graph.makeInput(50)
        let s2 = graph.makeInput(50)
        let ind = graph.makeIndirect(s1)
        let tick = graph.makeInput(0)
        var indLog: [(Int, Bool)] = []
        let srInd = graph.makeStatefulRule(ClosureStateful<Int> { ctx in
            _ = tick.value
            let cv = ctx.changedValue(of: ind)
            indLog.append(cv)
            ctx.value = cv.value + tick.value
        })
        #expect(graph.value(of: srInd) == 50)
        graph.setSource(s2, for: ind)
        #expect(graph.value(of: srInd) == 50)
        graph.setValue(1, for: tick)
        #expect(graph.value(of: srInd) == 51)
        #expect(indLog.map { "\($0.0):\($0.1)" } == ["50:true", "50:true", "50:false"])
    }

    @Test func multiObserverTreeNotifiesParentsFirstReverseChildrenAndSnapshotsPerSubgraph() {
        let graph = Graph()
        var events: [String] = []
        let parent = graph.makeSubgraph()
        let child1 = graph.makeSubgraph(parent: parent)
        let grand1 = graph.makeSubgraph(parent: child1)
        let child2 = graph.makeSubgraph(parent: parent)

        var c1Obs2: SubgraphObservationToken?
        var c2Obs2: SubgraphObservationToken?
        let c1Obs1 = graph.observe(child1) {
            events.append("child1-obs1")
            c1Obs2?.cancel()
        }
        c1Obs2 = graph.observe(child1) { events.append("child1-obs2") }
        let g1Obs1 = graph.observe(grand1) { events.append("grand1-obs1") }
        let c2Obs1 = graph.observe(child2) { events.append("child2-obs1") }
        c2Obs2 = graph.observe(child2) { events.append("child2-obs2") }
        let pObs1 = graph.observe(parent) {
            events.append("parent-obs1")
            c2Obs2?.cancel()
        }
        let pObs2 = graph.observe(parent) { events.append("parent-obs2") }
        _ = (c1Obs1, c1Obs2, g1Obs1, c2Obs1, c2Obs2, pObs1, pObs2)

        graph.invalidate(parent)
        #expect(events == ["parent-obs1", "parent-obs2", "child2-obs1", "child1-obs1", "child1-obs2", "grand1-obs1"])
    }
}
