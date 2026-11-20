import Testing
import SwiftAttributeGraph

@Suite struct AGProbeParityTests {
    private final class Counter { var value = 0 }

    private final class DynState {
        var rExec = 0
        var hExec = 0
        var branch = "-"
    }

    private final class MultiCounters {
        var r1 = 0
        var r2 = 0
        var h = 0
    }

    private final class DiamondState {
        var r1 = 0
        var r2 = 0
        var h = 0
        var readR1 = 0
        var readR2 = 0
        var r2Branch = "-"
    }

    private struct ParityRule: Rule {
        let a: Attribute<Int>
        let counter: Counter
        var value: Int {
            counter.value += 1
            return a.value % 2
        }
    }

    private struct ParityStatefulUnconditional: StatefulRule {
        let a: Attribute<Int>
        let counter: Counter
        mutating func updateValue(_ context: inout RuleContext<Int>) {
            counter.value += 1
            context.value = a.value % 2
        }
    }

    private struct ParityStatefulConditional: StatefulRule {
        let a: Attribute<Int>
        let counter: Counter
        mutating func updateValue(_ context: inout RuleContext<Int>) {
            counter.value += 1
            let next = a.value % 2
            if !context.hasValue || context.value != next {
                context.value = next
            }
        }
    }

    private struct AddOffsetRule: Rule {
        let r: Attribute<Int>
        let offset: Int
        let counter: Counter
        var value: Int {
            counter.value += 1
            return r.value + offset
        }
    }

    private func runParityScenario(
        nextA: Int,
        makeR: (Graph, Attribute<Int>, Counter) -> Attribute<Int>
    ) -> (h0: Int, beforeR: Int, beforeH: Int, h1: Int, rExec: Int, hExec: Int) {
        let graph = Graph()
        let rc = Counter(), hc = Counter()
        let a = graph.makeInput(1)
        let r = makeR(graph, a, rc)
        let h = graph.makeRule(AddOffsetRule(r: r, offset: 10, counter: hc))

        let h0 = graph.value(of: h)
        graph.setValue(nextA, for: a)
        let beforeR = rc.value
        let beforeH = hc.value
        let h1 = graph.value(of: h)
        return (h0, beforeR, beforeH, h1, rc.value, hc.value)
    }

    // MARK: - 1-9: Rule & StatefulRule

    @Test func rule_positive() {
        let res = runParityScenario(nextA: 2) { g, a, c in g.makeRule(ParityRule(a: a, counter: c)) }
        #expect(res == (11, 1, 1, 10, 2, 2))
    }

    @Test func rule_cutoff() {
        let res = runParityScenario(nextA: 3) { g, a, c in g.makeRule(ParityRule(a: a, counter: c)) }
        #expect(res == (11, 1, 1, 11, 2, 1))
    }

    @Test func rule_no_change() {
        let res = runParityScenario(nextA: 1) { g, a, c in g.makeRule(ParityRule(a: a, counter: c)) }
        #expect(res == (11, 1, 1, 11, 1, 1))
    }

    @Test func stateful_uncond_positive() {
        let res = runParityScenario(nextA: 2) { g, a, c in g.makeStatefulRule(ParityStatefulUnconditional(a: a, counter: c)) }
        #expect(res == (11, 1, 1, 10, 2, 2))
    }

    @Test func stateful_uncond_cutoff() {
        let res = runParityScenario(nextA: 3) { g, a, c in g.makeStatefulRule(ParityStatefulUnconditional(a: a, counter: c)) }
        #expect(res == (11, 1, 1, 11, 2, 1))
    }

    @Test func stateful_uncond_no_change() {
        let res = runParityScenario(nextA: 1) { g, a, c in g.makeStatefulRule(ParityStatefulUnconditional(a: a, counter: c)) }
        #expect(res == (11, 1, 1, 11, 1, 1))
    }

    @Test func stateful_cond_positive() {
        let res = runParityScenario(nextA: 2) { g, a, c in g.makeStatefulRule(ParityStatefulConditional(a: a, counter: c)) }
        #expect(res == (11, 1, 1, 10, 2, 2))
    }

