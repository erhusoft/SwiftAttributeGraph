import Testing
@testable import SwiftAttributeGraph

/// The input edges of a node are walked by `NodeTable` helpers (scan for the update stack, mark read, begin a run, keep
/// all when all were read). These tests pin down the cases each helper must hand back to the general code.
@Suite struct EdgeScanTests {
    @Test func readsInDescendingOrderInsertEdgesSortedAndFindThemAgain() {
        let graph = Graph()
        let inputs = (0..<5).map { graph.makeInput($0) }
        var runs = 0
        let rule = graph.makeRule { () -> Int in
            runs += 1
            return inputs.reversed().reduce(0) { $0 * 10 + graph.value(of: $1) }
        }
        #expect(graph.value(of: rule) == 43210)
        #expect(graph.inputs(of: rule.id) == inputs.map(\.id))

        graph.setValue(9, for: inputs[2])
        #expect(graph.value(of: rule) == 43910)
        #expect(graph.inputs(of: rule.id) == inputs.map(\.id))
        #expect(runs == 2)
    }

    @Test func anEdgeNotReadInTheLastRunIsPrunedAndTheOthersStay() {
        let graph = Graph()
        let flag = graph.makeInput(true)
        let a = graph.makeInput(1)
        let b = graph.makeInput(2)
        let rule = graph.makeRule { graph.value(of: flag) ? graph.value(of: a) + graph.value(of: b) : graph.value(of: b) }
        #expect(graph.value(of: rule) == 3)
        #expect(graph.inputCount(of: rule.id) == 3)

        graph.setValue(false, for: flag)
        #expect(graph.value(of: rule) == 2)
        #expect(graph.inputs(of: rule.id) == [flag.id, b.id])
        #expect(graph.outputCount(of: a.id) == 0)
    }

    @Test func theScanStopsAtADirtyInputAndResumesAfterUpdatingIt() {
        let graph = Graph()
        let a = graph.makeInput(1)
        let b = graph.makeInput(10)
        let middle = graph.makeRule { graph.value(of: b) % 2 }
        var runs = 0
        let rule = graph.makeRule { () -> Int in runs += 1; return graph.value(of: a) + graph.value(of: middle) }
        #expect(graph.value(of: rule) == 1)

        // `b` changes but `middle` keeps its value: the scan stops at the dirty `middle`, updates it, and the rule is
        // cut because no input version changed.
        graph.setValue(12, for: b)
        #expect(graph.value(of: rule) == 1)
        #expect(runs == 1)

        // Now an earlier input changed too: the rule must run.
        graph.setValue(2, for: a)
        graph.setValue(13, for: b)
        #expect(graph.value(of: rule) == 3)
        #expect(runs == 2)
    }
}
