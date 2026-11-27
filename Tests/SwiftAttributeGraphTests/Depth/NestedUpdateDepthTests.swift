import Testing
@testable import SwiftAttributeGraph

/// The engine counts how deep the native stack nests inside rule updates. A cold closure chain nests once per level
/// (the rule of each level reads an input that is not computed yet). Resumable rules never nest.
@Suite(.serialized) struct NestedUpdateDepthTests {
    struct ColdPlus: ResumableRule {
        let source: Attribute<Int>
        mutating func resume(_ context: inout ResumableRuleContext<Int>) -> RuleStep {
            switch context.poll(source) {
            case .pending: return .needsInput(source.erased)
            case .ready(let value): context.value = value + 1; return .finished
            }
        }
    }

    @Test func aColdClosureChainReportsOneNestedUpdatePerLevel() {
        let depth = 50
        let graph = Graph()
        var last: Attribute<Int> = graph.makeInput(0)
        graph.withCurrent(graph.rootSubgraph) {
            for _ in 0..<depth {
                let previous = last
                last = graph.makeRule { previous.value + 1 }
            }
        }
        #expect(graph.value(of: last) == depth)
        // The top-level read starts the loop from outside any rule, so only the other levels nest.
        #expect(graph.maxNestedUpdateDepth == depth - 1)
    }

    @Test func aColdResumableChainNeverNestsTheNativeStack() {
        let depth = 100_000
        let graph = Graph()
        var last = graph.makeInput(0)
        for _ in 0..<depth { last = graph.makeResumableRule(ColdPlus(source: last)) }
        #expect(graph.value(of: last) == depth)
        #expect(graph.maxNestedUpdateDepth == 0)
    }

    /// The guard measures the stack left on the current thread and stops the engine with a message before the native
    /// stack overflows. A margin larger than any stack must trip it; the default margin must not, on a normal stack.
    @Test func theStackGuardTripsOnlyWhenTheRemainingStackIsBelowTheMargin() {
        let graph = Graph()
        #expect((graph.nativeStackRemainingBytes() ?? 0) > 0)
        #expect(graph.nestedUpdateWouldExhaustStack() == false)
        graph.stackMarginBytes = Int.max / 2
        #expect(graph.nestedUpdateWouldExhaustStack() == true)
    }
}
