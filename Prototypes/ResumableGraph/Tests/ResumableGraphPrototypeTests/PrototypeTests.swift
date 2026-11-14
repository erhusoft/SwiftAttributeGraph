import Testing
@testable import ResumableGraphPrototype

@Suite struct PrototypeTests {
    final class Counter { var starts = 0; var steps = 0 }

    struct PlusOne: ResumableRule {
        let source: Attribute<Int>
        let counter: Counter
        mutating func resume(_ context: inout RuleContext<Int>) -> RuleStep {
            counter.steps += 1
            if context.isFirstStep { counter.starts += 1 }
            switch context.poll(source) {
            case .pending: return .needsInput(source.erased)
            case .ready(let value): context.value = value + 1; return .finished
            }
        }
    }

    struct Choose: ResumableRule {
        let selector: Attribute<Bool>
        let left: Attribute<Int>
        let right: Attribute<Int>
        let counter: Counter
        var selected: Attribute<Int>?
        mutating func resume(_ context: inout RuleContext<Int>) -> RuleStep {
            counter.steps += 1
            if context.isFirstStep { selected = nil; counter.starts += 1 }
            if selected == nil {
                switch context.poll(selector) {
                case .pending: return .needsInput(selector.erased)
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

    @Test func aColdChainOfTwentyThousandRulesUsesOnlyExplicitFrames() {
        checkChain(depth: 20_000)
    }

    @Test func aColdChainOfOneHundredThousandRulesUsesOnlyExplicitFrames() {
        checkChain(depth: 100_000)
    }

    func checkChain(depth: Int) {
        let graph = PrototypeGraph()
        let counter = Counter()
        let root = graph.makeInput(0)
        var last = root
        for _ in 0..<depth { last = graph.makeRule(PlusOne(source: last, counter: counter)) }
        #expect(counter.starts == 0)
        #expect(graph.value(of: last) == depth)
        #expect(counter.starts == depth)
        #expect(graph.maximumFrameCount == depth)
        #expect(graph.maximumActiveSteps == 1)
        #expect(graph.frameCount == 0)
        graph.setValue(1, for: root)
        #expect(graph.value(of: last) == depth + 1)
        #expect(counter.starts == 2 * depth)
        #expect(graph.frameCount == 0)
    }

    @Test func conditionalReadsSuspendWithoutReplayingCompletedEffectsAndPrune() {
        let graph = PrototypeGraph()
        let counter = Counter()
        let flag = graph.makeInput(true)
        let a = graph.makeInput(10), b = graph.makeInput(20)
        let left = graph.makeRule(PlusOne(source: a, counter: Counter()))
        let right = graph.makeRule(PlusOne(source: b, counter: Counter()))
        let result = graph.makeRule(Choose(selector: flag, left: left, right: right, counter: counter))
        #expect(graph.value(of: result) == 11)
        #expect(counter.starts == 1 && counter.steps == 2)
        #expect(graph.inputs(of: result.erased) == [flag.erased, left.erased])
        graph.setValue(false, for: flag)
        #expect(graph.value(of: result) == 21)
        #expect(counter.starts == 2 && counter.steps == 4)
        #expect(graph.inputs(of: result.erased) == [flag.erased, right.erased])
        graph.setValue(100, for: a)
        #expect(!graph.isDirty(result.erased))
        #expect(graph.value(of: result) == 21 && counter.starts == 2)
    }

    struct Accumulate: ResumableRule {
        let source: Attribute<Int>
        var executions = 0
        static var initialValue: Int? { 0 }
        mutating func resume(_ context: inout RuleContext<Int>) -> RuleStep {
            switch context.poll(source) {
            case .pending: return .needsInput(source.erased)
            case .ready(let value):
                executions += 1
                if context.hasChanged(source) { context.value += value }
                return .finished
            }
        }
    }

    @Test func aStatefulRuleAccumulatesOnceAfterCoalescedWrites() {
        let graph = PrototypeGraph()
        let input = graph.makeInput(1)
        let source = graph.makeRule(PlusOne(source: input, counter: Counter()))
        let sum = graph.makeRule(Accumulate(source: source))
        #expect(graph.value(of: sum) == 2)
        graph.setValue(2, for: input)
        graph.setValue(3, for: input)
        #expect(graph.value(of: sum) == 6)
        #expect(graph.value(of: sum) == 6)
    }

    struct Even: ResumableRule {
        let source: Attribute<Int>
        static var initialValue: Int? { 0 }
        mutating func resume(_ context: inout RuleContext<Int>) -> RuleStep {
            switch context.poll(source) {
            case .pending: return .needsInput(source.erased)
            case .ready(let value):
                if value % 2 == 0 { context.value = value }
                return .finished
            }
        }
    }

    @Test func keepingThePreviousValueCutsDownstreamExecutions() {
        let graph = PrototypeGraph()
        let input = graph.makeInput(0)
        let even = graph.makeRule(Even(source: input))
        let counter = Counter()
        let last = graph.makeRule(PlusOne(source: even, counter: counter))
        #expect(graph.value(of: last) == 1)
        let version = graph.version(of: even.erased)
        graph.setValue(3, for: input)
        #expect(graph.value(of: last) == 1)
        #expect(graph.version(of: even.erased) == version && counter.starts == 1)
        graph.setValue(4, for: input)
        #expect(graph.value(of: last) == 5 && counter.starts == 2)
    }

    struct OptionalRead: ResumableRule {
        let source: Attribute<Int?>
        mutating func resume(_ context: inout RuleContext<Int?>) -> RuleStep {
            switch context.poll(source) {
            case .pending: return .needsInput(source.erased)
            case .ready(let value): context.value = value; return .finished
            }
        }
    }

    @Test func aReadyNilIsAValueAndRepeatedReadsDoNotDuplicateEdges() {
        let graph = PrototypeGraph()
        let input = graph.makeInput(nil as Int?)
        let first = graph.makeRule(OptionalRead(source: input))
        let last = graph.makeRule(OptionalRead(source: first))
        #expect(graph.value(of: last) == nil)
        #expect(graph.inputs(of: last.erased) == [first.erased])
        graph.setValue(4, for: input)
        #expect(graph.value(of: last) == 4)
    }

    final class Saved { var context: RuleContext<Int>? }
    struct Save: ResumableRule {
        let saved: Saved
        mutating func resume(_ context: inout RuleContext<Int>) -> RuleStep {
            saved.context = context
            context.value = 0
            return .finished
        }
    }

    @Test func anEscapedContextFailsInAControlledWay() async {
        await #expect(processExitsWith: .failure) {
            let graph = PrototypeGraph()
            let saved = Saved()
            let rule = graph.makeRule(Save(saved: saved))
            _ = graph.value(of: rule)
            _ = saved.context!.hasValue
        }
    }

    @Test func invalidatingAnOwnerReleasesDeepRulesAndTheirState() {
        weak var weakCounter: Counter?
        let graph = PrototypeGraph()
        let owner = graph.makeOwner()
        graph.withOwner(owner) {
            let counter = Counter()
            weakCounter = counter
            var last = graph.makeInput(0)
            for _ in 0..<20_000 { last = graph.makeRule(PlusOne(source: last, counter: counter)) }
            #expect(graph.value(of: last) == 20_000)
        }
        graph.invalidate(owner)
        #expect(weakCounter == nil)
        #expect(graph.nodeCount == 0 && graph.liveOwnerCount == 1 && graph.frameCount == 0)
    }
}
