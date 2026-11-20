import Testing
@testable import SwiftAttributeGraph

/// `Graph.counter(for:)`: the selectors of `AGGraphGetCounter` that the engine reproduces. Every expected number was
/// measured on macOS 15.8.3 with the native `AGGraphGetCounter` in an isolated probe [O].
@Suite struct GraphCounterTests {
    private struct Snapshot: Equatable, CustomStringConvertible {
        var nodes, transactions, updates, changes, createdNodes, subgraphs, createdSubgraphs: UInt64
        var description: String {
            "N=\(nodes) T=\(transactions) U=\(updates) C=\(changes) CN=\(createdNodes) S=\(subgraphs) CS=\(createdSubgraphs)"
        }
    }

    private func snapshot(_ graph: Graph) -> Snapshot {
        Snapshot(nodes: graph.counter(for: .nodes), transactions: graph.counter(for: .transactions),
                 updates: graph.counter(for: .updates), changes: graph.counter(for: .changes),
                 createdNodes: graph.counter(for: .createdNodes), subgraphs: graph.counter(for: .subgraphs),
                 createdSubgraphs: graph.counter(for: .createdSubgraphs))
    }

    private func expect(_ graph: Graph, _ n: UInt64, _ t: UInt64, _ u: UInt64, _ c: UInt64, _ cn: UInt64,
                        _ s: UInt64, _ cs: UInt64, _ label: String = "") {
        let want = Snapshot(nodes: n, transactions: t, updates: u, changes: c, createdNodes: cn, subgraphs: s,
                            createdSubgraphs: cs)
        #expect(snapshot(graph) == want, "\(label)")
    }

    @Test func aFreshGraphHasEveryCounterAtZero() {
        let graph = Graph()
        expect(graph, 0, 0, 0, 0, 0, 0, 0, "fresh graph (the root subgraph is not counted)")
        _ = graph.makeSubgraph()
        expect(graph, 0, 0, 0, 0, 0, 1, 1, "one subgraph")
    }

    @Test func creatingNodesCountsNodesAndInputChangesButNotRules() {
        let graph = Graph()
        let sub = graph.makeSubgraph()
        let src = graph.withCurrent(sub) { graph.makeInput(Int64(1)) }
        for _ in 0..<4 { graph.withCurrent(sub) { _ = graph.makeInput(Int64(0)) } }
        _ = graph.withCurrent(sub) { graph.makeRule { graph.value(of: src) } }
        expect(graph, 6, 0, 0, 5, 6, 1, 1, "5 inputs + 1 rule")
    }

