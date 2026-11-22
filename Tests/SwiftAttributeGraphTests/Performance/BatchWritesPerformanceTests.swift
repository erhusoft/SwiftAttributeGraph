import Testing
import Foundation
@testable import SwiftAttributeGraph

@Suite("BatchWritesPerformanceTests")
struct BatchWritesPerformanceTests {

    /// Measures the throughput of writing to 1,000 independent input nodes that fan in to 1,000 rules,
    /// repeating over 100 iterations (100,000 total writes).
    @Test func thousandInputsBatchWrites() {
        let graph = Graph()
        let count = 1_000
        let inputs = (0..<count).map { graph.makeInput($0) }
        let rules = (0..<count).map { i in
            graph.makeRule { inputs[i].value * 2 }
        }

        // Prime the graph (warm cache)
        for rule in rules {
            _ = graph.value(of: rule)
        }

        let iterations = 100
        let start = DispatchTime.now()

        for iter in 0..<iterations {
            for i in 0..<count {
                graph.setValue(iter * 1_000 + i, for: inputs[i])
            }
            // Evaluate only the first and last to ensure dirty propagation ran
            _ = graph.value(of: rules[0])
            _ = graph.value(of: rules[count - 1])
        }

        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
        print("PERF BatchWrites 1,000 inputs x \(iterations) cycles (\(count * iterations) writes): \(String(format: "%.2f", elapsed)) ms")

        #if !DEBUG
        #expect(elapsed < 600.0, "Batch writes of 100k inputs must complete under 600 ms in Release")
        #endif
    }

    /// Measures writing in batches under `withoutUpdate`, comparing propagation overhead.
    @Test func batchWritesInsideWithoutUpdate() {
        let graph = Graph()
        let count = 1_000
        let inputs = (0..<count).map { graph.makeInput($0) }
        let sumRule = graph.makeRule {
            var sum = 0
            for input in inputs {
                sum += input.value
            }
            return sum
        }

        _ = graph.value(of: sumRule)

        let iterations = 50
        let start = DispatchTime.now()

        for iter in 0..<iterations {
            Graph.withoutUpdate {
                for i in 0..<count {
                    graph.setValue(iter + i, for: inputs[i])
                }
            }
            _ = graph.value(of: sumRule)
        }

        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
        print("PERF BatchWrites withoutUpdate 1,000 inputs into 1 accumulator x \(iterations) cycles: \(String(format: "%.2f", elapsed)) ms")

        #if !DEBUG
        #expect(elapsed < 400.0, "Batch writes inside withoutUpdate must complete under 400 ms in Release")
        #endif
    }
}
