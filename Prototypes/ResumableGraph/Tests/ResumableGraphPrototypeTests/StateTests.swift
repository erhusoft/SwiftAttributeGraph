import Testing
@testable import ResumableGraphPrototype

@Suite struct StateTests {
    @Test func repeatedEvaluationsReuseTheirOwnedContextStorage() {
        let graph = PrototypeGraph()
        let input = graph.makeInput(0)
        let rule = graph.makeRule(PrototypeTests.PlusOne(source: input, counter: .init()))
        for value in 0..<50 {
            graph.setValue(value, for: input)
            #expect(graph.value(of: rule) == value + 1)
        }
        #expect(graph.evaluationAllocationCount == 1)
    }

    @Test func reusableEvaluationStorageDiesWithItsOwner() {
        let graph = PrototypeGraph()
        let owner = graph.makeOwner()
        let rule = graph.withOwner(owner) {
            graph.makeRule(PrototypeTests.PlusOne(source: graph.makeInput(0), counter: .init()))
        }
        _ = graph.value(of: rule)
        weak var storage = (graph.nodes[rule.index] as! RuleNode<PrototypeTests.PlusOne>).evaluation
        #expect(storage != nil)
        graph.invalidate(owner)
        #expect(storage == nil && graph.nodeCount == 0)
    }

    struct UseContextFromAnEarlierEvaluation: ResumableRule {
        let input: Attribute<Int>
        let saved: PrototypeTests.Saved
        var runs = 0
        mutating func resume(_ context: inout RuleContext<Int>) -> RuleStep {
            switch context.poll(input) {
            case .pending: return .needsInput(input.erased)
            case .ready(let value):
                if runs == 0 { saved.context = context }
                else { _ = saved.context!.hasValue }
                runs += 1
                context.value = value
                return .finished
            }
        }
    }

