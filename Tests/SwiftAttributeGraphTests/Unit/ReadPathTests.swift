import Testing
@testable import SwiftAttributeGraph

/// The read is split into a non-generic part inside the engine and a generic part inlined into the caller. These tests
/// pin down that every kind of attribute reads the same through `Graph.value(of:)` and through `Attribute.value`, and
/// that both record the dependency of the running rule.
@Suite struct ReadPathTests {
    private struct Point: BitwiseCopyable, Equatable {
        var x: Int64
        var y: Int64
    }

    @Test func everyKindOfAttributeReadsTheSameThroughBothEntryPoints() {
        let graph = Graph()
        let input = graph.makeInput(Int64(3))
        let rule = graph.makeRule { graph.value(of: input) * 2 }
        let indirect = graph.makeIndirect(rule)
        let point = graph.makeInput(Point(x: 5, y: 7))
        let field = graph.makeOffsetFieldAttribute(of: point, keyPath: \Point.y)

        let throughGraph = graph.makeRule {
            graph.value(of: input) + graph.value(of: rule) + graph.value(of: indirect) + graph.value(of: field)
        }
        let throughAttribute = graph.makeRule { input.value + rule.value + indirect.value + field.value }

        #expect(graph.value(of: throughGraph) == 3 + 6 + 6 + 7)
        #expect(graph.value(of: throughAttribute) == 3 + 6 + 6 + 7)
        #expect(graph.value(of: indirect) == 6)
        #expect(graph.value(of: field) == 7)
    }

    @Test func bothEntryPointsRecordTheDependencyOfTheRunningRule() {
        let graph = Graph()
        let input = graph.makeInput(Int64(1))
        let indirect = graph.makeIndirect(input)
        var runs = (graph: 0, attribute: 0)
        let throughGraph = graph.makeRule { runs.graph += 1; return graph.value(of: input) + graph.value(of: indirect) }
        let throughAttribute = graph.makeRule { runs.attribute += 1; return input.value + indirect.value }
        _ = graph.value(of: throughGraph)
        _ = graph.value(of: throughAttribute)

        graph.setValue(10, for: input)

        #expect(graph.value(of: throughGraph) == 20)
        #expect(graph.value(of: throughAttribute) == 20)
        #expect(runs.graph == 2)
        #expect(runs.attribute == 2)
    }

    @Test func aDeadAttributeStillStopsBothEntryPointsAfterTheSplit() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            let sub = graph.makeSubgraph()
            let input = graph.withCurrent(sub) { graph.makeInput(1) }
            sub.invalidate()
            _ = graph.value(of: input)
        }
    }
}
