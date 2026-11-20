import Testing
@testable import SwiftAttributeGraph

/// `recordRead` when the new source sorts before the reader's existing edges (insertion in the middle of the list).
@Suite struct RecordReadInsertionTests {
    /// Builds `low` (small slot index) plus a reader that already has edges to two higher-index sources.
    private func makeFixture(stateful: Bool) -> (graph: Graph, low: Attribute<Int>, high: [Attribute<Int>],
                                                 reader: Attribute<Int>, runs: Counter) {
        let graph = Graph()
        let low = graph.makeInput(1)
        let high = [graph.makeInput(10), graph.makeInput(20)]
        let runs = Counter()
        let reader: Attribute<Int>
        if stateful {
            reader = graph.makeStatefulRule(initialValue: 0) { (context: inout RuleContext<Int>) in
                runs.value += 1
                context.value = high[0].value + high[1].value
            }
        } else {
            reader = graph.makeRule {
                runs.value += 1
                return high[0].value + high[1].value
            }
        }
        _ = graph.value(of: reader)
        return (graph, low, high, reader, runs)
    }

    private final class Counter: @unchecked Sendable { var value = 0 }

    private func edge(_ graph: Graph, reader: Attribute<Int>, source: Attribute<Int>) -> InputEdge? {
        graph.table.inputs[Int(reader.id.index)].first { $0.source == source.id.index }
    }

    @Test(arguments: [false, true])
    func outOfRuleInsertionBeforeHigherEdgesRegistersTheReader(stateful: Bool) {
        let f = makeFixture(stateful: stateful)
        #expect(f.low.id.index < f.high[0].id.index)
        let v = f.graph.inputValue(of: f.low, for: f.reader.erased)
        #expect(v == 1)
        #expect(f.graph.table.outputs[Int(f.low.id.index)] == [f.reader.id.index])
        let e = edge(f.graph, reader: f.reader, source: f.low)
        #expect(e?.keepForNextPrune == true)
        #expect(e?.changed == true)
        let sources = f.graph.table.inputs[Int(f.reader.id.index)].map(\.source)
        #expect(sources == sources.sorted())
        // positionInOutputs must point at the reader.
        let p = Int(e?.positionInOutputs ?? Graph.noNode)
        #expect(f.graph.table.outputs[Int(f.low.id.index)][p] == f.reader.id.index)
    }

    @Test(arguments: [false, true])
    func insertedEdgeSurvivesOneEvaluationBeforeBeingPruned(stateful: Bool) {
        let f = makeFixture(stateful: stateful)
        _ = f.graph.inputValue(of: f.low, for: f.reader.erased)
        f.graph.setValue(2, for: f.low)
        _ = f.graph.value(of: f.reader)       // reruns because of the kept edge, then prunes it
        f.graph.setValue(3, for: f.low)
        _ = f.graph.value(of: f.reader)       // pruned by now? no: kept one evaluation, so reruns once more
        #expect(f.runs.value == 3)
        f.graph.setValue(4, for: f.low)
        _ = f.graph.value(of: f.reader)
        #expect(f.runs.value == 3)
        #expect(f.graph.table.outputs[Int(f.low.id.index)].isEmpty)
    }

    @Test func insertionInsideARuleKeepsOutputsAndChangedFlag() {
        let graph = Graph()
        let low = graph.makeInput(1)
        let high = graph.makeInput(10)
        var changedWhileOnlyLowIsNew = false
        var runs = 0
        let rule = graph.makeStatefulRule(initialValue: 0) { (context: inout RuleContext<Int>) in
            runs += 1
            let h = high.value
            let l = low.value                     // sorts before `high`: inserted in the middle
            changedWhileOnlyLowIsNew = graph.anyInputsChanged(excluding: [high.erased])
            context.value = h + l
        }
        #expect(graph.value(of: rule) == 11)
        #expect(changedWhileOnlyLowIsNew)
        #expect(graph.table.outputs[Int(low.id.index)] == [rule.id.index])
        #expect(graph.table.outputs[Int(high.id.index)] == [rule.id.index])
        graph.setValue(2, for: low)
        #expect(graph.value(of: rule) == 12)
        #expect(runs == 2)
    }

    /// A reader whose edges are created by appends and by insertions in every order keeps them sorted, finds each one
    /// again on later runs and prunes the ones it stops reading (guards the pre-sized first edge array).
    @Test func edgesStaySortedAcrossAppendsAndInsertionsOfManyInputs() {
        let graph = Graph()
        let inputs = (0..<9).map { graph.makeInput($0) }
        let order = [4, 8, 0, 6, 2, 7, 1, 5, 3]
        var useAll = true
        var runs = 0
        let reader = graph.makeRule {
            runs += 1
            var sum = 0
            for i in order where useAll || i % 2 == 0 { sum += graph.value(of: inputs[i]) }
            return sum
        }
        #expect(graph.value(of: reader) == 36)
        let ids = graph.inputs(of: reader.id).map { $0.index }
        #expect(ids == ids.sorted() && ids.count == 9)

        useAll = false
        graph.setValue(100, for: inputs[3])
        #expect(graph.value(of: reader) == 0 + 2 + 4 + 6 + 8)
        #expect(graph.inputs(of: reader.id).count == 5)
        graph.setValue(50, for: inputs[3])                  // pruned: no rerun
        #expect(graph.value(of: reader) == 20 && runs == 2)
        graph.setValue(10, for: inputs[4])
        #expect(graph.value(of: reader) == 26 && runs == 3)
    }
}