    @Test func aContextFromAnEarlierEvaluationStaysInvalidDuringTheNextEvaluation() async {
        await #expect(processExitsWith: .failure) {
            let graph = PrototypeGraph()
            let input = graph.makeInput(0)
            let rule = graph.makeRule(UseContextFromAnEarlierEvaluation(input: input, saved: .init()))
            _ = graph.value(of: rule)
            graph.setValue(1, for: input)
            _ = graph.value(of: rule)
        }
    }

    struct Parity: ResumableRule {
        let source: Attribute<Int>
        mutating func resume(_ context: inout RuleContext<Int>) -> RuleStep {
            switch context.poll(source) {
            case .pending: return .needsInput(source.erased)
            case .ready(let value): context.value = value % 2; return .finished
            }
        }
    }

    final class Changes { var values: [[Bool]] = [] }
    struct ObserveTwo: ResumableRule {
        let first: Attribute<Int>
        let second: Attribute<Int>
        let changes: Changes
        var left: Int?
        mutating func resume(_ context: inout RuleContext<Int>) -> RuleStep {
            if context.isFirstStep {
                left = nil
                changes.values.append([context.hasChanged(first), context.hasChanged(second)])
            }
            if left == nil {
                switch context.poll(first) {
                case .pending: return .needsInput(first.erased)
                case .ready(let value): left = value
                }
            }
            switch context.poll(second) {
            case .pending: return .needsInput(second.erased)
            case .ready(let value): context.value = left! * 10 + value; return .finished
            }
        }
    }

    @Test func anEarlierChangeSurvivesUpdatingALaterInputAndItsSnapshotStaysStable() {
        let graph = PrototypeGraph()
        let first = graph.makeInput(0), second = graph.makeInput(0)
        let parity = graph.makeRule(Parity(source: second))
        let changes = Changes()
        let rule = graph.makeRule(ObserveTwo(first: first, second: parity, changes: changes))
        #expect(graph.value(of: rule) == 0)
        graph.setValue(1, for: first)
        graph.setValue(2, for: second)
        #expect(graph.value(of: rule) == 10)
        #expect(changes.values == [[false, false], [true, false]])
    }

    struct WriteBeforeWait: ResumableRule {
        let source: Attribute<Int>
        let counter: PrototypeTests.Counter
        static var initialValue: Int? { 10 }
        mutating func resume(_ context: inout RuleContext<Int>) -> RuleStep {
            counter.steps += 1
            if context.isFirstStep { counter.starts += 1; context.value += 1 }
            switch context.poll(source) {
            case .pending: return .needsInput(source.erased)
            case .ready(let value): context.value += value; return .finished
            }
        }
    }

    @Test func proposedWritesSurviveSuspensionWithoutBeingPublishedEarly() {
        let graph = PrototypeGraph()
        let input = graph.makeInput(2)
        let source = graph.makeRule(PrototypeTests.PlusOne(source: input, counter: .init()))
        let counter = PrototypeTests.Counter()
        let result = graph.makeRule(WriteBeforeWait(source: source, counter: counter))
        let version = graph.version(of: result.erased)
        #expect(graph.value(of: result) == 14)
        #expect(counter.starts == 1 && counter.steps == 2)
        #expect(graph.version(of: result.erased) == version + 1)
    }

    @Test func twentyThousandColdStatefulRulesRetainTheirPreviousValues() {
        let graph = PrototypeGraph()
        let root = graph.makeInput(1)
        var last = root
        for _ in 0..<20_000 { last = graph.makeRule(PrototypeTests.Accumulate(source: last)) }
        #expect(graph.value(of: last) == 1)
        graph.setValue(2, for: root)
        #expect(graph.value(of: last) == 20_002)
        #expect(graph.maximumActiveSteps == 1 && graph.frameCount == 0)
    }

    struct RepeatRead: ResumableRule {
        let source: Attribute<Int>
        mutating func resume(_ context: inout RuleContext<Int>) -> RuleStep {
            switch context.poll(source) {
            case .pending: return .needsInput(source.erased)
            case .ready(let first):
                guard case .ready(let second) = context.poll(source) else { preconditionFailure() }
                context.value = first + second
                return .finished
            }
        }
    }

    @Test func repeatedPollsAndThePendingRequestKeepOneDependency() {
        let graph = PrototypeGraph()
        let input = graph.makeInput(2)
        let source = graph.makeRule(PrototypeTests.PlusOne(source: input, counter: .init()))
        let twice = graph.makeRule(RepeatRead(source: source))
        #expect(graph.value(of: twice) == 6)
        #expect(graph.inputs(of: twice.erased) == [source.erased])
    }

    final class Target { var attribute: Attribute<Int>? }
    struct Cycle: ResumableRule {
        let target: Target
        mutating func resume(_ context: inout RuleContext<Int>) -> RuleStep {
            switch context.poll(target.attribute!) {
            case .pending: return .needsInput(target.attribute!.erased)
            case .ready(let value): context.value = value; return .finished
            }
        }
    }

    @Test func aDynamicCycleStopsTheProgram() async {
        await #expect(processExitsWith: .failure) {
            let graph = PrototypeGraph()
            let target = Target()
            let rule = graph.makeRule(Cycle(target: target))
            target.attribute = rule
            _ = graph.value(of: rule)
        }
    }

    struct UseSavedContext: ResumableRule {
        let source: Attribute<Int>
        let saved: PrototypeTests.Saved
        mutating func resume(_ context: inout RuleContext<Int>) -> RuleStep {
            if context.isFirstStep {
                saved.context = context
                return .needsInput(source.erased)
            }
            _ = saved.context!.hasValue
            context.value = 123
            return .finished
        }
    }

    @Test func aContextFromThePreviousStepCannotBeReused() async {
        await #expect(processExitsWith: .failure) {
            let graph = PrototypeGraph()
            let input = graph.makeInput(0)
            let source = graph.makeRule(PrototypeTests.PlusOne(source: input, counter: .init()))
            let result = graph.makeRule(UseSavedContext(source: source, saved: .init()))
            _ = graph.value(of: result)
        }
    }

    @Test func aContextDoesNotKeepItsGraphAlive() {
        let saved = PrototypeTests.Saved()
        weak var weakGraph: PrototypeGraph?
        do {
            let graph = PrototypeGraph()
            weakGraph = graph
            _ = graph.value(of: graph.makeRule(PrototypeTests.Save(saved: saved)))
        }
        #expect(weakGraph == nil && saved.context != nil)
    }

    struct InvalidateSelf: ResumableRule {
        weak var graph: PrototypeGraph?
        let owner: Int
        let source: Attribute<Int>
        mutating func resume(_ context: inout RuleContext<Int>) -> RuleStep {
            if context.isFirstStep { graph!.invalidate(owner) }
            switch context.poll(source) {
            case .pending: return .needsInput(source.erased)
            case .ready(let value): context.value = value; return .finished
            }
        }
    }

    @Test func selfInvalidationWaitsUntilTheExternalReadHasCopiedItsValue() {
        let graph = PrototypeGraph()
        let owner = graph.makeOwner()
        let rule = graph.withOwner(owner) {
            let input = graph.makeInput(4)
            let source = graph.makeRule(PrototypeTests.PlusOne(source: input, counter: .init()))
            return graph.makeRule(InvalidateSelf(graph: graph, owner: owner, source: source))
        }
        #expect(graph.value(of: rule) == 5)
        #expect(graph.nodeCount == 0 && graph.liveOwnerCount == 1 && graph.frameCount == 0)
    }
}
