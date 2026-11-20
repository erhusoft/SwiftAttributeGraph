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
}
