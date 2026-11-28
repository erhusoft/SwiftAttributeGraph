import Testing
@testable import SwiftAttributeGraph

/// `makeInput` and the closure form of `makeRule` build their node in the caller's specialization, and a closure rule
/// stores its result through a function built there too. These tests pin down that the comparison policy, the change
/// cut and the value itself behave the same for trivial, reference-counted and generic (unspecialized) callers.
@Suite struct SpecializedNodePathTests {
    private final class Token {
        let id: Int
        init(_ id: Int) { self.id = id }
    }

    @Test func aClosureRuleThatComputesAnEqualValueCutsItsReaders() {
        let graph = Graph()
        let input = graph.makeInput(Int64(1))
        let parity = graph.makeRule { graph.value(of: input) % 2 }
        var readerRuns = 0
        let reader = graph.makeRule { readerRuns += 1; return graph.value(of: parity) * 10 }
        #expect(graph.value(of: reader) == 10)

        graph.setValue(3, for: input)

        #expect(graph.value(of: reader) == 10)
        #expect(readerRuns == 1)
    }

    @Test func alwaysDifferentRulesAndInputsDoNotCut() {
        let graph = Graph()
        let input = graph.makeInput(Int64(5), comparison: .alwaysDifferent)
        let rule = graph.makeRule({ graph.value(of: input) }, comparison: .alwaysDifferent)
        var readerRuns = 0
        let reader = graph.makeRule { readerRuns += 1; return graph.value(of: rule) }
        _ = graph.value(of: reader)

        graph.setValue(5, for: input)

        #expect(graph.value(of: reader) == 5)
        #expect(readerRuns == 2)
    }

    @Test func referenceCountedValuesKeepTheirIdentityAndDieWithTheGraph() {
        weak var weakToken: Token?
        do {
            let graph = Graph()
            let token = Token(7)
            weakToken = token
            let input = graph.makeInput(token)
            let names = graph.makeRule { "item-\(graph.value(of: input).id)" }
            let same = graph.makeRule { graph.value(of: input) }
            #expect(graph.value(of: names) == "item-7")
            #expect(graph.value(of: same) === token)

            graph.setValue(Token(8), for: input)

            #expect(graph.value(of: names) == "item-8")
            #expect(graph.value(of: same).id == 8)
        }
        #expect(weakToken == nil)
    }

    @Test func writesThroughTheFastAndTheSlowPathBehaveTheSame() {
        struct Point: BitwiseCopyable, Equatable { var x: Int64; var y: Int64 }
        let graph = Graph()
        let plain = graph.makeInput(Int64(1))
        let target = graph.makeInput(Int64(10))
        let indirect = graph.makeIndirect(target)
        var runs = 0
        let sum = graph.makeRule { runs += 1; return graph.value(of: plain) + graph.value(of: indirect) }
        #expect(graph.value(of: sum) == 11)

        graph.setValue(1, for: plain)                       // equal: cut, nothing reruns
        #expect(graph.value(of: sum) == 11 && runs == 1)
        graph.setValue(20, for: indirect)                   // through the indirect, to its source
        #expect(graph.value(of: target) == 20)
        #expect(graph.value(of: sum) == 21 && runs == 2)

        // An offset attribute switches the graph to the partial-compare path for every later write.
        let point = graph.makeInput(Point(x: 1, y: 2))
        let y = graph.makeOffsetFieldAttribute(of: point, keyPath: \Point.y)
        var yRuns = 0
        let readsY = graph.makeRule { yRuns += 1; return graph.value(of: y) }
        #expect(graph.value(of: readsY) == 2)
        graph.setValue(Point(x: 5, y: 2), for: point)       // only x changed: the reader of y is cut
        #expect(graph.value(of: readsY) == 2 && yRuns == 1)
        graph.setValue(3, for: plain)
        #expect(graph.value(of: sum) == 23 && runs == 3)
    }

    @Test func aWriteToARuleThatReadAnInputStillStopsTheProgram() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            let input = graph.makeInput(Int64(1))
            let rule = graph.makeRule { graph.value(of: input) }
            _ = graph.value(of: rule)
            graph.setValue(2, for: rule)
        }
    }

    @Test func aWriteFromInsideARuleStillStopsTheProgram() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            let input = graph.makeInput(Int64(1))
            let rule = graph.makeRule { graph.setValue(2, for: input); return Int64(1) }
            _ = graph.value(of: rule)
        }
    }

    @Test func alternatingTypesAndPoliciesEachKeepTheirOwnComparison() {
        let graph = Graph()
        var plain: [Attribute<Int>] = []
        var always: [Attribute<Int>] = []
        for i in 0..<3 {
            plain.append(graph.makeInput(i))
            _ = graph.makeInput("s\(i)")
            always.append(graph.makeInput(i, comparison: .alwaysDifferent))
            _ = graph.makeInput(Double(i))
        }
        var runs = 0
        let reader = graph.makeRule { runs += 1; return graph.value(of: plain[1]) + graph.value(of: always[1]) }
        _ = graph.value(of: reader)
        graph.setValue(1, for: plain[1])                    // equal under the default policy: cut
        #expect(graph.value(of: reader) == 2 && runs == 1)
        graph.setValue(1, for: always[1])                   // equal, but always different: reruns
        #expect(graph.value(of: reader) == 2 && runs == 2)
    }

    @Test func anUnspecializedGenericCallerBuildsTheSameNodes() {
        @inline(never)
        func build<V>(_ graph: Graph, _ value: V, _ transform: @escaping (V) -> V) -> (Attribute<V>, Attribute<V>) {
            let input = graph.makeInput(value)
            return (input, graph.makeRule { transform(graph.value(of: input)) })
        }
        let graph = Graph()
        let (input, rule) = build(graph, [1, 2], { $0 + [3] })
        #expect(graph.value(of: rule) == [1, 2, 3])

        graph.setValue([4], for: input)

        #expect(graph.value(of: rule) == [4, 3])
    }

    private struct ParityRule: Rule {
        var source: Attribute<Int64>
        var modulo: Int64 = 2
        var value: Int64 { source.value % modulo }
    }

    @Test func aTypeRuleAndMapAndFocusCutReadersAndSupportMutateBody() {
        struct Pair: Equatable { var a: Int64; var b: Int64 }
        let graph = Graph()
        let input = graph.makeInput(Int64(1))
        let typeRule = graph.makeRule(ParityRule(source: input))
        var readerRuns = 0
        let reader = graph.makeRule { readerRuns += 1; return typeRule.value * 10 }
        #expect(graph.value(of: reader) == 10 && readerRuns == 1)

        graph.setValue(3, for: input)
        #expect(graph.value(of: reader) == 10 && readerRuns == 1)

        graph.mutateBody(of: typeRule, as: ParityRule.self, invalidating: true) { $0.modulo = 4 }
        #expect(graph.value(of: reader) == 30 && readerRuns == 2)

        let pair = graph.makeInput(Pair(a: 2, b: 9))
        let focused = graph.makeFocus(pair, keyPath: \Pair.a)
        let mapped = graph.makeMap(focused) { $0 % 2 }
        var mapReaderRuns = 0
        let mapReader = graph.makeRule { mapReaderRuns += 1; return mapped.value }
        #expect(graph.value(of: mapReader) == 0 && mapReaderRuns == 1)

        graph.setValue(Pair(a: 4, b: 99), for: pair)
        #expect(graph.value(of: mapReader) == 0 && mapReaderRuns == 1)
    }
}
