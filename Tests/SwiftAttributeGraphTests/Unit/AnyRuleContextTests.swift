import Testing
@testable import SwiftAttributeGraph

@Suite("AnyRuleContextTests")
struct AnyRuleContextTests {
    @Test func typedRuleContextSubscriptsReadDependencies() {
        let graph = Graph()
        let in1 = graph.makeInput(10)
        let in2 = graph.makeInput("abc")
        let in3 = graph.makeInput(99.0)

        let weakIn2 = WeakAttribute(in2)
        let optIn3 = OptionalAttribute(in3)

        var contextAttribute: Attribute<Int>?
        var readWeakVal: String?
        var readOptVal: Double?

        let rule = graph.makeStatefulRule(initialValue: 0) { (ctx: inout RuleContext<Int>) in
            contextAttribute = ctx.attribute
            let v1 = ctx[in1]
            readWeakVal = ctx[weakIn2]
            readOptVal = ctx[optIn3]
            ctx.value = v1 + 5
        }

        #expect(graph.value(of: rule) == 15)
        #expect(contextAttribute == rule)
        #expect(readWeakVal == "abc")
        #expect(readOptVal == 99.0)
    }

    @Test func anyRuleContextWrapsAndCastsBack() {
        let graph = Graph()
        let input = graph.makeInput(50)
        let rule = graph.makeInput(0) // simple node

        let typedCtx = RuleContext<Int>(attribute: rule)
        let anyCtx = AnyRuleContext(typedCtx)

        #expect(anyCtx.attribute == rule.erased)
        #expect(anyCtx == AnyRuleContext(attribute: rule.erased))

        let castBack = anyCtx.unsafeCast(to: Int.self)
        #expect(castBack == typedCtx)
        #expect(castBack.attribute == rule)

        // Subscripts on AnyRuleContext
        #expect(anyCtx[input] == 50)
        #expect(anyCtx[WeakAttribute(input)] == 50)
        #expect(anyCtx[OptionalAttribute(input)] == 50)
    }

    @Test func anyRuleContextUpdateExecutesInScope() {
        let graph = Graph()
        let ruleNode = graph.makeInput(1)
        let anyCtx = AnyRuleContext(attribute: ruleNode.erased)

        var insideEvaluatingNode: UInt32?
        anyCtx.update {
            insideEvaluatingNode = graph.evaluatingNode
        }

        #expect(insideEvaluatingNode == ruleNode.id.index)
        #expect(graph.evaluatingNode == Graph.noNode)
    }
}