    @Test func stateful_cond_cutoff() {
        let res = runParityScenario(nextA: 3) { g, a, c in g.makeStatefulRule(ParityStatefulConditional(a: a, counter: c)) }
        #expect(res == (11, 1, 1, 11, 2, 1))
    }

    @Test func stateful_cond_no_change() {
        let res = runParityScenario(nextA: 1) { g, a, c in g.makeStatefulRule(ParityStatefulConditional(a: a, counter: c)) }
        #expect(res == (11, 1, 1, 11, 1, 1))
    }

    // MARK: - 10-12: Dynamic Dependencies

    @Test func dynamic_branches() {
        let graph = Graph()
        let s = DynState()
        let sel = graph.makeInput(true)
        let a = graph.makeInput(10)
        let b = graph.makeInput(20)
        let r = graph.makeRule {
            s.rExec += 1
            if sel.value { s.branch = "A"; return a.value }
            else { s.branch = "B"; return b.value }
        }
        let h = graph.makeRule { s.hExec += 1; return r.value + 100 }

        #expect((graph.value(of: h), graph.value(of: r), s.rExec, s.hExec, s.branch) == (110, 10, 1, 1, "A"))
        graph.setValue(30, for: b)
        #expect((graph.value(of: h), graph.value(of: r), s.rExec, s.hExec, s.branch) == (110, 10, 1, 1, "A"))
        graph.setValue(11, for: a)
        #expect((graph.value(of: h), graph.value(of: r), s.rExec, s.hExec, s.branch) == (111, 11, 2, 2, "A"))
        graph.setValue(false, for: sel)
        #expect((graph.value(of: h), graph.value(of: r), s.rExec, s.hExec, s.branch) == (130, 30, 3, 3, "B"))
        graph.setValue(12, for: a)
        #expect((graph.value(of: h), graph.value(of: r), s.rExec, s.hExec, s.branch) == (130, 30, 3, 3, "B"))
        graph.setValue(31, for: b)
        #expect((graph.value(of: h), graph.value(of: r), s.rExec, s.hExec, s.branch) == (131, 31, 4, 4, "B"))
        graph.setValue(true, for: sel)
        #expect((graph.value(of: h), graph.value(of: r), s.rExec, s.hExec, s.branch) == (112, 12, 5, 5, "A"))
        graph.setValue(32, for: b)
        #expect((graph.value(of: h), graph.value(of: r), s.rExec, s.hExec, s.branch) == (112, 12, 5, 5, "A"))
    }

    @Test func dynamic_same_output() {
        let graph = Graph()
        let s = DynState()
        let sel = graph.makeInput(true)
        let a = graph.makeInput(10)
        let b = graph.makeInput(10)
        let r = graph.makeRule {
            s.rExec += 1
            if sel.value { s.branch = "A"; return a.value }
            else { s.branch = "B"; return b.value }
        }
        let h = graph.makeRule { s.hExec += 1; return r.value + 100 }

        #expect((graph.value(of: h), graph.value(of: r), s.rExec, s.hExec, s.branch) == (110, 10, 1, 1, "A"))
        graph.setValue(false, for: sel)
        #expect((graph.value(of: h), graph.value(of: r), s.rExec, s.hExec, s.branch) == (110, 10, 2, 1, "B"))
        graph.setValue(11, for: a)
        #expect((graph.value(of: h), graph.value(of: r), s.rExec, s.hExec, s.branch) == (110, 10, 2, 1, "B"))
        graph.setValue(12, for: b)
        #expect((graph.value(of: h), graph.value(of: r), s.rExec, s.hExec, s.branch) == (112, 12, 3, 2, "B"))
        graph.setValue(true, for: sel)
        #expect((graph.value(of: h), graph.value(of: r), s.rExec, s.hExec, s.branch) == (111, 11, 4, 3, "A"))
        graph.setValue(13, for: b)
        #expect((graph.value(of: h), graph.value(of: r), s.rExec, s.hExec, s.branch) == (111, 11, 4, 3, "A"))
        graph.setValue(14, for: a)
        #expect((graph.value(of: h), graph.value(of: r), s.rExec, s.hExec, s.branch) == (114, 14, 5, 4, "A"))
    }

