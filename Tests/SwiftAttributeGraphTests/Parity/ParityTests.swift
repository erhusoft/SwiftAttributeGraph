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
}
