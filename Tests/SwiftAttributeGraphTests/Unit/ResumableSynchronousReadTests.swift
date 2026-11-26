import Testing
@testable import SwiftAttributeGraph

/// Parity with Apple: a resumable rule may read a dirty input synchronously, as a closure rule does, and the read
/// updates that input inside the rule's run. Polling stays available, but a synchronous read is not an error.
@Suite struct ResumableSynchronousReadTests {
    struct SyncPlus: ResumableRule {
        let graph: Graph
        let source: Attribute<Int>

        mutating func resume(_ context: inout ResumableRuleContext<Int>) -> RuleStep {
            context.value = graph.value(of: source) + 1
            return .finished
        }
    }

    @Test func aResumableRuleReadingADirtyInputSynchronouslyGetsTheValue() {
        let graph = Graph()
        let input = graph.makeInput(1)
        let previous = graph.makeRule { graph.value(of: input) * 10 }
        let rule = graph.makeResumableRule(SyncPlus(graph: graph, source: previous))
        #expect(graph.value(of: rule) == 11)
        graph.setValue(2, for: input)
        #expect(graph.value(of: rule) == 21)
    }
}