    @Test func dynamic_constant_branch() {
        let graph = Graph()
        let s = DynState()
        let sel = graph.makeInput(true)
        let a = graph.makeInput(100)
        let r = graph.makeRule {
            s.rExec += 1
            if sel.value { s.branch = "A"; return a.value }
            else { s.branch = "const(100)"; return 100 }
        }
        let h = graph.makeRule { s.hExec += 1; return r.value + 10 }

        #expect((graph.value(of: h), graph.value(of: r), s.rExec, s.hExec, s.branch) == (110, 100, 1, 1, "A"))
        graph.setValue(false, for: sel)
        #expect((graph.value(of: h), graph.value(of: r), s.rExec, s.hExec, s.branch) == (110, 100, 2, 1, "const(100)"))
        graph.setValue(101, for: a)
        #expect((graph.value(of: h), graph.value(of: r), s.rExec, s.hExec, s.branch) == (110, 100, 2, 1, "const(100)"))
        graph.setValue(102, for: a)
        #expect((graph.value(of: h), graph.value(of: r), s.rExec, s.hExec, s.branch) == (110, 100, 2, 1, "const(100)"))
        graph.setValue(true, for: sel)
        #expect((graph.value(of: h), graph.value(of: r), s.rExec, s.hExec, s.branch) == (112, 102, 3, 2, "A"))
        graph.setValue(103, for: a)
        #expect((graph.value(of: h), graph.value(of: r), s.rExec, s.hExec, s.branch) == (113, 103, 4, 3, "A"))
        graph.setValue(false, for: sel)
        #expect((graph.value(of: h), graph.value(of: r), s.rExec, s.hExec, s.branch) == (110, 100, 5, 4, "const(100)"))
        graph.setValue(104, for: a)
        #expect((graph.value(of: h), graph.value(of: r), s.rExec, s.hExec, s.branch) == (110, 100, 5, 4, "const(100)"))
    }

    // MARK: - 13-22: Accumulation & MultiLevel

    private func runMultiInput(_ mutate: (Graph, Attribute<Int>, Attribute<Int>) -> Void) -> (Int, Int, Int, Int) {
        let graph = Graph()
        let c = MultiCounters()
        let a = graph.makeInput(10), b = graph.makeInput(20)
        let r1 = graph.makeRule { c.r1 += 1; return a.value }
        let r2 = graph.makeRule { c.r2 += 1; return b.value }
        let h = graph.makeRule { c.h += 1; return r1.value + r2.value }
        #expect(graph.value(of: h) == 30)
        mutate(graph, a, b)
        #expect((c.r1, c.r2, c.h) == (1, 1, 1))
        let h1 = graph.value(of: h)
        return (h1, c.r1, c.r2, c.h)
    }

    @Test func multi_input_control() {
        #expect(runMultiInput { g, a, _ in g.setValue(11, for: a) } == (31, 2, 1, 2))
    }

    @Test func multi_input_two_changes() {
        #expect(runMultiInput { g, a, b in g.setValue(11, for: a); g.setValue(21, for: b) } == (32, 2, 2, 2))
    }

    @Test func multi_input_compensating() {
        #expect(runMultiInput { g, a, b in g.setValue(11, for: a); g.setValue(19, for: b) } == (30, 2, 2, 2))
    }

    @Test func multi_input_repeated() {
        #expect(runMultiInput { g, a, _ in g.setValue(11, for: a); g.setValue(12, for: a); g.setValue(13, for: a) } == (33, 2, 1, 2))
    }

    @Test func multi_input_revert() {
        #expect(runMultiInput { g, a, _ in g.setValue(11, for: a); g.setValue(10, for: a) } == (30, 2, 1, 1))
    }

