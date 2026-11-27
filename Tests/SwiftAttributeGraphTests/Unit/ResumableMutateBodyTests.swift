import Testing
@testable import SwiftAttributeGraph

/// A resumable rule's body can be mutated in place, as `Rule` and `StatefulRule` bodies can, and a mutation with
/// invalidation makes the rule run again with the new body.
@Suite struct ResumableMutateBodyTests {
    struct Offset: ResumableRule {
        let source: Attribute<Int>
        var offset: Int

        mutating func resume(_ context: inout ResumableRuleContext<Int>) -> RuleStep {
            switch context.poll(source) {
            case .pending: return .needsInput(source.erased)
            case .ready(let value): context.value = value + offset; return .finished
            }
        }
    }

    @Test func aMutatedBodyRunsAgainWithTheNewValue() {
        let graph = Graph()
        let source = graph.makeInput(10)
        let rule = graph.makeResumableRule(Offset(source: source, offset: 1))
        #expect(graph.value(of: rule) == 11)
        graph.mutateBody(of: rule, as: Offset.self, invalidating: true) { body in
            body.offset = 5
        }
        #expect(graph.value(of: rule) == 15)
    }
}