    @Test func theWholeNativeSequenceOfReadsWritesAndRules() {
        let graph = Graph()
        let sg = graph.makeSubgraph()
        expect(graph, 0, 0, 0, 0, 0, 1, 1, "0 start")
        let a = graph.withCurrent(sg) { graph.makeInput(Int64(1)) }
        expect(graph, 1, 0, 0, 1, 1, 1, 1, "1 input created")
        _ = graph.value(of: a)
        _ = graph.value(of: a)
        expect(graph, 1, 0, 0, 1, 1, 1, 1, "2-3 reading an input is not a transaction")
        graph.setValue(1, for: a)
        expect(graph, 1, 0, 0, 1, 1, 1, 1, "4 writing the same value changes nothing")
        graph.setValue(5, for: a)
        expect(graph, 1, 0, 0, 2, 1, 1, 1, "5 a different value is a change")
        graph.setValue(6, for: a)
        expect(graph, 1, 0, 0, 3, 1, 1, 1, "6")
        let b = graph.withCurrent(sg) { graph.makeRule { graph.value(of: a) + 1 } }
        let c = graph.withCurrent(sg) { graph.makeRule { graph.value(of: b) + 1 } }
        expect(graph, 3, 0, 0, 3, 3, 1, 1, "7 two rules created")
        _ = graph.value(of: c)
        expect(graph, 3, 1, 2, 5, 3, 1, 1, "8 first read of the chain: 1 transaction, 2 updates, 2 changes")
        _ = graph.value(of: c)
        expect(graph, 3, 2, 2, 5, 3, 1, 1, "9 a clean read is a transaction but not an update")
        _ = graph.value(of: c)
        expect(graph, 3, 3, 2, 5, 3, 1, 1, "10")
        graph.setValue(7, for: a)
        expect(graph, 3, 3, 2, 6, 3, 1, 1, "11 a write is a change, not a transaction")
        graph.setValue(8, for: a)
        expect(graph, 3, 3, 2, 7, 3, 1, 1, "12")
        _ = graph.value(of: c)
        expect(graph, 3, 4, 3, 9, 3, 1, 1, "13 re-evaluating the chain: 1 update, 2 changes")
        let d = graph.withCurrent(sg) { graph.makeRule { Int64(9) } }
        expect(graph, 4, 4, 3, 9, 4, 1, 1, "14")
        _ = graph.value(of: d)
        expect(graph, 4, 5, 4, 10, 4, 1, 1, "15")
        let x = graph.withCurrent(sg) { graph.makeInput(Int64(1)) }
        let y = graph.withCurrent(sg) { graph.makeRule { _ = graph.value(of: x); return Int64(0) } }
        _ = graph.value(of: y)
        expect(graph, 6, 6, 5, 12, 6, 1, 1, "16")
        graph.setValue(2, for: x)
        _ = graph.value(of: y)
        expect(graph, 6, 7, 6, 13, 6, 1, 1, "17 y gives the same value: a cut is not a change")
        graph.withoutUpdate { _ = graph.value(of: y) }
        expect(graph, 6, 8, 6, 13, 6, 1, 1, "18 a read under withoutUpdate is a transaction")
        let sg2 = graph.makeSubgraph()
        expect(graph, 6, 8, 6, 13, 6, 2, 2, "19 second subgraph")
        sg.addChild(sg2)
        sg2.invalidate()
        expect(graph, 6, 8, 6, 13, 6, 1, 2, "21 invalidated child: subgraphs falls, createdSubgraphs does not")
        sg.invalidate()
        expect(graph, 0, 8, 6, 13, 6, 0, 2, "22 invalidated parent frees the nodes")
    }

    /// Each node that has no value yet and is evaluated inside another update counts one more update; re-evaluating
    /// a whole chain is one update. Updates and changes after each of four reads, per chain length [O].
    @Test(arguments: [
        (1, [1, 2, 3, 3] as [UInt64], [2, 4, 6, 6] as [UInt64]),
        (2, [2, 3, 4, 5], [3, 6, 8, 9]),
        (4, [4, 5, 6, 7], [5, 10, 12, 15]),
    ])
    func aChainOfRulesCountsFirstEvaluationsNested(length: Int, updates: [UInt64], changes: [UInt64]) {
        let graph = Graph()
        let sg = graph.makeSubgraph()
        let a = graph.withCurrent(sg) { graph.makeInput(Int64(1)) }
        var chain: [Attribute<Int64>] = []
        var previous = a
        for _ in 0..<length {
            let p = previous
            chain.append(graph.withCurrent(sg) { graph.makeRule { graph.value(of: p) + 1 } })
            previous = chain.last!
        }
        let tail = previous
        var seen: [(UInt64, UInt64, UInt64)] = []
        func record() {
            seen.append((graph.counter(for: .transactions), graph.counter(for: .updates), graph.counter(for: .changes)))
        }
        _ = graph.value(of: tail); record()
        graph.setValue(5, for: a); _ = graph.value(of: tail); record()
        graph.setValue(6, for: a); _ = graph.value(of: chain[0]); record()
        _ = graph.value(of: tail); record()
        #expect(seen.map(\.0) == [1, 2, 3, 4])
        #expect(seen.map(\.1) == updates)
        #expect(seen.map(\.2) == changes)
    }

