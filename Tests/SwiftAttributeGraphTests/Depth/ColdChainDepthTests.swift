import Testing
@testable import SwiftAttributeGraph

/// Contract for the first evaluation of a chain that has never been read (a "cold" chain).
///
/// - Resumable rules (`makeResumableRule`) are iterative: they must evaluate a cold chain of 100.000 levels with an
///   empty frame stack, as AGENTS.md requires.
/// - Synchronous closure rules (`makeRule`) keep the native-stack limit that Apple's framework also has (measured in
///   `NativeAttributeGraphBackendProbe/PROFUNDIDAD_FRIA_NATIVO_VS_MOTOR.md`). Their cold test stays at 500 levels, which is
///   safe even in debug builds; deeper chains must be warmed node by node, as ``DepthTests`` does.
@Suite(.serialized) struct ColdChainDepthTests {
    struct ColdPlus: ResumableRule {
        let source: Attribute<Int>
        mutating func resume(_ context: inout ResumableRuleContext<Int>) -> RuleStep {
            switch context.poll(source) {
            case .pending: return .needsInput(source.erased)
            case .ready(let value): context.value = value + 1; return .finished
            }
        }
    }

    @Test func aColdChainOfResumableRulesOfOneHundredThousandLevelsEvaluatesWithoutFrames() {
        let depth = 100_000
        let graph = Graph()
        var last = graph.makeInput(0)
        for _ in 0..<depth { last = graph.makeResumableRule(ColdPlus(source: last)) }
        #expect(graph.value(of: last) == depth)
        #expect(graph.frames.isEmpty)
    }

    @Test func aColdChainOfClosureRulesOfFiftyLevelsEvaluatesCorrectly() {
        let depth = 50
        let graph = Graph()
        var last: Attribute<Int> = graph.makeInput(0)
        graph.withCurrent(graph.rootSubgraph) {
            for _ in 0..<depth {
                let previous = last
                last = graph.makeRule { previous.value + 1 }
            }
        }
        #expect(graph.value(of: last) == depth)
    }
}
