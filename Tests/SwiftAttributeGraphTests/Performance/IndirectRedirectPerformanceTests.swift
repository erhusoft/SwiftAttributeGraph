import Testing
import Foundation
@testable import SwiftAttributeGraph

@Suite("IndirectRedirectPerformanceTests")
struct IndirectRedirectPerformanceTests {

    /// Measures the throughput of redirecting 10,000 indirect attributes repeatedly between distinct sources,
    /// verifying dirty propagation and edge detachment cost.
    @Test func redirectTenThousandIndirectAttributes() {
        let graph = Graph()
        let count = 10_000

        let sourcesA = (0..<count).map { graph.makeInput($0) }
        let sourcesB = (0..<count).map { graph.makeInput($0 + 1_000_000) }

        // Create indirect attributes pointing initially to sourcesA
        let indirects = (0..<count).map { i in
            graph.makeIndirect(sourcesA[i])
        }

        // Downstream rules reading the indirects
        let readers = (0..<count).map { i in
            graph.makeRule { indirects[i].value * 2 }
        }

        // Warm up readers
        for reader in readers {
            _ = graph.value(of: reader)
        }

        let rounds = 10
        let start = DispatchTime.now()

        for round in 0..<rounds {
            let targetSources = (round % 2 == 0) ? sourcesB : sourcesA
            for i in 0..<count {
                graph.setSource(targetSources[i], for: indirects[i])
            }

            // Verify a subset to pull values and ensure propagation happened
            _ = graph.value(of: readers[0])
            _ = graph.value(of: readers[count / 2])
            _ = graph.value(of: readers[count - 1])
        }

        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
        let totalRedirects = count * rounds
        let microsPerRedirect = (elapsed / Double(totalRedirects)) * 1000.0
        print("PERF IndirectRedirects: \(totalRedirects) redirects across \(count) indirect attributes in \(String(format: "%.2f", elapsed)) ms (~\(String(format: "%.2f", microsPerRedirect)) µs/redirect)")

        #if !DEBUG
        #expect(elapsed < 200.0, "100k indirect redirects must complete under 200 ms in Release")
        #endif
    }
}
