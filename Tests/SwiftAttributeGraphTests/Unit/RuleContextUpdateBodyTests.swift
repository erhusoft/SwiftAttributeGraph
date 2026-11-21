import Testing
@testable import SwiftAttributeGraph

/// `RuleContext.update(body:)`. Measured on macOS 15.8 (two steps): inside the body the current attribute is the context's
/// attribute, and a dependency read inside the body is recorded for the context's attribute, not for the caller.
@Suite struct RuleContextUpdateBodyTests {
    @Test func insideTheBodyTheCurrentAttributeIsTheContextsAttribute() {
        let graph = Graph()
        var saved: RuleContext<Int>? = nil
        let ruleA = graph.makeStatefulRule(initialValue: 0) { (context: inout RuleContext<Int>) in
            saved = context
        }
        _ = graph.value(of: ruleA)
        var inside: AnyAttribute? = nil
        let ruleB = graph.makeRule { () -> Int in
            saved?.update(body: { inside = Graph.currentAttribute })
            return 1
        }
        _ = graph.value(of: ruleB)
        #expect(inside == ruleA.erased)
    }

    @Test func aDependencyReadInsideTheBodyBelongsToTheContextsAttribute() {
        let graph = Graph()
        let source = graph.makeInput(1)
        var saved: RuleContext<Int>? = nil
        var runsA = 0
        let ruleA = graph.makeStatefulRule(initialValue: 0) { (context: inout RuleContext<Int>) in
            runsA += 1
            saved = context
        }
        _ = graph.value(of: ruleA)
        var runsB = 0
        let ruleB = graph.makeRule { () -> Int in
            runsB += 1
            saved?.update(body: { _ = graph.value(of: source) })
            return 1
        }
        _ = graph.value(of: ruleB)
        graph.setValue(2, for: source)
        _ = graph.value(of: ruleA)
        _ = graph.value(of: ruleB)
        #expect(runsA == 2)
        #expect(runsB == 1)
    }
}
