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
                parent.addChild(child)
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

    private func invalidateSiblings(_ count: Int) -> Double {
        let graph = Graph()
        let parent = graph.makeSubgraph(parent: graph.rootSubgraph)
        var children: [Subgraph] = []
        children.reserveCapacity(count)
        for i in 0..<count {
            let child = graph.makeSubgraph(parent: parent)
            graph.withCurrent(child) {
                _ = graph.makeInput(i)
            }
            children.append(child)
        }
        let duration = ContinuousClock().measure {
            for child in children {
                child.invalidate()
            }
        }
        #expect(graph.nodeCount == 0 && graph.liveSubgraphCount == 2)
        return Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    @Test func invalidatingTwentyThousandSiblingSubgraphsIsLinearAndPreservesChildOrder() {
        // 1. Verify that invalidating a middle sibling preserves reverse-creation order of remaining siblings
        // for `forEach`, `update(flags:)`, `children(of:)`, and parent invalidation observer notices.
        let graph = Graph()
        let parent = graph.makeSubgraph(parent: graph.rootSubgraph)
        let c1 = graph.makeSubgraph(parent: parent)
        let c2 = graph.makeSubgraph(parent: parent)
        let c3 = graph.makeSubgraph(parent: parent)
        let c4 = graph.makeSubgraph(parent: parent)
        let flag = AttributeFlags(rawValue: 1)
        let a1 = graph.withCurrent(c1) { let r = graph.makeRule { 1 }; graph.setFlags(flag, for: r); return r }
        _ = graph.withCurrent(c2) { let r = graph.makeRule { 2 }; graph.setFlags(flag, for: r); return r }
        let a3 = graph.withCurrent(c3) { let r = graph.makeRule { 3 }; graph.setFlags(flag, for: r); return r }
        let a4 = graph.withCurrent(c4) { let r = graph.makeRule { 4 }; graph.setFlags(flag, for: r); return r }

        // Invalidate the middle child c2; remaining children must stay in creation order [c1, c3, c4],
        // visited in reverse creation order [c4, c3, c1] by `forEach` and by `observe` when `parent` is invalidated.
        c2.invalidate()
        #expect(graph.children(of: parent) == [c1, c3, c4])
        var visited: [AttributeID] = []
        graph.forEach(in: parent, flags: flag) { visited.append($0.id) }
        #expect(visited == [a4.id, a3.id, a1.id])

        var notices: [String] = []
        graph.observe(parent) { notices.append("parent") }
        graph.observe(c1) { notices.append("c1") }
        graph.observe(c3) { notices.append("c3") }
        graph.observe(c4) { notices.append("c4") }
        parent.invalidate()
        #expect(notices == ["parent", "c4", "c3", "c1"])

        // 2. Cost scaling across 1,000, 5,000, and 20,000 siblings must be linear, not O(N^2) (~297 ms in release before fix).
        var times: [Int: Double] = [:]
        for count in [1_000, 5_000, 20_000] {
            times[count] = invalidateSiblings(count)
            print("PERF invalidate \(count) siblings: \(times[count]!) ms")
        }
        #expect(times[20_000]! < 50.0, "20,000 sibling invalidations in release must finish under 50 ms (was ~297 ms O(N^2))")
    }
}
