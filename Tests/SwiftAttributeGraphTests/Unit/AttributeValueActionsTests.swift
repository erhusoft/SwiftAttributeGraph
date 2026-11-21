import Testing
@testable import SwiftAttributeGraph

/// `AGAttribute.updateValue(self:)` and `AGAttribute.invalidateValue(self:)`. Same behaviour as the graph operations they
/// wrap, which the oracle already measures (`prefetch`, `invalidate-in-rule`).
@Suite struct AttributeValueActionsTests {
    @Test func invalidateValueMakesTheRuleRunAgainOnItsNextRead() {
        let graph = Graph()
        var runs = 0
        let rule = graph.makeRule { () -> Int in runs += 1; return 5 }
        _ = graph.value(of: rule)
        rule.invalidateValue()
        _ = graph.value(of: rule)
        #expect(runs == 2)
    }

    @Test func updateValueRunsADirtyRuleNow() {
        let graph = Graph()
        let source = graph.makeInput(1)
        var runs = 0
        let rule = graph.makeRule { () -> Int in runs += 1; return graph.value(of: source) + 1 }
        _ = graph.value(of: rule)
        graph.setValue(2, for: source)
        rule.updateValue()
        #expect(runs == 2)
    }
}