    private func runMultiLevel(_ mutations: [Int]) -> (Int, Int, Int, Int, Int, Int) {
        let graph = Graph()
        let c = MultiCounters()
        let a = graph.makeInput(1)
        let r1 = graph.makeRule { c.r1 += 1; return a.value % 2 }
        let r2 = graph.makeRule { c.r2 += 1; return r1.value * 10 }
        let h = graph.makeRule { c.h += 1; return r2.value + 100 }
        #expect(graph.value(of: h) == 110)
        for m in mutations { graph.setValue(m, for: a) }
        #expect((c.r1, c.r2, c.h) == (1, 1, 1))
        let hv = graph.value(of: h)
        return (graph.value(of: r1), graph.value(of: r2), hv, c.r1, c.r2, c.h)
    }

    @Test func multilevel_positive() {
        #expect(runMultiLevel([2]) == (0, 0, 100, 2, 2, 2))
    }

    @Test func multilevel_cutoff_r1() {
        #expect(runMultiLevel([3]) == (1, 10, 110, 2, 1, 1))
    }

    @Test func multilevel_repeated() {
        #expect(runMultiLevel([2, 3]) == (1, 10, 110, 2, 1, 1))
    }

    @Test func multilevel_revert() {
        #expect(runMultiLevel([2, 1]) == (1, 10, 110, 2, 1, 1))
    }

    @Test func multilevel_intermediate_eval() {
        let graph = Graph()
        let c = MultiCounters()
        let a = graph.makeInput(1)
        let r1 = graph.makeRule { c.r1 += 1; return a.value % 2 }
        let r2 = graph.makeRule { c.r2 += 1; return r1.value * 10 }
        let h = graph.makeRule { c.h += 1; return r2.value + 100 }
        #expect((graph.value(of: h), c.r1, c.r2, c.h) == (110, 1, 1, 1))
        graph.setValue(2, for: a)
        #expect((graph.value(of: h), c.r1, c.r2, c.h) == (100, 2, 2, 2))
        graph.setValue(3, for: a)
        #expect((graph.value(of: h), graph.value(of: r2), graph.value(of: r1), c.r1, c.r2, c.h) == (110, 10, 1, 3, 3, 3))
    }

    // MARK: - 23-30: Diamond & DiamondDynamic

    private func runStaticDiamond(r2First: Bool, mutations: [Int], extraReads: Int = 0) -> (Int, Int, Int, Int, Int, Int) {
        let graph = Graph()
        let s = DiamondState()
        let a = graph.makeInput(1)
        let r1 = graph.makeRule { s.r1 += 1; return a.value * 2 }
        let r2 = graph.makeRule { s.r2 += 1; return a.value * 3 }
        let h = graph.makeRule {
            s.h += 1
            let v1: Int, v2: Int
            if r2First { v2 = r2.value; v1 = r1.value }
            else { v1 = r1.value; v2 = r2.value }
            s.readR1 = v1; s.readR2 = v2
            return v1 + v2
        }
        #expect((graph.value(of: h), s.readR1, s.readR2, s.r1, s.r2, s.h) == (5, 2, 3, 1, 1, 1))
        for m in mutations { graph.setValue(m, for: a) }
        #expect((s.r1, s.r2, s.h) == (1, 1, 1))
        var hv = graph.value(of: h)
        for _ in 0..<extraReads { hv = graph.value(of: h) }
        return (hv, s.readR1, s.readR2, s.r1, s.r2, s.h)
    }

    @Test func diamond_positive() {
        #expect(runStaticDiamond(r2First: false, mutations: [2]) == (10, 4, 6, 2, 2, 2))
    }

    @Test func diamond_accumulated() {
        #expect(runStaticDiamond(r2First: false, mutations: [2, 3]) == (15, 6, 9, 2, 2, 2))
    }

    @Test func diamond_revert() {
        #expect(runStaticDiamond(r2First: false, mutations: [2, 1]) == (5, 2, 3, 2, 2, 1))
    }

    @Test func diamond_repeated_reads() {
        #expect(runStaticDiamond(r2First: false, mutations: [2], extraReads: 2) == (10, 4, 6, 2, 2, 2))
    }

    @Test func diamond_inverse_positive() {
        #expect(runStaticDiamond(r2First: true, mutations: [2]) == (10, 4, 6, 2, 2, 2))
    }

    @Test func diamond_inverse_accumulated() {
        #expect(runStaticDiamond(r2First: true, mutations: [2, 3]) == (15, 6, 9, 2, 2, 2))
    }

