import Testing
@testable import SwiftAttributeGraph

/// A rule that reads a value only through a version input must re-run when that version changes, the same way SAGCore's
/// stored state reads its version attribute.
@Suite struct VersionedReadPropagationTests {
    final class Counter { var runs = 0 }

    @Test func ruleRerunsWhenItsVersionInputIsWritten() {
        let graph = Graph()
        let version = graph.makeInput(0 as UInt64, comparison: .comparison(.equatableAlways))
        let counter = Counter()
        let rule = graph.makeRule {
            counter.runs += 1
            return graph.value(of: version)
        }

        #expect(graph.value(of: rule) == 0)
        #expect(counter.runs == 1)

        graph.setValue(1 as UInt64, for: version)
        #expect(graph.value(of: rule) == 1)
        #expect(counter.runs == 2)
    }

    @Test func ruleRerunsWhenItsVersionInputChangesFromAnotherRuleRead() {
        let graph = Graph()
        let version = graph.makeInput(0 as UInt64, comparison: .comparison(.equatableAlways))
        let counter = Counter()
        let rule = graph.makeRule {
            counter.runs += 1
            return graph.value(of: version) * 10
        }

        #expect(graph.value(of: rule) == 0)
        graph.setValue(2 as UInt64, for: version)
        #expect(graph.value(of: rule) == 20)
        #expect(counter.runs == 2)
    }
}

extension VersionedReadPropagationTests {
    /// Mirrors SAGCore's `ViewBodyRule`: a stateful rule that reads its source and a version inside `updateValue`.
    struct BodyLikeRule: StatefulRule {
        typealias Value = Int
        let source: Attribute<Int>
        let version: Attribute<UInt64>
        let counter: Counter

        mutating func updateValue(_ context: inout RuleContext<Int>) {
            counter.runs += 1
            let base = source.value
            let v = Int(version.value)
            context.value = base + v
        }
    }

    @Test func statefulRuleRerunsWhenItsVersionInputIsWritten() {
        let graph = Graph()
        let source = graph.makeInput(5, comparison: .comparison(.equatableUnlessPOD))
        let version = graph.makeInput(0 as UInt64, comparison: .comparison(.equatableAlways))
        let counter = Counter()
        let rule = graph.makeStatefulRule(BodyLikeRule(source: source, version: version, counter: counter), comparison: .comparison(.equatableUnlessPOD))

        #expect(graph.value(of: rule) == 5)
        graph.setValue(3 as UInt64, for: version)
        #expect(graph.value(of: rule) == 8)
        #expect(counter.runs == 2)
    }
}

extension VersionedReadPropagationTests {
    /// As above, but the version input and the rule belong to a subgraph, as SAGCore's state and body rule do.
    @Test func statefulRuleInSubgraphRerunsWhenItsVersionInputIsWritten() {
        let graph = Graph()
        let subgraph = graph.makeSubgraph()
        let counter = Counter()
        var version: Attribute<UInt64>!
        var source: Attribute<Int>!
        var rule: Attribute<Int>!
        graph.withCurrent(subgraph) {
            source = graph.makeInput(5, comparison: .comparison(.equatableUnlessPOD))
            version = graph.makeInput(0 as UInt64, comparison: .comparison(.equatableAlways))
            rule = graph.makeStatefulRule(BodyLikeRule(source: source, version: version, counter: counter), comparison: .comparison(.equatableUnlessPOD))
        }

        #expect(graph.value(of: rule) == 5)
        graph.setValue(3 as UInt64, for: version)
        #expect(graph.value(of: rule) == 8)
        #expect(counter.runs == 2)
    }
}
