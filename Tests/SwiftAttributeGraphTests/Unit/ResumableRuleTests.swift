import Testing
@testable import SwiftAttributeGraph

@Suite struct ResumableRuleTests {
    final class Counter {
        var starts = 0
        var steps = 0
        let thread = currentThreadToken()
    }
    struct PlusOne: ResumableRule {
        let source: Attribute<Int>
        let counter: Counter
        mutating func resume(_ context: inout ResumableRuleContext<Int>) -> RuleStep {
            precondition(currentThreadToken() == counter.thread)
            counter.steps += 1
            if context.isFirstStep { counter.starts += 1 }
            switch context.poll(source) {
            case .pending: return .needsInput(source.erased)
            case .ready(let value): context.value = value + 1; return .finished
            }
        }
    }

    func checkChain(_ depth: Int) {
        let graph = Graph()
        let counter = Counter()
        let root = graph.makeInput(0)
        var last = root
        for _ in 0..<depth { last = graph.makeResumableRule(PlusOne(source: last, counter: counter)) }
        #expect(counter.starts == 0)
        #expect(graph.value(of: last) == depth)
        #expect(counter.starts == depth)
        #expect(graph.frames.isEmpty)
        graph.setValue(1, for: root)
        #expect(graph.value(of: last) == depth + 1)
        #expect(counter.starts == depth * 2 && graph.frames.isEmpty)
    }

    @Test func twentyThousandColdRulesRunOnTheOriginalThread() { checkChain(20_000) }
    @Test func oneHundredThousandColdRulesRunOnTheOriginalThread() { checkChain(100_000) }

    struct Accumulate: ResumableRule {
        let source: Attribute<Int>
        static var initialValue: Int? { 0 }
        mutating func resume(_ context: inout ResumableRuleContext<Int>) -> RuleStep {
            switch context.poll(source) {
            case .pending: return .needsInput(source.erased)
            case .ready(let value):
                if context.hasChanged(source) { context.value += value }
                return .finished
            }
        }
    }

    @Test func twentyThousandColdStatefulRulesAccumulateAfterSuspending() {
        let graph = Graph()
        let root = graph.makeInput(1)
        var last = root
        for _ in 0..<20_000 { last = graph.makeResumableRule(Accumulate(source: last)) }
        #expect(graph.value(of: last) == 1)
        graph.setValue(2, for: root)
        #expect(graph.value(of: last) == 20_002)
        #expect(graph.frames.isEmpty)
    }

    struct Choose: ResumableRule {
        let flag: Attribute<Bool>
        let left: Attribute<Int>
        let right: Attribute<Int>
        let counter: Counter
        var selected: Attribute<Int>?
        mutating func resume(_ context: inout ResumableRuleContext<Int>) -> RuleStep {
            if context.isFirstStep { counter.starts += 1; selected = nil }
            counter.steps += 1
            if selected == nil {
                switch context.poll(flag) {
                case .pending: return .needsInput(flag.erased)
                case .ready(let flag): selected = flag ? left : right
                }
            }
            let source = selected!
            switch context.poll(source) {
            case .pending: return .needsInput(source.erased)
            case .ready(let value): context.value = value; return .finished
            }
        }
    }

    @Test func conditionalSuspensionPrunesAndDoesNotReplayEffects() {
        let graph = Graph()
        let flag = graph.makeInput(true), a = graph.makeInput(10), b = graph.makeInput(20)
        let left = graph.makeResumableRule(PlusOne(source: a, counter: .init()))
        let right = graph.makeResumableRule(PlusOne(source: b, counter: .init()))
        let counter = Counter()
        let result = graph.makeResumableRule(Choose(flag: flag, left: left, right: right, counter: counter))
        #expect(graph.value(of: result) == 11)
        #expect(counter.starts == 1 && counter.steps == 2)
        #expect(graph.inputs(of: result.id) == [flag.id, left.id])
        graph.setValue(false, for: flag)
        #expect(graph.value(of: result) == 21)
        #expect(counter.starts == 2 && counter.steps == 4)
        #expect(graph.inputs(of: result.id) == [flag.id, right.id])
        graph.setValue(100, for: a)
        #expect(!graph.isDirty(result.id))
    }

    struct Copy<T>: ResumableRule {
        let source: Attribute<T>
        mutating func resume(_ context: inout ResumableRuleContext<T>) -> RuleStep {
            switch context.poll(source) {
            case .pending: return .needsInput(source.erased)
            case .ready(let value): context.value = value; return .finished
            }
        }
    }