    @Test func aDiamondCountsOneUpdatePerFirstEvaluation() {
        let graph = Graph()
        let sg = graph.makeSubgraph()
        let a = graph.withCurrent(sg) { graph.makeInput(Int64(1)) }
        let b = graph.withCurrent(sg) { graph.makeRule { graph.value(of: a) } }
        let c = graph.withCurrent(sg) { graph.makeRule { graph.value(of: b) } }
        _ = graph.value(of: b)
        _ = graph.value(of: c)
        let d1 = graph.withCurrent(sg) { graph.makeRule { graph.value(of: a) } }
        let d2 = graph.withCurrent(sg) { graph.makeRule { graph.value(of: a) } }
        let top = graph.withCurrent(sg) { graph.makeRule { graph.value(of: d1) + graph.value(of: d2) } }
        _ = graph.value(of: top)
        #expect(graph.counter(for: .updates) == 5, "top + d1 + d2 first evaluations, after 2 for b and c")
        #expect(graph.counter(for: .transactions) == 3)
        graph.setValue(9, for: a)
        _ = graph.value(of: top)
        #expect(graph.counter(for: .updates) == 6)
        #expect(graph.counter(for: .changes) == 10)
    }

    @Test func aReadThroughAnIndirectAttributeOfARuleIsATransaction() {
        let graph = Graph()
        let sg = graph.makeSubgraph()
        let rule = graph.withCurrent(sg) { graph.makeRule { Int64(3) } }
        let indirect = graph.withCurrent(sg) { graph.makeIndirect(rule) }
        _ = graph.value(of: indirect)
        #expect(graph.counter(for: .transactions) == 1)
        #expect(graph.counter(for: .updates) == 1)
        _ = graph.value(of: indirect)
        #expect(graph.counter(for: .transactions) == 2)
        #expect(graph.counter(for: .updates) == 1)
    }

    @Test func anIndirectAttributeOverAnInputIsNotATransactionAndAWriteThroughItIsOneUpdate() {
        let graph = Graph()
        let sg = graph.makeSubgraph()
        let input = graph.withCurrent(sg) { graph.makeInput(Int64(1)) }
        let indirectInput = graph.withCurrent(sg) { graph.makeIndirect(input) }
        _ = graph.value(of: indirectInput)
        #expect(graph.counter(for: .transactions) == 0)
        let rule = graph.withCurrent(sg) { graph.makeRule { graph.value(of: input) } }
        let indirectRule = graph.withCurrent(sg) { graph.makeIndirect(rule) }
        _ = graph.value(of: indirectRule)
        graph.setValue(2, for: input)
        _ = graph.value(of: indirectRule)
        #expect(graph.counter(for: .transactions) == 2)
        #expect(graph.counter(for: .updates) == 2, "first evaluation, then one re-evaluation")
    }

    @Test func aTopLevelUpdateThatSkipsEveryRuleIsStillAnUpdate() {
        let graph = Graph()
        let sg = graph.makeSubgraph()
        let a = graph.withCurrent(sg) { graph.makeInput(Int64(1)) }
        let mid = graph.withCurrent(sg) { graph.makeRule { _ = graph.value(of: a); return Int64(0) } }
        let tail = graph.withCurrent(sg) { graph.makeRule { graph.value(of: mid) } }
        _ = graph.value(of: tail)
        #expect(graph.counter(for: .updates) == 2)
        graph.setValue(2, for: a)
        let changes = graph.counter(for: .changes)
        _ = graph.value(of: tail)
        #expect(graph.counter(for: .updates) == 3, "mid re-runs, gives the same value and tail is skipped")
        #expect(graph.counter(for: .changes) == changes, "no value changed during that update")
    }

    @Test func readsInsideARuleAreNotTransactions() {
        let graph = Graph()
        let sg = graph.makeSubgraph()
        let inner = graph.withCurrent(sg) { graph.makeRule { Int64(1) } }
        let outer = graph.withCurrent(sg) { graph.makeRule { graph.value(of: inner) + 1 } }
        _ = graph.value(of: outer)
        #expect(graph.counter(for: .transactions) == 1)
    }
}
