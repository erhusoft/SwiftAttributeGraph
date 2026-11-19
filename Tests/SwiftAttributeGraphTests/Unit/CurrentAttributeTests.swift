import Testing
@testable import SwiftAttributeGraph

/// `Graph.currentAttribute` (`AGGraphGetCurrentAttribute`) and `Graph.currentAttributeWasModified`
/// (`AGGraphCurrentAttributeWasModified`). Expected values were measured natively on macOS 15.8.3
/// (probe_getvalue_and_current.swift, probe_current_b.swift, probe_current_c.swift).
@Suite struct CurrentAttributeTests {
    private final class Log: @unchecked Sendable { var items: [String] = []; var ids: [AnyAttribute?] = [] }

    @Test func thereIsNoCurrentAttributeOutsideARule() {
        let graph = Graph()
        let input = graph.makeInput(1)
        #expect(Graph.currentAttribute == nil)
        _ = graph.value(of: input)
        #expect(Graph.currentAttribute == nil)
        #expect(Graph.currentAttributeWasModified == false)
    }

    @Test func insideARuleTheCurrentAttributeIsTheRuleItselfOnEveryRun() {
        let graph = Graph()
        let src = graph.makeInput(1)
        let log = Log()
        let rule = graph.makeRule { log.ids.append(Graph.currentAttribute); return graph.value(of: src) }
        _ = graph.value(of: rule)
        graph.setValue(2, for: src)
        _ = graph.value(of: rule)
        #expect(log.ids == [rule.erased, rule.erased])
        #expect(Graph.currentAttribute == nil)
    }

    @Test func aNestedRuleSeesItselfAndTheOuterOneIsRestoredWhenTheReadReturns() {
        let graph = Graph()
        var innerSeen: AnyAttribute?
        let inner = graph.makeRule { innerSeen = Graph.currentAttribute; return 7 }
        let log = Log()
        let outer = graph.makeRule {
            log.ids.append(Graph.currentAttribute)
            let v = graph.value(of: inner)
            log.ids.append(Graph.currentAttribute)
            return v
        }
        _ = graph.value(of: outer)
        #expect(innerSeen == inner.erased)
        #expect(log.ids == [outer.erased, outer.erased])
    }

    @Test func clearUpdateHidesTheCurrentAttributeAndSetUpdateRestoresIt() {
        let graph = Graph()
        let log = Log()
        let rule = graph.makeRule {
            let token = Graph.clearUpdate()
            log.ids.append(Graph.currentAttribute)
            Graph.setUpdate(token)
            log.ids.append(Graph.currentAttribute)
            return 1
        }
        _ = graph.value(of: rule)
        #expect(log.ids == [nil, rule.erased])
    }

    @Test func withoutUpdateHidesTheCurrentAttributeToo() {
        let graph = Graph()
        let log = Log()
        let rule = graph.makeRule {
            graph.withoutUpdate { log.ids.append(Graph.currentAttribute) }
            log.ids.append(Graph.currentAttribute)
            return 1
        }
        _ = graph.value(of: rule)
        #expect(log.ids == [nil, rule.erased])
    }

    @Test func aStatefulRuleSeesItselfAsTheCurrentAttribute() {
        let graph = Graph()
        let src = graph.makeInput(1)
        let log = Log()
        let rule = graph.makeStatefulRule(initialValue: 0) { (context: inout RuleContext<Int>) in
            log.ids.append(Graph.currentAttribute)
            context.value = graph.value(of: src)
        }
        _ = graph.value(of: rule)
        graph.setValue(2, for: src)
        _ = graph.value(of: rule)
        #expect(log.ids == [rule.erased, rule.erased])
    }

    /// Natively the query was `false` in every measured case: outside a rule, in plain rules, in stateful rules before
    /// and after writing the value (different or equal value, through the context or `AGGraphSetOutputValue`), in
    /// stateful rules that do not write, and in an outer rule after an inner stateful rule wrote.
    @Test func wasModifiedIsFalseInEveryMeasuredCase() {
        let graph = Graph()
        let src = graph.makeInput(1)
        let log = Log()
        let writer = graph.makeStatefulRule(initialValue: 0) { (context: inout RuleContext<Int>) in
            let s = graph.value(of: src)
            log.items.append("before=\(Graph.currentAttributeWasModified)")
            context.value = 10 + s
            log.items.append("after=\(Graph.currentAttributeWasModified)")
        }
        let silent = graph.makeStatefulRule(initialValue: 0) { (_: inout RuleContext<Int>) in
            _ = graph.value(of: src)
            log.items.append("silent=\(Graph.currentAttributeWasModified)")
        }
        let plain = graph.makeRule { log.items.append("plain=\(Graph.currentAttributeWasModified)"); return 1 }
        let outer = graph.makeRule {
            let b = Graph.currentAttributeWasModified
            let v = graph.value(of: writer)
            log.items.append("outer=\(b),\(Graph.currentAttributeWasModified)")
            return v
        }
        _ = graph.value(of: writer); _ = graph.value(of: silent); _ = graph.value(of: plain); _ = graph.value(of: outer)
        graph.setValue(2, for: src)
        _ = graph.value(of: writer); _ = graph.value(of: silent)
        #expect(log.items.allSatisfy { $0.hasSuffix("false") || $0.contains("false,false") })
        #expect(!log.items.contains { $0.contains("true") })
        #expect(log.items.count == 8)
    }
}
