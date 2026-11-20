import Testing
@testable import SwiftAttributeGraph

@Suite struct ResumableStateTests {
    struct LazyInitial: ResumableRule {
        nonisolated(unsafe) static var initialReads = 0
        let tick: Attribute<Int>
        static var initialValue: Int? { initialReads += 1; return 7 }
        mutating func resume(_ context: inout ResumableRuleContext<Int>) -> RuleStep {
            switch context.poll(tick) {
            case .pending: return .needsInput(tick.erased)
            case .ready(let value): context.value += value; return .finished
            }
        }
    }
    @Test func initialValueIsResolvedLazilyAndOnlyOnce() {
        LazyInitial.initialReads = 0
        let graph = Graph()
        let tick = graph.makeInput(0)
        let rule = graph.makeResumableRule(LazyInitial(tick: tick))
        #expect(LazyInitial.initialReads == 0)
        #expect(graph.value(of: rule) == 7 && LazyInitial.initialReads == 1)
        graph.setValue(1, for: tick)
        #expect(graph.value(of: rule) == 8 && LazyInitial.initialReads == 1)
    }

    struct WriteBeforeWait: ResumableRule {
        let source: Attribute<Int>
        let counter: ResumableRuleTests.Counter
        static var initialValue: Int? { 10 }
        mutating func resume(_ context: inout ResumableRuleContext<Int>) -> RuleStep {
            if context.isFirstStep { context.value += 1; counter.starts += 1 }
            switch context.poll(source) {
            case .pending: return .needsInput(source.erased)
            case .ready(let value): context.value += value; return .finished
            }
        }
    }
    @Test func proposedWritesSurviveSuspensionAndPublishOnce() {
        let graph = Graph()
        let source = graph.makeResumableRule(ResumableRuleTests.PlusOne(source: graph.makeInput(2), counter: .init()))
        let counter = ResumableRuleTests.Counter()
        let rule = graph.makeResumableRule(WriteBeforeWait(source: source, counter: counter))
        let version = graph.version(of: rule.id)
        #expect(graph.value(of: rule) == 14 && counter.starts == 1)
        #expect(graph.version(of: rule.id) == version + 1)
    }

    struct Even: ResumableRule {
        let source: Attribute<Int>
        static var initialValue: Int? { 0 }
        mutating func resume(_ context: inout ResumableRuleContext<Int>) -> RuleStep {
            switch context.poll(source) {
            case .pending: return .needsInput(source.erased)
            case .ready(let value):
                if value % 2 == 0 { context.value = value }
                return .finished
            }
        }
    }
    @Test func omittingTheWriteKeepsTheVersionAndSkipsLegacyDependents() {
        let graph = Graph()
        let source = graph.makeInput(0)
        let even = graph.makeResumableRule(Even(source: source))
        var runs = 0
        let last = graph.makeRule { runs += 1; return even.value + 1 }
        #expect(graph.value(of: last) == 1 && runs == 1)
        let version = graph.version(of: even.id)
        graph.setValue(3, for: source)
        #expect(graph.value(of: last) == 1 && runs == 1 && graph.version(of: even.id) == version)
        graph.setValue(4, for: source)
        #expect(graph.value(of: last) == 5 && runs == 2)
    }

