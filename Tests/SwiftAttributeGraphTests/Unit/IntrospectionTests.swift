import Testing
@testable import SwiftAttributeGraph

/// Tests for M8: tools — counters, graph dump, memory footprint.
@Suite struct IntrospectionTests {

    // MARK: - Edge counters

    @Test func inputAndOutputCountOfAnAttribute() {
        let graph = Graph()
        let a = graph.makeInput(1)
        let b = graph.makeInput(2)
        let rule = graph.makeRule { a.value + b.value }
        _ = graph.value(of: rule)

        #expect(graph.inputCount(of: rule.id) == 2)
        #expect(graph.outputCount(of: a.id) == 1)
        #expect(graph.outputCount(of: b.id) == 1)
    }

    @Test func edgeCountIsTheSumOfAllInputEdges() {
        let graph = Graph()
        let a = graph.makeInput(1)
        let b = graph.makeInput(2)
        let c = graph.makeRule { a.value + b.value }
        let d = graph.makeRule { c.value + 1 }
        _ = graph.value(of: c)
        _ = graph.value(of: d)

        // c reads a and b (2 edges), d reads c (1 edge): 3 total.
        #expect(graph.edgeCount == 3)
    }

    @Test func edgeCountUpdatesAfterPruning() {
        let graph = Graph()
        let a = graph.makeInput(1)
        let flag = graph.makeInput(true)

        let rule = graph.makeRule {
            _ = flag.value
            return flag.value ? a.value + 1 : 0
        }
        _ = graph.value(of: rule)
        #expect(graph.edgeCount == 2) // reads flag and a

        graph.setValue(false, for: flag)
        _ = graph.value(of: rule) // prunes the edge to a
        #expect(graph.edgeCount == 1) // only flag remains
    }

    // MARK: - Recalculation counter

    @Test func recalculationCountIncrementsWhenARuleRuns() {
        let graph = Graph()
        let input = graph.makeInput(0)
        let rule = graph.makeRule { input.value + 1 }

        #expect(graph.recalculationCount == 0)

        _ = graph.value(of: rule)
        #expect(graph.recalculationCount == 1)

        // Reading again without changes: the rule is cut, not re-run.
        _ = graph.value(of: rule)
        #expect(graph.recalculationCount == 1)

        // Changing the input forces a re-run.
        graph.setValue(1, for: input)
        _ = graph.value(of: rule)
        #expect(graph.recalculationCount == 2)
    }

    @Test func recalculationCountCountsEachIndependentRun() {
        let graph = Graph()
        let input = graph.makeInput(0)
        let rules = (0..<5).map { _ in graph.makeRule { input.value + 1 } }
        for rule in rules { _ = graph.value(of: rule) }

        #expect(graph.recalculationCount == 5)
    }

    // MARK: - Graph dump

    @Test func dumpListsLiveAttributes() {
        let graph = Graph()
        let a = graph.makeInput(1)
        let rule = graph.makeRule { a.value + 1 }
        _ = graph.value(of: rule)

        let dump = graph.dump()
        #expect(dump.contains("attributes"))
        #expect(dump.contains("edges"))
        #expect(dump.contains(String(a.id.index)))
        #expect(dump.contains(String(rule.id.index)))
    }

    @Test func dumpShowsInputAndRuleDifferently() {
        let graph = Graph()
        let input = graph.makeInput(5)
        let rule = graph.makeRule { input.value * 2 }
        _ = graph.value(of: rule)

        let dump = graph.dump()
        // The input line should say "input", the rule line should say "rule".
        let inputLine = dump.split(separator: "\n").first { $0.contains("gen=") && $0.contains("input") }
        let ruleLine = dump.split(separator: "\n").first { $0.contains("gen=") && $0.contains("rule") }
        #expect(inputLine != nil)
        #expect(ruleLine != nil)
    }

    // MARK: - Memory footprint

    @Test func estimatedMemoryFootprintIsPositiveAndGrows() {
        let graph = Graph()
        let first = graph.estimatedMemoryFootprint
        #expect(first > 0)

        _ = (0..<100).map { graph.makeInput($0) }
        let after = graph.estimatedMemoryFootprint
        #expect(after > first)
    }

    @Test func estimatedMemoryFootprintReflectsEdges() {
        let graph = Graph()
        let base = graph.estimatedMemoryFootprint

        let input = graph.makeInput(0)
        let rules = (0..<10).map { _ in graph.makeRule { input.value + 1 } }
        for rule in rules { _ = graph.value(of: rule) }

        let withEdges = graph.estimatedMemoryFootprint
        #expect(withEdges > base)
    }

    // MARK: - C31: breadthFirstSearch

    @Test func breadthFirstSearchVisitsStartThenNeighboursInOrderAndStopsOnMatch() {
        let graph = Graph()
        let a = graph.makeInput(1)
        let b = graph.makeInput(2)
        let r1 = graph.makeRule { a.value + b.value }
        let r2 = graph.makeRule { r1.value + a.value }
        _ = graph.value(of: r2)

        // Search inputs from `r2`: visits `r2`, then its inputs in ascending ID order (`a`, `r1`), then `b`.
        var visitedInputs: [AttributeID] = []
        let foundAllInputs = graph.breadthFirstSearch(from: r2, options: .searchInputs) { attr in
            visitedInputs.append(attr.id)
            return false
        }
        #expect(!foundAllInputs)
        #expect(visitedInputs == [r2.id, a.id, r1.id, b.id])

        // Search outputs from `a`: visits `a`, then `r1`, `r2`.
        var visitedOutputs: [AttributeID] = []
        let foundAllOutputs = graph.breadthFirstSearch(from: a, options: .searchOutputs) { attr in
            visitedOutputs.append(attr.id)
            return false
        }
        #expect(!foundAllOutputs)
        #expect(visitedOutputs == [a.id, r1.id, r2.id])

        // Early exit when predicate returns `true`.
        var visitedStop: [AttributeID] = []
        let stopped = graph.breadthFirstSearch(from: r2, options: .searchInputs) { attr in
            visitedStop.append(attr.id)
            return attr.id == r1.id
        }
        #expect(stopped)
        #expect(visitedStop == [r2.id, a.id, r1.id])

        // Empty options visit only the start node.
        var visitedEmpty: [AttributeID] = []
        let foundEmpty = graph.breadthFirstSearch(from: r2, options: []) { attr in
            visitedEmpty.append(attr.id)
            return false
        }
        #expect(!foundEmpty)
        #expect(visitedEmpty == [r2.id])
    }
}
