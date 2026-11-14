import Testing
@testable import SwiftAttributeGraph

/// Version cuts and fast verification shortcuts (M1): rules returning the same value,
/// transitively skipping all downstream dependents, and global epoch versioning.
@Suite struct VersionCutTests {
    private final class Counter { var runs = 0 }

    @Test func globalVersionBumpsOnlyWhenAValueActuallyChanges() {
        let graph = Graph()
        let initialGlobal = graph.globalVersion

        let input = graph.makeInput(10)
        #expect(graph.globalVersion == initialGlobal)

        // Writing the same value should not bump the global version
        graph.setValue(10, for: input)
        #expect(graph.globalVersion == initialGlobal)

        // Writing a different value bumps global version
        graph.setValue(20, for: input)
        #expect(graph.globalVersion == initialGlobal + 1)

        // A rule that computes a new value
        let doubled = graph.makeRule { input.value * 2 }
        _ = graph.value(of: doubled)
        let afterFirstRun = graph.globalVersion

        // Changing input changes rule output, bumping global version twice (input + rule)
        graph.setValue(30, for: input)
        let afterWrite = graph.globalVersion
        #expect(afterWrite == afterFirstRun + 1)

        _ = graph.value(of: doubled)
        #expect(graph.globalVersion == afterWrite + 1)
    }

    @Test func aRuleComputingTheSameValueDoesNotBumpGlobalVersionOrRunDependentsInALinearChain() {
        let graph = Graph()
        let input = graph.makeInput(10)
        let intermediateRuns = Counter()
        let downstreamRuns = Counter()
        let leafRuns = Counter()

        // Intermediate divides by 10 (10/10 == 1, 19/10 == 1)
        let intermediate = graph.makeRule {
            intermediateRuns.runs += 1
            return input.value / 10
        }
        let downstream = graph.makeRule {
            downstreamRuns.runs += 1
            return intermediate.value + 100
        }
        let leaf = graph.makeRule {
            leafRuns.runs += 1
            return downstream.value * 2
        }

        #expect(graph.value(of: leaf) == 202)
        #expect((intermediateRuns.runs, downstreamRuns.runs, leafRuns.runs) == (1, 1, 1))

        let globalBefore = graph.globalVersion
        // Write 19: intermediate recalculates (19/10 == 1), same value!
        graph.setValue(19, for: input)
        #expect(graph.globalVersion == globalBefore + 1) // only input changed

        let leafVal = graph.value(of: leaf)
        #expect(leafVal == 202)
        #expect(intermediateRuns.runs == 2, "intermediate had to run to compute 19/10")
        #expect(downstreamRuns.runs == 1, "downstream must be cut because intermediate value did not change")
        #expect(leafRuns.runs == 1, "leaf must be cut because intermediate value did not change")
    }

    @Test func diamondGraphCutsDownstreamWhenBothBranchesRecomputeToSameValue() {
        let graph = Graph()
        let input = graph.makeInput(4)
        let leftRuns = Counter()
        let rightRuns = Counter()
        let bottomRuns = Counter()

        // Left: even or odd (4 % 2 == 0)
        let left = graph.makeRule {
            leftRuns.runs += 1
            return input.value % 2
        }
        // Right: absolute sign/parity
        let right = graph.makeRule {
            rightRuns.runs += 1
            return (input.value * 2) % 2
        }
        let bottom = graph.makeRule {
            bottomRuns.runs += 1
            return left.value + right.value
        }

        #expect(graph.value(of: bottom) == 0)
        #expect((leftRuns.runs, rightRuns.runs, bottomRuns.runs) == (1, 1, 1))

        // Change input to 6: both left and right will recompute, but both yield 0
        graph.setValue(6, for: input)
        #expect(graph.value(of: bottom) == 0)
        #expect(leftRuns.runs == 2)
        #expect(rightRuns.runs == 2)
        #expect(bottomRuns.runs == 1, "bottom rule must not run when both inputs cut")
    }

    @Test func aFanoutOfFiftyDependentsIsSkippedWhenSharedRuleValueDoesNotChange() {
        let graph = Graph()
        let input = graph.makeInput(100)
        let rootRuns = Counter()
        let rootRule = graph.makeRule {
            rootRuns.runs += 1
            return input.value / 100 // 100 / 100 = 1, 150 / 100 = 1
        }

        var leafCounters: [Counter] = []
        var leaves: [Attribute<Int>] = []
        for i in 0..<50 {
            let c = Counter()
            leafCounters.append(c)
            leaves.append(graph.makeRule {
                c.runs += 1
                return rootRule.value + i
            })
        }

        for (i, leaf) in leaves.enumerated() {
            #expect(graph.value(of: leaf) == 1 + i)
        }
        #expect(rootRuns.runs == 1)
        for c in leafCounters { #expect(c.runs == 1) }

        // Change input such that rootRule produces 1 again
        graph.setValue(150, for: input)
        for (i, leaf) in leaves.enumerated() {
            #expect(graph.value(of: leaf) == 1 + i)
        }
        #expect(rootRuns.runs == 2, "rootRule had to evaluate 150 / 100")
        for c in leafCounters {
            #expect(c.runs == 1, "none of the 50 leaves should have recomputed")
        }
    }

    @Test func statefulRuleLeavingValueUnchangedCutsDownstreamExecution() {
        let graph = Graph()
        let input = graph.makeInput(1)
        let statefulRuns = Counter()
        let downstreamRuns = Counter()

        // Stateful rule ignores even values
        let stateful = graph.makeStatefulRule(initialValue: 0) { (ctx: inout RuleContext<Int>) in
            statefulRuns.runs += 1
            let inVal = input.value
            if inVal % 2 != 0 {
                ctx.value = inVal
            }
            // If even, do not set ctx.value: keeps old value
        }

        let downstream = graph.makeRule {
            downstreamRuns.runs += 1
            return stateful.value * 10
        }

        #expect(graph.value(of: downstream) == 10)
        #expect((statefulRuns.runs, downstreamRuns.runs) == (1, 1))

        // Write 2 (even): stateful rule runs but does not change its value
        graph.setValue(2, for: input)
        #expect(graph.value(of: downstream) == 10)
        #expect(statefulRuns.runs == 2)
        #expect(downstreamRuns.runs == 1, "downstream must cut when stateful rule leaves value untouched")
    }

    @Test func resumableRuleLeavingValueUnchangedCutsDownstreamExecution() {
        struct ThresholdRule: ResumableRule {
            typealias Value = Int
            static var initialValue: Int? { 0 }

            let input: Attribute<Int>

            mutating func resume(_ context: inout ResumableRuleContext<Int>) -> RuleStep {
                guard case .ready(let v) = context.poll(input) else {
                    return .needsInput(input.erased)
                }
                if v > 100 {
                    context.value = v
                }
                // If <= 100, do not write context.value: preserves initial/previous 0
                return .finished
            }
        }

        let graph = Graph()
        let input = graph.makeInput(10)
        let leafRuns = Counter()

        let threshold = graph.makeResumableRule(ThresholdRule(input: input))
        let leaf = graph.makeRule {
            leafRuns.runs += 1
            return threshold.value + 5
        }

        #expect(graph.value(of: leaf) == 5)
        #expect(leafRuns.runs == 1)

        // Write 20: still <= 100, threshold rule runs but value stays 0
        graph.setValue(20, for: input)
        #expect(graph.value(of: leaf) == 5)
        #expect(leafRuns.runs == 1, "leaf must cut when resumable rule does not change value")
    }
}
