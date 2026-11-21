import Testing
@testable import SwiftAttributeGraph

/// Baseline for the hot read path before the shared-graph split (`docs/DISENO-GRAFO-COMPARTIDO.md` §5, phase 1). Run in
/// release, several times:
///
///     swift test -c release -Xswiftc -enable-testing --filter HotReadPerformance
///
/// Creation is outside the timed part: only warm reads are measured.
@Suite(.serialized) struct HotReadPerformanceTests {
    private static func median(runs: Int = 7, _ body: () -> Void) -> Double {
        var samples: [Double] = []
        let clock = ContinuousClock()
        for _ in 0..<runs {
            let elapsed = clock.measure(body)
            samples.append(Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15)
        }
        samples.sort()
        return samples[samples.count / 2]
    }

    @Test func tenMillionWarmInputReads() {
        let graph = Graph()
        let inputs = (0..<1_000).map { graph.makeInput($0) }
        var checksum = 0
        let ms = Self.median {
            for _ in 0..<10_000 { for input in inputs { checksum &+= graph.value(of: input) } }
        }
        print("PERF hot input reads: \(ms) ms for 10M reads (checksum \(checksum & 1))")
        #expect(ms < 5_000)
    }

    @Test func tenMillionWarmRuleReads() {
        let graph = Graph()
        let source = graph.makeInput(3)
        let rule = graph.makeRule { graph.value(of: source) + 1 }
        _ = graph.value(of: rule)
        var checksum = 0
        let ms = Self.median {
            for _ in 0..<10_000_000 { checksum &+= graph.value(of: rule) }
        }
        print("PERF hot rule reads: \(ms) ms for 10M reads (checksum \(checksum & 1))")
        #expect(ms < 5_000)
    }
}