    @Test func diamond_inverse_revert() {
        #expect(runStaticDiamond(r2First: true, mutations: [2, 1]) == (5, 2, 3, 2, 2, 1))
    }

    @Test func diamond_dynamic_shared() {
        let graph = Graph()
        let s = DiamondState()
        let a = graph.makeInput(10), b = graph.makeInput(20), sel = graph.makeInput(true)
        let r1 = graph.makeRule { s.r1 += 1; return a.value * 2 }
        let r2 = graph.makeRule {
            s.r2 += 1
            if sel.value { s.r2Branch = "A"; return a.value * 3 }
            else { s.r2Branch = "B"; return b.value * 3 }
        }
        let h = graph.makeRule {
            s.h += 1
            let v1 = r1.value, v2 = r2.value
            s.readR1 = v1; s.readR2 = v2
            return v1 + v2
        }

        func check(_ expected: (Int, Int, Int, Int, Int, Int, String)) {
            #expect((graph.value(of: h), s.readR1, s.readR2) == (expected.0, expected.1, expected.2))
            #expect((s.r1, s.r2, s.h, s.r2Branch) == (expected.3, expected.4, expected.5, expected.6))
        }

        check((50, 20, 30, 1, 1, 1, "A"))
        graph.setValue(11, for: a)
        check((55, 22, 33, 2, 2, 2, "A"))
        graph.setValue(false, for: sel)
        check((82, 22, 60, 2, 3, 3, "B"))
        graph.setValue(12, for: a)
        check((84, 24, 60, 3, 3, 4, "B"))
        graph.setValue(21, for: b)
        check((87, 24, 63, 3, 4, 5, "B"))
        graph.setValue(true, for: sel)
        check((60, 24, 36, 3, 5, 6, "A"))
        graph.setValue(22, for: b)
        check((60, 24, 36, 3, 5, 6, "A"))
        graph.setValue(13, for: a)
        check((65, 26, 39, 4, 6, 7, "A"))
    }

    // MARK: - 31-41: Invalidation & InvalidationDynamic

    private func runBasicInv(_ act: (Graph, Attribute<Int>, Attribute<Int>, Attribute<Int>) -> Void) -> (Int, Int, Int) {
        let graph = Graph()
        let rc = Counter(), hc = Counter()
        let a = graph.makeInput(10)
        let r = graph.makeRule { rc.value += 1; return a.value * 2 }
        let h = graph.makeRule { hc.value += 1; return r.value + 1 }
        #expect(graph.value(of: h) == 21)
        act(graph, a, r, h)
        #expect((rc.value, hc.value) == (1, 1))
        let hv = graph.value(of: h)
        return (hv, rc.value, hc.value)
    }

    @Test func invalidate_control() {
        #expect(runBasicInv { g, a, _, _ in g.setValue(11, for: a) } == (23, 2, 2))
    }

    @Test func invalidate_r() {
        #expect(runBasicInv { g, _, r, _ in g.invalidateValue(of: r) } == (21, 2, 1))
    }

    @Test func invalidate_h() {
        #expect(runBasicInv { g, _, _, h in g.invalidateValue(of: h) } == (21, 1, 2))
    }

    @Test func invalidate_r_twice() {
        #expect(runBasicInv { g, _, r, _ in g.invalidateValue(of: r); g.invalidateValue(of: r) } == (21, 2, 1))
    }

    @Test func invalidate_r_then_mutate_a() {
        #expect(runBasicInv { g, a, r, _ in g.invalidateValue(of: r); g.setValue(11, for: a) } == (23, 2, 2))
    }

    private func makeDynInv() -> (Graph, Attribute<Bool>, Attribute<Int>, Attribute<Int>, Attribute<Int>, Attribute<Int>, DynState) {
        let graph = Graph()
        let s = DynState()
        let sel = graph.makeInput(true), a = graph.makeInput(10), b = graph.makeInput(10)
        let r = graph.makeRule {
            s.rExec += 1
            if sel.value { s.branch = "A"; return a.value }
            else { s.branch = "B"; return b.value }
        }
        let h = graph.makeRule { s.hExec += 1; return r.value + 100 }
        #expect((graph.value(of: h), graph.value(of: r), s.rExec, s.hExec, s.branch) == (110, 10, 1, 1, "A"))
        return (graph, sel, a, b, r, h, s)
    }

