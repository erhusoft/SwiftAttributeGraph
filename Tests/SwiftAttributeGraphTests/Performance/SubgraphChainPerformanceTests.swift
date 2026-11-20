import Testing
@testable import SwiftAttributeGraph

/// `addChild` must not cost O(depth of the parent): a chain of N subgraphs links in O(N) total.
@Suite struct SubgraphChainPerformanceTests {
    private func buildChain(_ depth: Int) -> Double {
        let graph = Graph()
        var parent = graph.makeSubgraph(parent: graph.rootSubgraph)
        let duration = ContinuousClock().measure {
            for _ in 0..<depth {
                let child = graph.makeSubgraph(parent: graph.rootSubgraph)   // fresh, no children yet
                graph.addChild(child, to: parent)
                parent = child
            }
        }
        #expect(graph.liveSubgraphCount == depth + 2)
        return Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    @Test func linkingAChainOfSubgraphsWithAddChildIsLinearInTheDepth() {
        var times: [Int: Double] = [:]
        for depth in [1_000, 5_000, 20_000] {
            times[depth] = buildChain(depth)
            print("PERF addChild chain of \(depth): \(times[depth]!) ms")
        }
        #expect(times[20_000]! < 1_000, "20,000 addChild calls must take under 1 s (was O(depth) per call)")
    }
}