    struct ReusePreviousStep: ResumableRule {
        let source: Attribute<Int>
        let saved: ResumableRuleTests.Saved
        mutating func resume(_ context: inout ResumableRuleContext<Int>) -> RuleStep {
            if context.isFirstStep { saved.context = context; return .needsInput(source.erased) }
            _ = saved.context!.hasValue
            context.value = 1
            return .finished
        }
    }
    @Test func aContextFromThePreviousStepCannotBeReused() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            let source = graph.makeResumableRule(ResumableRuleTests.PlusOne(source: graph.makeInput(0), counter: .init()))
            _ = graph.value(of: graph.makeResumableRule(ReusePreviousStep(source: source, saved: .init())))
        }
    }

    final class Target { var attribute: Attribute<Int>? }
    struct Cyclic: ResumableRule {
        let target: Target
        mutating func resume(_ context: inout ResumableRuleContext<Int>) -> RuleStep {
            switch context.poll(target.attribute!) {
            case .pending: return .needsInput(target.attribute!.erased)
            case .ready(let value): context.value = value; return .finished
            }
        }
    }
    @Test func aDynamicCycleFailsWithoutNativeRecursion() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            let target = Target()
            let rule = graph.makeResumableRule(Cyclic(target: target))
            target.attribute = rule
            _ = graph.value(of: rule)
        }
    }

    struct NestedRead: ResumableRule {
        weak var graph: Graph?
        let source: Attribute<Int>
        mutating func resume(_ context: inout ResumableRuleContext<Int>) -> RuleStep {
            context.value = graph!.value(of: source)
            return .finished
        }
    }
    @Test func aDirtySynchronousReadInsideAResumableStepIsRejected() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            let source = graph.makeRule { 5 }
            _ = graph.value(of: graph.makeResumableRule(NestedRead(graph: graph, source: source)))
        }
    }

    struct Many: ResumableRule {
        let sources: [Attribute<Int>]
        var next = 0
        var sum = 0
        mutating func resume(_ context: inout ResumableRuleContext<Int>) -> RuleStep {
            if context.isFirstStep { next = 0; sum = 0 }
            while next < sources.count {
                switch context.poll(sources[next]) {
                case .pending: return .needsInput(sources[next].erased)
                case .ready(let value): sum += value; next += 1
                }
            }
            context.value = sum
            return .finished
        }
    }
    @Test func twentyThousandInputsPreserveTheirTrackingOrder() {
        let graph = Graph()
        let sources = (0..<20_000).map { graph.makeInput($0) }
        let rule = graph.makeResumableRule(Many(sources: sources))
        #expect(graph.value(of: rule) == 20_000 * 19_999 / 2)
        #expect(graph.inputs(of: rule.id) == sources.map(\.id))
        graph.setValue(1_000_000, for: sources[10_000])
        #expect(graph.value(of: rule) == 20_000 * 19_999 / 2 - 10_000 + 1_000_000)
    }

    struct CopyInitial: ResumableRule {
        static var initialValue: Double? { 0 }
        mutating func resume(_ context: inout ResumableRuleContext<Double>) -> RuleStep {
            context.value = -0.0
            return .finished
        }
    }
    @Test func theInitialValueIsComparedBeforePublishingTheFirstWrite() {
        let graph = Graph()
        let rule = graph.makeResumableRule(CopyInitial(), comparison: .stateWrite)
        let version = graph.version(of: rule.id)
        #expect(graph.value(of: rule).sign == .plus)
        #expect(graph.version(of: rule.id) == version)
    }

    struct Empty: ResumableRule {
        mutating func resume(_ context: inout ResumableRuleContext<Int>) -> RuleStep { .finished }
    }
    @Test func finishingWithoutAnInitialOrProposedValueFails() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            _ = graph.value(of: graph.makeResumableRule(Empty()))
        }
    }

    struct ReadIfAlive: ResumableRule {
        weak var graph: Graph?
        let tick: Attribute<Int>
        let source: Attribute<Int>
        var ticked = false
        mutating func resume(_ context: inout ResumableRuleContext<Int>) -> RuleStep {
            if context.isFirstStep { ticked = false }
            if !ticked {
                switch context.poll(tick) {
                case .pending: return .needsInput(tick.erased)
                case .ready: ticked = true
                }
            }
            guard graph!.contains(source.id) else { context.value = 99; return .finished }
            switch context.poll(source) {
            case .pending: return .needsInput(source.erased)
            case .ready(let value): context.value = value; return .finished
            }
        }
    }
    @Test func separatelyQueuedInvalidationsUpdateAResumableReaderBeforeItsNotice() {
        let graph = Graph()
        let a = graph.makeSubgraph(), b = graph.makeSubgraph()
        let tick = graph.makeInput(0)
        let source = graph.withCurrent(a) { graph.makeInput(7) }
        let reader = graph.withCurrent(b) { graph.makeResumableRule(ReadIfAlive(graph: graph, tick: tick, source: source)) }
        #expect(graph.value(of: reader) == 7)
        var seen: [Int] = []
        graph.observe(b) {
            #expect(graph.inputs(of: reader.id) == [tick.id])
            #expect(!graph.isDirty(reader.id))
            graph.setValue(1, for: tick)
            seen.append(graph.value(of: reader))
        }
        let trigger = graph.makeRule { () -> Int in a.invalidate(); b.invalidate(); return 0 }
        _ = graph.value(of: trigger)
        #expect(seen == [99])
        #expect(graph.nodeCount == 2 && graph.liveSubgraphCount == 1 && graph.frames.isEmpty)
    }
}