    @Test func invalidate_dynamic_control() {
        let (g, _, _, _, r, h, s) = makeDynInv()
        g.invalidateValue(of: r)
        #expect((g.value(of: h), g.value(of: r), s.rExec, s.hExec, s.branch) == (110, 10, 2, 1, "A"))
    }

    @Test func invalidate_dynamic_before_selector() {
        let (g, sel, a, b, r, h, s) = makeDynInv()
        g.invalidateValue(of: r)
        g.setValue(false, for: sel)
        #expect((g.value(of: h), g.value(of: r), s.rExec, s.hExec, s.branch) == (110, 10, 2, 1, "B"))
        g.setValue(11, for: a)
        #expect((g.value(of: h), g.value(of: r), s.rExec, s.hExec, s.branch) == (110, 10, 2, 1, "B"))
        g.setValue(12, for: b)
        #expect((g.value(of: h), g.value(of: r), s.rExec, s.hExec, s.branch) == (112, 12, 3, 2, "B"))
    }

    @Test func invalidate_dynamic_after_selector() {
        let (g, sel, a, b, r, h, s) = makeDynInv()
        g.setValue(false, for: sel)
        g.invalidateValue(of: r)
        #expect((g.value(of: h), g.value(of: r), s.rExec, s.hExec, s.branch) == (110, 10, 2, 1, "B"))
        g.setValue(11, for: a)
        #expect((g.value(of: h), g.value(of: r), s.rExec, s.hExec, s.branch) == (110, 10, 2, 1, "B"))
        g.setValue(12, for: b)
        #expect((g.value(of: h), g.value(of: r), s.rExec, s.hExec, s.branch) == (112, 12, 3, 2, "B"))
    }

    @Test func invalidate_dynamic_twice_before_selector() {
        let (g, sel, a, b, r, h, s) = makeDynInv()
        g.invalidateValue(of: r)
        g.invalidateValue(of: r)
        g.setValue(false, for: sel)
        #expect((g.value(of: h), g.value(of: r), s.rExec, s.hExec, s.branch) == (110, 10, 2, 1, "B"))
        g.setValue(11, for: a)
        #expect((g.value(of: h), g.value(of: r), s.rExec, s.hExec, s.branch) == (110, 10, 2, 1, "B"))
        g.setValue(12, for: b)
        #expect((g.value(of: h), g.value(of: r), s.rExec, s.hExec, s.branch) == (112, 12, 3, 2, "B"))
    }

    @Test func invalidate_dynamic_inactive_a() {
        let (g, sel, a, _, r, h, s) = makeDynInv()
        g.setValue(false, for: sel)
        #expect((g.value(of: h), g.value(of: r), s.rExec, s.hExec, s.branch) == (110, 10, 2, 1, "B"))
        g.invalidateValue(of: r)
        g.setValue(11, for: a)
        #expect((g.value(of: h), g.value(of: r), s.rExec, s.hExec, s.branch) == (110, 10, 3, 1, "B"))
    }

    @Test func invalidate_dynamic_active_b() {
        let (g, sel, _, b, r, h, s) = makeDynInv()
        g.setValue(false, for: sel)
        #expect((g.value(of: h), g.value(of: r), s.rExec, s.hExec, s.branch) == (110, 10, 2, 1, "B"))
        g.invalidateValue(of: r)
        g.setValue(12, for: b)
        #expect((g.value(of: h), g.value(of: r), s.rExec, s.hExec, s.branch) == (112, 12, 3, 2, "B"))
    }

