import Testing
@testable import SwiftAttributeGraph

/// `update(_:flags:)` repeats its walk until a pass updates nothing and clears the requested mark bits only at the end,
/// so attributes dirtied while it runs are updated in the same call. Expected values observed in native AttributeGraph
/// with the `NativeProbe` scenarios `is-dirty-dirtied-during-update-b-first` / `-b-last`.
@Suite struct SubgraphUpdateFlagsLoopTests {
    private final class Log { var runs: [String] = [] }

    private struct OffsetRule: Rule {
        var source: Attribute<Int>
        var offset: Int
        let name: String
        let log: Log
        var value: Int {
            log.runs.append(name)
            return source.value + offset
        }
    }

    /// `isDirty` of each `(subgraph, flags)` probe, as 0 or 1.
    private func marks(_ graph: Graph, _ probes: [(Subgraph, UInt8)]) -> [Int] {
        probes.map { graph.isDirty($0.0, flags: AttributeFlags(rawValue: $0.1)) ? 1 : 0 }
    }

    private func flags(_ raw: UInt8) -> AttributeFlags { AttributeFlags(rawValue: raw) }

    /// Returns the runs logged since the previous call and clears them.
    private func took(_ log: Log) -> [String] {
        defer { log.runs.removeAll() }
        return log.runs
    }


    @Test(arguments: [true, false])
    func attributesDirtiedDuringUpdateFlagsAreUpdatedInTheSamePass(bFirst: Bool) {
        let graph = Graph()
        let scope = graph.makeSubgraph()
        let log = Log()
        var armed = false
        var b: Attribute<Int>? = nil
        var c: Attribute<Int>? = nil
        let (x, y) = graph.withCurrent(scope) { (graph.makeInput(1), graph.makeInput(100)) }
        let a = graph.withCurrent(scope) { () -> Attribute<Int> in
            if bFirst { b = graph.makeRule(OffsetRule(source: y, offset: 0, name: "b", log: log)) }
            let a = graph.makeRule { () -> Int in
                log.runs.append("a")
                let v = x.value
                if armed {
                    armed = false
                    graph.mutateBody(of: b!, as: OffsetRule.self, invalidating: true) { $0.offset = 10 }
                    graph.mutateBody(of: c!, as: OffsetRule.self, invalidating: true) { $0.offset = 20 }
                }
                return v
            }
            if !bFirst { b = graph.makeRule(OffsetRule(source: y, offset: 0, name: "b", log: log)) }
            c = graph.makeRule(OffsetRule(source: y, offset: 0, name: "c", log: log))
            return a
        }
        graph.setFlags(flags(1), for: a)
        graph.setFlags(flags(1), for: b!)
        graph.setFlags(flags(2), for: c!)
        let p = [(scope, UInt8(1)), (scope, UInt8(2))]
        _ = graph.value(of: a)
        _ = graph.value(of: b!)
        _ = graph.value(of: c!)
        graph.update(scope, flags: flags(3))
        _ = took(log)
        graph.setValue(2, for: x)
        armed = true
        #expect(marks(graph, p) == [1, 0])
        graph.update(scope, flags: flags(1))
        #expect(marks(graph, p) == [0, 1] && took(log) == ["a", "b"])
        graph.update(scope, flags: flags(1))
        #expect(marks(graph, p) == [0, 1] && took(log) == [])
        #expect(graph.value(of: b!) == 110 && graph.value(of: c!) == 120)
        #expect(marks(graph, p) == [0, 1] && took(log) == ["c"])
        graph.update(scope, flags: flags(3))
        #expect(marks(graph, p) == [0, 0])
    }
}
