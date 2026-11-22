import Testing
import Foundation
@testable import SwiftAttributeGraph

@Suite("MultiThreadContextPerformanceTests")
struct MultiThreadContextPerformanceTests {

    /// Measures the throughput of running 8 concurrent worker threads, each driving its own independent
    /// Graph instance through 100,000 evaluations (800,000 total evaluations in parallel).
    @Test func eightThreadsConcurrentIndependentGraphs() async {
        let threadCount = 8
        let evaluationsPerThread = 100_000

        let start = DispatchTime.now()

        await withTaskGroup(of: Void.self) { group in
            for threadIndex in 0..<threadCount {
                group.addTask {
                    let graph = Graph()
                    let input = graph.makeInput(threadIndex)
                    let rule = graph.makeRule { input.value * 3 + 1 }

                    for i in 0..<evaluationsPerThread {
                        graph.setValue(i, for: input)
                        _ = graph.value(of: rule)
                    }
                }
            }
        }

        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
        let totalEvaluations = threadCount * evaluationsPerThread
        let evalsPerSec = (Double(totalEvaluations) / (elapsed / 1000.0))
        print("PERF MultiThread: \(totalEvaluations) evaluations across \(threadCount) threads in \(String(format: "%.2f", elapsed)) ms (~\(String(format: "%.2f", evalsPerSec / 1_000_000.0)) M evals/sec)")

        #if !DEBUG
        #expect(elapsed < 200.0, "8 concurrent threads must finish 800k evaluations under 200 ms in Release")
        #endif
    }
}