    @Test func oracle1_indirect_set_redirect_reset() {
        let g = Graph()
        let a = g.makeInput(10)
        let bSame = g.makeInput(10)
        let cDiff = g.makeInput(20)
        let ind = g.makeIndirect(a)
        var runs = 0
        let consumer = g.makeRule { runs += 1; return ind.value }

        #expect((g.value(of: consumer), runs) == (10, 1))
        g.setSource(bSame, for: ind)
        #expect((g.value(of: consumer), runs) == (10, 2))
        g.setSource(cDiff, for: ind)
        #expect((g.value(of: consumer), runs) == (20, 3))
        g.resetSource(for: ind)
        #expect((g.value(of: consumer), runs) == (10, 4))
    }

    @Test func oracle2_indirect_a_to_b_to_a() {
        let g = Graph()
        let a = g.makeInput(10)
        let b = g.makeInput(20)
        let ind = g.makeIndirect(a)
        var runs = 0
        let consumer = g.makeRule { runs += 1; return ind.value }

        #expect((g.value(of: consumer), runs) == (10, 1))
        g.setSource(b, for: ind)
        g.resetSource(for: ind)
        #expect((g.value(of: consumer), runs) == (10, 2))
    }

    @Test func oracle3_indirect_chain_two() {
        let g = Graph()
        let a = g.makeInput(10)
        let b = g.makeInput(30)
        let i1 = g.makeIndirect(a)
        let i2 = g.makeIndirect(i1)
        var runs = 0
        let consumer = g.makeRule { runs += 1; return i2.value }

        #expect((g.value(of: consumer), runs) == (10, 1))
        g.setSource(b, for: i1)
        #expect((g.value(of: consumer), runs) == (30, 2))
        g.resetSource(for: i1)
        #expect((g.value(of: consumer), runs) == (10, 3))
    }

    @Test func oracle4_offset_range_inside_outside() {
        struct Pair: BitwiseCopyable, Equatable { var x: Int64; var y: Int64 }
        let g = Graph()
        let src = g.makeInput(Pair(x: 1, y: 10))
        let yOff = MemoryLayout<Pair>.offset(of: \Pair.y)!
        let off = g.makeOffsetIndirect(of: src, offset: yOff, size: MemoryLayout<Int64>.size)
        var runs = 0
        let consumer = g.makeRule { runs += 1; return off.value.y }

        #expect((g.value(of: consumer), runs) == (10, 1))
        g.setValue(Pair(x: 99, y: 10), for: src)
        #expect((g.value(of: consumer), runs) == (10, 1))
        g.setValue(Pair(x: 99, y: 25), for: src)
        #expect((g.value(of: consumer), runs) == (25, 2))
    }

    @Test func oracle5_subgraph_dag_add_child() {
        let g = Graph()
        let p1 = g.makeSubgraph()
        let ctx2 = g.makeSubgraphContext()
        let p2 = g.makeSubgraph(context: ctx2)
        let sameChild = g.makeSubgraph(parent: p1)
        let diffChild = g.makeSubgraph(parent: p2)
        (p1).addChild(diffChild)

        (p1).invalidate()
        #expect(!(sameChild).isValid)
        #expect((diffChild).isValid)
    }

    @Test func oracle6_cooperative_cancellation() {
        let g = Graph()
        let src = g.makeInput(1)
        var cancel = false
        let r = g.makeRule {
            let v = src.value
            if cancel { g.cancelUpdate() }
            return v + 10
        }
        #expect(g.value(of: r) == 11)
        cancel = true
        g.setValue(2, for: src)
        // NativeProbe `cooperative-cancel` measured that a cancelled rule writes its returned value (12) while staying dirty.
        #expect(g.value(of: r) == 12)
        cancel = false
        #expect(g.value(of: r) == 12)
    }

    @Test func oracle7_context_update_callback() {
        let g = Graph()
        let ctx = g.makeContext()
        var coalescedCalls = 0
        ctx.setUpdateCallback { coalescedCalls += 1 }
        g.withBatch {
            ctx.setNeedsUpdate()
            ctx.setNeedsUpdate()
        }
        #expect(coalescedCalls == 1)

        // NativeProbe `context-update-callback` measured `before=0|after=1|reentrant=3`:
        // `setNeedsUpdate` defers and coalesces until a read/update drains callbacks.
        let dummy = g.makeRule { 0 }   // a rule: reading an input drains nothing (shared-context-input-read [O])
        var samePassDrain = 0
        ctx.setUpdateCallback {
            samePassDrain += 1
            if samePassDrain == 1 { ctx.setNeedsUpdate() }
        }
        ctx.setNeedsUpdate()
        #expect(samePassDrain == 0)
        _ = g.value(of: dummy)
        #expect(samePassDrain == 2)
    }

