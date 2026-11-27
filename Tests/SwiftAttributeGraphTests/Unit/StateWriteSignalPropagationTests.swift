import Testing
@testable import SwiftAttributeGraph

/// Replica of SAGCore's state storage: a signal rule with `.stateWrite` comparison plus a version input. A write
/// invalidates the signal and bumps the version. A body-like rule that reads both must re-run.
@Suite struct StateWriteSignalPropagationTests {
    final class Runs { var count = 0 }

    @Test func bodyRuleRerunsAfterWriteThroughSignalAndVersion() {
        let graph = Graph()
        let subgraph = graph.makeSubgraph()
        let runs = Runs()
        var signal: Attribute<Void>!
        var version: Attribute<UInt64>!
        var body: Attribute<Int>!
        var stored = 0

        graph.withCurrent(subgraph) {
            signal = graph.makeRule({ () }, comparison: .stateWrite)
            version = graph.makeInput(0 as UInt64, comparison: .comparison(.equatableAlways))
            body = graph.makeStatefulRule(
                BodyStateRule(read: { () -> Int in
                    _ = graph.value(of: signal)
                    _ = graph.value(of: version)
                    return stored
                }, runs: runs),
                comparison: .comparison(.equatableUnlessPOD)
            )
        }

        #expect(graph.value(of: body) == 0)
        #expect(runs.count == 1)

        stored = 7
        graph.setValue(1 as UInt64, for: version)
        graph.invalidateValue(of: signal)
        #expect(graph.value(of: body) == 7)
        #expect(runs.count == 2)
    }

    struct BodyStateRule: StatefulRule {
        typealias Value = Int
        let read: () -> Int
        let runs: Runs
        mutating func updateValue(_ context: inout RuleContext<Int>) {
            runs.count += 1
            context.value = read()
        }
    }
}
