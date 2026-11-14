import Testing
@testable import SwiftAttributeGraph

@Suite struct IndirectPerformanceTests {
    @Test func readAndWriteThroughTwentyThousandRedirects() {
        let graph = Graph()
        let source = graph.makeInput(0)
        var last = source
        for _ in 0..<20_000 { last = graph.makeIndirect(last) }
        var samples: [Double] = []
        for value in 1...7 {
            let duration = ContinuousClock().measure {
                graph.setValue(value, for: last)
                _ = graph.value(of: last)
            }
            #expect(graph.value(of: source) == value)
            samples.append(Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15)
        }
        print("PERF 20,000 indirects, write + read: \(samples.sorted()[3]) ms")
    }
}