    @Test func oracle8_offset_zero_full_and_size_zero() {
        struct Pair: BitwiseCopyable, Equatable { var x: Int64; var y: Int64 }
        let g = Graph()
        let src = g.makeInput(Pair(x: 1, y: 2))
        let full = g.makeOffsetIndirect(of: src, offset: 0, size: MemoryLayout<Pair>.size)
        let zero = g.makeOffsetIndirect(of: src, offset: 0, size: 0)

        var fullRuns = 0
        let fullC = g.makeRule { fullRuns += 1; return full.value.x }
        var zeroRuns = 0
        let zeroC = g.makeRule { zeroRuns += 1; return zero.value.x }

        #expect((g.value(of: fullC), fullRuns) == (1, 1))
        #expect((g.value(of: zeroC), zeroRuns) == (1, 1))

        g.setValue(Pair(x: 3, y: 4), for: src)
        #expect((g.value(of: fullC), fullRuns) == (3, 2))
        #expect((g.value(of: zeroC), zeroRuns) == (1, 1))
    }

    @Test func oracle9_offset_sticky_inside_then_outside() {
        struct Pair: BitwiseCopyable, Equatable { var x: Int64; var y: Int64 }
        let g = Graph()
        let src = g.makeInput(Pair(x: 1, y: 10))
        let yOff = MemoryLayout<Pair>.offset(of: \Pair.y)!
        let off = g.makeOffsetIndirect(of: src, offset: yOff, size: MemoryLayout<Int64>.size)

        var runs = 0
        let consumer = g.makeRule { runs += 1; return off.value.y }
        #expect((g.value(of: consumer), runs) == (10, 1))

        // Inside range (`y: 20`), then back to `y: 10` before evaluating consumer -> sticky changed.
        g.setValue(Pair(x: 1, y: 20), for: src)
        g.setValue(Pair(x: 1, y: 10), for: src)
        #expect((g.value(of: consumer), runs) == (10, 2))
    }

    @Test func oracle10_mixed_chain_source_offset_indirect_consumer() {
        struct Pair: BitwiseCopyable, Equatable { var x: Int64; var y: Int64 }
        let g = Graph()
        let src = g.makeInput(Pair(x: 1, y: 10))
        let yOff = MemoryLayout<Pair>.offset(of: \Pair.y)!
        let off = g.makeOffsetIndirect(of: src, offset: yOff, size: MemoryLayout<Int64>.size)
        let ind = g.makeIndirect(off)

        var runs = 0
        let consumer = g.makeRule { runs += 1; return ind.value.y }
        #expect((g.value(of: consumer), runs) == (10, 1))

        g.setValue(Pair(x: 99, y: 10), for: src)
        #expect((g.value(of: consumer), runs) == (10, 1))

        g.setValue(Pair(x: 99, y: 25), for: src)
        #expect((g.value(of: consumer), runs) == (25, 2))
    }

    @Test func oracle11_direct_edge_without_offset() {
        let g = Graph()
        let src = g.makeInput(10)
        var runs = 0
        let consumer = g.makeRule { runs += 1; return src.value }

        #expect((g.value(of: consumer), runs) == (10, 1))
        g.setValue(10, for: src)
        #expect((g.value(of: consumer), runs) == (10, 1))
        g.setValue(20, for: src)
        #expect((g.value(of: consumer), runs) == (20, 2))
    }

    @Test func oracle12_weak_attribute_alive_and_after_invalidate() {
        let g = Graph()
        let sg = g.makeSubgraph()
        let attr = g.withCurrent(sg) { g.makeInput(42) }
        let weak = WeakAttribute(attr)

        #expect(g.value(of: weak) == 42)
        (sg).invalidate()
        #expect(g.value(of: weak) == nil)
    }
}
