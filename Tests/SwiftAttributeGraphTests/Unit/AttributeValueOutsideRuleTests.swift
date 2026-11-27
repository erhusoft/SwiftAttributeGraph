import Testing
@testable import SwiftAttributeGraph

/// `Attribute.value` and `OptionalAttribute.value` read outside a rule. Oracle scenarios `hueco-b2` to `hueco-b6` and
/// `hueco-b11` (native: the read works, is cached, re-evaluates after an input changes and records no dependency).
@Suite struct AttributeValueOutsideRuleTests {
    @Test func anInputIsReadOutsideARule() {
        let graph = Graph()
        let a = graph.makeInput(7)

        #expect(a.value == 7)
    }

    @Test func aRuleAttributeIsEvaluatedOnceAndCachedWhenReadOutsideARule() {
        let graph = Graph()
        let source = graph.makeInput(5)
        var runs = 0
        let rule = graph.makeRule { () -> Int in
            runs += 1
            return graph.value(of: source) * 10
        }

        #expect(rule.value == 50)
        #expect(rule.value == 50)
        #expect(runs == 1)
        graph.setValue(8, for: source)
        #expect(rule.value == 80)
        #expect(runs == 2)
    }

    @Test func anOptionalAttributeReadsItsTargetOutsideARule() {
        let graph = Graph()
        let a = graph.makeInput(7)

        #expect(OptionalAttribute(a).value == 7)
        #expect(OptionalAttribute<Int>().value == nil)
    }
}
