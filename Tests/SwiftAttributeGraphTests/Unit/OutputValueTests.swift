import Testing
@testable import SwiftAttributeGraph

/// `Graph.outputValue()` and `Graph.setOutputValue(_:)`: they read and write the value of the attribute that is evaluating.
/// Native lines measured on macOS 15.8.3 by oracle scenarios `o1` to `o11` (in the comments).
@Suite struct OutputValueTests {
    final class Probe { var attrRuns = 0; var rRuns = 0; var peeks: [Int?] = [] }

    private func put<V>(_ value: V) { var v = value; withUnsafePointer(to: &v) { Graph.setOutputValue($0) } }
    private func peek<V>(_: V.Type = V.self) -> V? {
        let pointer: UnsafePointer<V>? = Graph.outputValue()
        return pointer?.pointee
    }

    /// An attribute and a downstream rule R that reads it and multiplies by 10.
    private func make(_ graph: Graph, _ probe: Probe, comparison: ValuePolicy = .viewValue,
                      body: @escaping (inout RuleContext<Int>) -> Void) -> (a: Attribute<Int>, r: Attribute<Int>) {
        let sg = graph.makeSubgraph()
        return graph.withCurrent(sg) {
            let a = graph.makeStatefulRule(comparison: comparison) { (ctx: inout RuleContext<Int>) in probe.attrRuns += 1; body(&ctx) }
            let r = graph.makeRule { probe.rRuns += 1; return a.value * 10 }
            return (a, r)
        }
    }

    @Test func theOutputIsNilBeforeTheFirstWriteAndHoldsTheWriteAfter() { // o1 [5, 1, true, 5]
        let graph = Graph(); let p = Probe()
        let (a, _) = make(graph, p) { _ in
            p.peeks.append(peek(Int.self)); put(5); p.peeks.append(peek(Int.self))
        }
        #expect(graph.value(of: a) == 5)
        #expect(p.attrRuns == 1)
        #expect(p.peeks == [nil, 5])
    }

    @Test func theSecondRunSeesThePreviousValue() { // o2 [5, 10, 2, nil, Optional(5)]
        let graph = Graph(); let p = Probe()
        let sg = graph.makeSubgraph()
        let input = graph.withCurrent(sg) { graph.makeInput(5) }
        let a = graph.withCurrent(sg) {
            graph.makeStatefulRule { (_: inout RuleContext<Int>) in
                p.attrRuns += 1; p.peeks.append(peek(Int.self)); put(input.value)
            }
        }
        #expect(graph.value(of: a) == 5)
        graph.setValue(10, for: input)
        #expect(graph.value(of: a) == 10)
        #expect(p.attrRuns == 2)
        #expect(p.peeks == [nil, 5])
    }

    @Test func writingTheSameValueTwiceInABodyIsOneChange() { // o3 [5, 50, 50, 1, 1]
        let graph = Graph(); let p = Probe()
        let (a, r) = make(graph, p) { _ in put(5); put(5) }
        #expect(graph.value(of: a) == 5)
        #expect(graph.value(of: r) == 50)
        #expect(graph.value(of: r) == 50)
        #expect(p.attrRuns == 1); #expect(p.rRuns == 1)
    }

    @Test func theSameValueInANewRunDoesNotRunTheDownstreamRule() { // o4 [50, 50, 2, 1]
        let graph = Graph(); let p = Probe()
        let sg = graph.makeSubgraph()
        let input = graph.withCurrent(sg) { graph.makeInput(0) }
        let (a, r) = graph.withCurrent(sg) { () -> (Attribute<Int>, Attribute<Int>) in
            let a = graph.makeStatefulRule { (_: inout RuleContext<Int>) in p.attrRuns += 1; _ = input.value; put(5) }
            return (a, graph.makeRule { p.rRuns += 1; return a.value * 10 })
        }
        _ = a
        #expect(graph.value(of: r) == 50)
        graph.setValue(1, for: input)
        #expect(graph.value(of: r) == 50)
        #expect(p.attrRuns == 2); #expect(p.rRuns == 1)
    }

    @Test func theLastWriteWins() { // o5 [6, 60, 1, 1]
        let graph = Graph(); let p = Probe()
        let (a, r) = make(graph, p) { _ in put(5); put(6) }
        #expect(graph.value(of: a) == 6)
        #expect(graph.value(of: r) == 60)
        #expect(p.attrRuns == 1); #expect(p.rRuns == 1)
    }

    struct SetsThenReturns: Rule {
        var value: Int { Graph.setOutputValueForTest(5); return 9 }
    }

    @Test func aRulesReturnOverridesAnEarlierWrite() { // o6 [9, 1]
        let graph = Graph()
        let sg = graph.makeSubgraph()
        let a = graph.withCurrent(sg) { graph.makeRule(SetsThenReturns()) }
        #expect(graph.value(of: a) == 9)
    }

