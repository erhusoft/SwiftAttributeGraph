import Testing
@testable import SwiftAttributeGraph

@Suite struct IndirectDepthTests {
    struct Copy: ResumableRule {
        let source: Attribute<Int>
        mutating func resume(_ context: inout ResumableRuleContext<Int>) -> RuleStep {
            switch context.poll(source) {
            case .pending: return .needsInput(source.erased)
            case .ready(let value):
                if context.hasChanged(source) { context.value = value }
                return .finished
            }
        }
    }
    @Test func statefulChangeQueriesFollowTheSourceVersion() {
        let graph = Graph()
        let source = graph.makeInput(1)
        let alias = graph.makeIndirect(source)
        let sum = graph.makeStatefulRule(initialValue: 0) { (context: inout RuleContext<Int>) in
            let value = alias.value
            if context.hasChanged(alias) { context.value += value }
        }
        #expect(graph.value(of: sum) == 1)
        graph.setValue(2, for: source)
        #expect(graph.value(of: sum) == 3)
    }
    @Test func anIndirectIsMarkedAsSuch() {
        let graph = Graph()
        let alias = graph.makeIndirect(graph.makeInput(1))
        #expect(graph.table.state[Int(alias.id.index)] & NodeState.indirect != 0)
    }
    @Test func twentyThousandRedirectsReadWriteTrackAndRelease() {
        let graph = Graph()
        let owner = graph.makeSubgraph()
        graph.withCurrent(owner) {
            let source = graph.makeInput(1)
            var last = source
            for _ in 0..<20_000 { last = graph.makeIndirect(last) }
            #expect(graph.value(of: last) == 1)
            graph.setValue(2, for: last)
            #expect(graph.value(of: source) == 2)
            let rule = graph.makeResumableRule(Copy(source: last))
            #expect(graph.value(of: rule) == 2)
            graph.setValue(3, for: source)
            #expect(graph.value(of: rule) == 3)
        }
        graph.invalidate(owner)
        #expect(graph.nodeCount == 0)
    }
}
