import Testing
import Foundation
@testable import SwiftAttributeGraph

@Suite("DynamicEdgePruningPerformanceTests")
struct DynamicEdgePruningPerformanceTests {

    /// Measures the performance of 1,000 rules dynamically switching between two sets of 5 inputs,
    /// forcing the engine to detach 5 old input edges and record 5 new input edges on every cycle
    /// across 50 complete toggle rounds (500,000 edge updates).
    @Test func alternatingEdgePruningAndReattachment() {
        let graph = Graph()
        let count = 1_000
        let branchSelector = graph.makeInput(false)

        let branchA = (0..<5).map { i in (0..<count).map { j in graph.makeInput(i * 10_000 + j) } }
        let branchB = (0..<5).map { i in (0..<count).map { j in graph.makeInput(i * 20_000 + j) } }

        let rules = (0..<count).map { i in
            graph.makeRule {
                let useB = branchSelector.value
                var sum = 0
                for k in 0..<5 {
                    sum += useB ? branchB[k][i].value : branchA[k][i].value
                }
                return sum
            }
        }

        // Prime the graph on branch A
        for rule in rules {
            _ = graph.value(of: rule)
        }

        let rounds = 50
        let start = DispatchTime.now()

        for round in 0..<rounds {
            graph.setValue((round % 2 == 0), for: branchSelector)
            for i in 0..<count {
                _ = graph.value(of: rules[i])
            }
        }

        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
        let totalRuleRuns = count * rounds
        let totalEdgeModifications = totalRuleRuns * 5
        let microsPerEdge = (elapsed / Double(totalEdgeModifications)) * 1000.0
        print("PERF DynamicEdgePruning: \(totalEdgeModifications) edge prune/inserts across \(totalRuleRuns) rule updates in \(String(format: "%.2f", elapsed)) ms (~\(String(format: "%.2f", microsPerEdge)) µs/edge)")

        #if !DEBUG
        #expect(elapsed < 200.0, "500k dynamic edge updates must complete under 200 ms in Release")
        #endif
    }
}