    @Test func comparisonPoliciesApplyToInitialAndSubsequentWrites() {
        for (policy, changes) in [(Comparison.stateWrite, false), (.viewValue, true),
                                  (.environment, false), (.bits, true), (.alwaysDifferent, true)] {
            let graph = Graph()
            let source = graph.makeInput(0.0)
            let result = graph.makeResumableRule(Copy(source: source), comparison: policy)
            _ = graph.value(of: result)
            let version = graph.version(of: result.id)
            graph.setValue(-0.0, for: source)
            _ = graph.value(of: result)
            #expect((graph.version(of: result.id) != version) == changes)
        }
        for (policy, changes) in [(Comparison.stateWrite, true), (.viewValue, false),
                                  (.environment, false), (.bits, false), (.alwaysDifferent, true)] {
            let graph = Graph()
            let source = graph.makeInput(Double.nan, comparison: .alwaysDifferent)
            let result = graph.makeResumableRule(Copy(source: source), comparison: policy)
            _ = graph.value(of: result)
            let version = graph.version(of: result.id)
            graph.setValue(Double.nan, for: source)
            _ = graph.value(of: result)
            #expect((graph.version(of: result.id) != version) == changes)
        }
    }

    @Test func optionalNilIsAReadyValueAndDynamicExistentialsUseM2() {
        let graph = Graph()
        let optional = graph.makeInput(nil as Int?)
        let first = graph.makeResumableRule(Copy(source: optional))
        let last = graph.makeResumableRule(Copy(source: first))
        #expect(graph.value(of: last) == nil)
        let source = graph.makeInput(1 as Any, comparison: .alwaysDifferent)
        let copy = graph.makeResumableRule(Copy(source: source))
        _ = graph.value(of: copy)
        let version = graph.version(of: copy.id)
        graph.setValue(1 as Any, for: source)
        _ = graph.value(of: copy)
        #expect(graph.version(of: copy.id) == version)
    }

    final class Saved { var context: ResumableRuleContext<Int>? }
    struct Save: ResumableRule {
        let source: Attribute<Int>
        let saved: Saved
        var previousRun = false
        mutating func resume(_ context: inout ResumableRuleContext<Int>) -> RuleStep {
            switch context.poll(source) {
            case .pending: return .needsInput(source.erased)
            case .ready(let value):
                if previousRun { _ = saved.context!.hasValue }
                saved.context = context
                previousRun = true
                context.value = value
                return .finished
            }
        }
    }

    @Test func aSavedContextDoesNotReviveInAnotherEvaluation() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            let source = graph.makeInput(0)
            let rule = graph.makeResumableRule(Save(source: source, saved: .init()))
            _ = graph.value(of: rule)
            graph.setValue(1, for: source)
            _ = graph.value(of: rule)
        }
    }

    @Test func savedContextsDoNotRetainTheGraphAndFailAfterItDies() async {
        await #expect(processExitsWith: .failure) {
            let saved = Saved()
            do {
                let graph = Graph()
                let source = graph.makeInput(0)
                _ = graph.value(of: graph.makeResumableRule(Save(source: source, saved: saved)))
            }
            _ = saved.context!.hasValue
        }
    }

    @Test func savedContextsDoNotRetainTheirGraph() {
        let saved = Saved()
        weak var weakGraph: Graph?
        do {
            let graph = Graph()
            weakGraph = graph
            let source = graph.makeInput(0)
            _ = graph.value(of: graph.makeResumableRule(Save(source: source, saved: saved)))
        }
        #expect(weakGraph == nil && saved.context != nil)
    }

    struct Invalidate: ResumableRule {
        weak var graph: Graph?
        let owner: Subgraph
        let source: Attribute<Int>
        mutating func resume(_ context: inout ResumableRuleContext<Int>) -> RuleStep {
            if context.isFirstStep { graph!.invalidate(owner) }
            switch context.poll(source) {
            case .pending: return .needsInput(source.erased)
            case .ready(let value): context.value = value; return .finished
            }
        }
    }

    @Test func selfInvalidationWaitsForTheReadAndKeepsHierarchicalNotices() {
        let graph = Graph()
        let owner = graph.makeSubgraph(), child = graph.makeSubgraph(parent: owner)
        let counter = Counter()
        let rule = graph.withCurrent(child) {
            let input = graph.makeInput(4)
            let source = graph.makeResumableRule(PlusOne(source: input, counter: counter))
            return graph.makeResumableRule(Invalidate(graph: graph, owner: owner, source: source))
        }
        var notices: [String] = []
        graph.observe(child) { notices.append("child") }
        graph.observe(owner) { notices.append("parent") }
        #expect(graph.value(of: rule) == 5)
        #expect(notices == ["child", "parent"])
        #expect(graph.nodeCount == 0 && graph.liveSubgraphCount == 1 && graph.frames.isEmpty)
    }

    @Test func deepRuleStateIsReleasedWithItsSubgraph() {
        let graph = Graph()
        let owner = graph.makeSubgraph()
        weak var weakCounter: Counter?
        graph.withCurrent(owner) {
            let counter = Counter()
            weakCounter = counter
            var last = graph.makeInput(0)
            for _ in 0..<20_000 { last = graph.makeResumableRule(PlusOne(source: last, counter: counter)) }
            #expect(graph.value(of: last) == 20_000)
        }
        graph.invalidate(owner)
        #expect(weakCounter == nil && graph.nodeCount == 0 && graph.liveSubgraphCount == 1)
    }
}
