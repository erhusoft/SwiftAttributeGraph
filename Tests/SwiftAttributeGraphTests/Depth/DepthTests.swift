import Testing
@testable import SwiftAttributeGraph

/// Every traversal uses an explicit stack, so depth must not matter (principle 1). Each traversal that exists has a
/// test of at least 20,000 levels.
///
/// Documented limit (removed by M4): the *first* run of a never-evaluated rule that reads another never-evaluated
/// rule nests on the native stack, because the engine cannot know the inputs it has not read yet. The chains below
/// are therefore warmed up node by node, which is also what a UI does while it builds a tree.
@Suite struct DepthTests {
    private let depth = 20_000

    private func warmChain(of graph: Graph, root: Attribute<Int>) -> [Attribute<Int>] {
        var chain: [Attribute<Int>] = [root]
        for _ in 1..<depth {
            let previous = chain[chain.count - 1]
            let next = graph.makeRule { previous.value + 1 }
            _ = graph.value(of: next)               // first run is shallow: the previous node is already computed
            chain.append(next)
        }
        return chain
    }

    @Test func aWriteAtTheRootOfAChainOfTwentyThousandRulesPropagatesAndUpdates() {
        let graph = Graph()
        let root = graph.makeInput(0)
        let chain = warmChain(of: graph, root: root)
        let last = chain[chain.count - 1]
        #expect(graph.value(of: last) == depth - 1)

        graph.setValue(100, for: root)               // dirty propagation: iterative
        #expect(graph.isDirty(last.id))
        #expect(graph.value(of: last) == 100 + depth - 1)   // update: explicit stack
        #expect(!graph.isDirty(last.id))
    }

    @Test func aChainThatCutsInTheMiddleRunsNothingBeyondTheCut() {
        final class Runs { var count = 0 }
        let runs = Runs()
        let graph = Graph()
        let root = graph.makeInput(0)
        let parity = graph.makeRule { root.value % 2 }
        var previous = parity
        for _ in 0..<depth {
            let source = previous
            previous = graph.makeRule { runs.count += 1; return source.value + 1 }
            _ = graph.value(of: previous)
        }
        let last = previous
        runs.count = 0
        graph.setValue(2, for: root)                 // parity stays 0
        #expect(graph.value(of: last) == depth)
        #expect(runs.count == 0, "the cut by version stops the update after the first rule")
    }

    @Test func twentyThousandReadersOfOneInputAreDirtiedAndUpdated() {
        let graph = Graph()
        let input = graph.makeInput(1)
        let readers = (0..<depth).map { _ in graph.makeRule { input.value + 1 } }
        for reader in readers { _ = graph.value(of: reader) }
        graph.setValue(2, for: input)
        for reader in readers { #expect(graph.isDirty(reader.id)) }
        #expect(graph.value(of: readers[depth - 1]) == 3)
    }

    @Test func aRuleWithTwentyThousandInputsKeepsThemInReadOrder() {
        let graph = Graph()
        let inputs = (0..<depth).map { graph.makeInput($0) }
        let sum = graph.makeRule { inputs.reduce(0) { $0 + $1.value } }
        #expect(graph.value(of: sum) == depth * (depth - 1) / 2)
        #expect(graph.inputs(of: sum.id) == inputs.map(\.id))
        graph.setValue(1_000_000, for: inputs[depth / 2])
        #expect(graph.value(of: sum) == depth * (depth - 1) / 2 - depth / 2 + 1_000_000)
    }

    @Test func invalidatingASubgraphOfTwentyThousandRulesIsIterative() {
        let graph = Graph()
        let sub = graph.makeSubgraph()
        graph.withCurrent(sub) {
            let root = graph.makeInput(0)
            _ = warmChain(of: graph, root: root)
        }
        #expect(graph.nodeCount == depth)
        graph.invalidate(sub)
        #expect(graph.nodeCount == 0)
    }

    @Test func aDeepChainOutsideASubgraphThatReadsIntoItDetachesIteratively() {
        let graph = Graph()
        let sub = graph.makeSubgraph()
        let inside = graph.withCurrent(sub) { graph.makeInput(1) }
        let first = graph.makeRule { inside.value }
        _ = graph.value(of: first)
        var previous = first
        for _ in 1..<depth {
            let source = previous
            previous = graph.makeRule { source.value }
            _ = graph.value(of: previous)
        }
        graph.invalidate(sub)
        #expect(graph.inputs(of: first.id).isEmpty && !graph.isDirty(previous.id))
    }

    // MARK: M5: the subgraph tree

    @Test func aTreeOfTwentyThousandNestedSubgraphsIsInvalidatedWithoutRecursion() {
        let graph = Graph()
        var current = graph.makeSubgraph()
        let top = current
        var last = current
        for i in 0..<20_000 {
            graph.withCurrent(current) { _ = graph.makeInput(i) }
            last = graph.makeSubgraph(parent: current)
            current = last
        }
        #expect(graph.nodeCount == 20_000 && graph.liveSubgraphCount == 20_002)
        graph.invalidate(top)
        #expect(graph.nodeCount == 0 && graph.liveSubgraphCount == 1)
        #expect(!graph.isLive(last))
    }

    @Test func twentyThousandSiblingSubgraphsAreInvalidatedTogether() {
        let graph = Graph()
        let parent = graph.makeSubgraph()
        for i in 0..<20_000 { graph.withCurrent(graph.makeSubgraph(parent: parent)) { _ = graph.makeInput(i) } }
        graph.invalidate(parent)
        #expect(graph.nodeCount == 0 && graph.liveSubgraphCount == 1)
    }

    @Test func aDeepNestedTreeInvalidatedFromInsideARuleIsFreedWithoutRecursion() {
        let graph = Graph()
        let top = graph.makeSubgraph()
        var current = top
        for _ in 0..<20_000 { current = graph.makeSubgraph(parent: current) }
        let rule = graph.makeRule { () -> Int in graph.invalidate(top); return 1 }
        _ = graph.value(of: rule)
        #expect(graph.liveSubgraphCount == 1)
    }
}