    @Test func aWriteOutsideAnUpdateStopsTheProgram() async { // o7b
        await #expect(processExitsWith: .failure) {
            var v = 1
            withUnsafePointer(to: &v) { Graph.setOutputValue($0) }
        }
    }

    @Test func aReadOutsideAnUpdateStopsTheProgram() async { // o7a
        await #expect(processExitsWith: .failure) { _ = Graph.outputValue() as UnsafePointer<Int>? }
    }

    @Test func aWriteOfTheWrongTypeStopsTheProgram() async { // o8 "invalid value type for attribute: ... (saw Int, expected String)"
        await #expect(processExitsWith: .failure) {
            let graph = Graph(); let sg = graph.makeSubgraph()
            let a = graph.withCurrent(sg) {
                graph.makeStatefulRule { (_: inout RuleContext<Int>) in
                    var s = "x"; withUnsafePointer(to: &s) { Graph.setOutputValue($0) }
                }
            }
            _ = graph.value(of: a)
        }
    }

    @Test func insideANestedRuleTheOutputIsThatRulesOwn() { // o9 [120, 20, true, 20, 100]
        let graph = Graph(); let sg = graph.makeSubgraph()
        var bPeeks: [Int?] = [], aPeeks: [Int?] = []
        let (a, b) = graph.withCurrent(sg) { () -> (Attribute<Int>, Attribute<Int>) in
            let b = graph.makeStatefulRule { (_: inout RuleContext<Int>) in
                bPeeks.append(peek(Int.self)); put(20); bPeeks.append(peek(Int.self))
            }
            let a = graph.makeStatefulRule { (_: inout RuleContext<Int>) in
                let bv = b.value
                put(bv + 100); aPeeks.append(peek(Int.self))
            }
            return (a, b)
        }
        #expect(graph.value(of: a) == 120)
        #expect(graph.value(of: b) == 20)
        #expect(bPeeks == [nil, 20])
        #expect(aPeeks == [120])
    }

    @Test func aWriteStaysWhenTheBodyReadsSomethingThatChanges() { // o10 [5, 50, 50, 2, 1]
        let graph = Graph(); let p = Probe()
        let sg = graph.makeSubgraph()
        let c = graph.withCurrent(sg) { graph.makeInput(0) }
        let (a, r) = graph.withCurrent(sg) { () -> (Attribute<Int>, Attribute<Int>) in
            let a = graph.makeStatefulRule { (_: inout RuleContext<Int>) in p.attrRuns += 1; _ = c.value; put(5) }
            return (a, graph.makeRule { p.rRuns += 1; return a.value * 10 })
        }
        #expect(graph.value(of: a) == 5); #expect(graph.value(of: r) == 50)
        graph.setValue(1, for: c)
        #expect(graph.value(of: a) == 5); #expect(graph.value(of: r) == 50)
        #expect(p.attrRuns == 2); #expect(p.rRuns == 1)
    }

    struct Tagged: Equatable {
        let id: Int
        let tag: Int
        static func == (l: Tagged, r: Tagged) -> Bool { l.id == r.id }
    }

    @Test func anEqualValueByBitsDoesNotRunTheDownstreamRule() { // o11a [16, 16, 2, 1]
        let graph = Graph(); let p = Probe()
        let sg = graph.makeSubgraph()
        let input = graph.withCurrent(sg) { graph.makeInput(0) }
        let (a, r) = graph.withCurrent(sg) { () -> (Attribute<Tagged>, Attribute<Int>) in
            let a = graph.makeStatefulRule(comparison: .bits) { (_: inout RuleContext<Tagged>) in
                p.attrRuns += 1; _ = input.value; put(Tagged(id: 1, tag: 1))
            }
            return (a, graph.makeRule { p.rRuns += 1; return a.value.id * 16 })
        }
        _ = a
        #expect(graph.value(of: r) == 16)
        graph.setValue(1, for: input)
        #expect(graph.value(of: r) == 16)
        #expect(p.attrRuns == 2); #expect(p.rRuns == 1)
    }

    @Test func aValueEqualByEqualsButNotByBitsRunsTheDownstreamRule() { // o11b [1, 1, 2, 2]
        let graph = Graph(); let p = Probe()
        let sg = graph.makeSubgraph()
        let input = graph.withCurrent(sg) { graph.makeInput(0) }
        let (a, r) = graph.withCurrent(sg) { () -> (Attribute<Tagged>, Attribute<Int>) in
            let a = graph.makeStatefulRule(comparison: .bits) { (_: inout RuleContext<Tagged>) in
                p.attrRuns += 1; put(Tagged(id: 1, tag: input.value))
            }
            return (a, graph.makeRule { p.rRuns += 1; return a.value.id })
        }
        _ = a
        #expect(graph.value(of: r) == 1)
        graph.setValue(1, for: input)
        #expect(graph.value(of: r) == 1)
        #expect(p.attrRuns == 2); #expect(p.rRuns == 2)
    }
}

extension Graph {
    /// Test helper: writes the output value of the attribute that is evaluating.
    static func setOutputValueForTest(_ value: Int) {
        var v = value
        withUnsafePointer(to: &v) { Graph.setOutputValue($0) }
    }
}
