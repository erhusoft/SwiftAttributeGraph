import Testing
@testable import SwiftAttributeGraph

@Suite("CooperativeCancellationTests")
struct CooperativeCancellationTests {
    @Test
    func cancelUpdateMarksCurrentAndNestedFramesAndRestoresAfterExit() {
        let graph = Graph()
        let source = graph.makeInput(10)
        var innerSawCancel = false
        var outerSawCancelBeforeInner = false
        var outerSawCancelAfterInner = false

        let inner = graph.makeRule {
            let v = source.value
            graph.cancelUpdate()
            innerSawCancel = graph.updateWasCancelled
            return v + 1
        }

        let outer = graph.makeRule {
            outerSawCancelBeforeInner = graph.updateWasCancelled
            let v = inner.value
            outerSawCancelAfterInner = graph.updateWasCancelled
            return v * 2
        }

        #expect(graph.value(of: outer) == 22)
        #expect(outerSawCancelBeforeInner == false)
        #expect(innerSawCancel == true)
        #expect(outerSawCancelAfterInner == true)
        #expect(graph.frames.isEmpty)
    }

    @Test
    func cancelledEvaluationKeepsNodeDirtyAndRetriesOnNextRead() {
        let graph = Graph()
        let source = graph.makeInput(10)
        var shouldCancel = true
        var runs = 0

        let rule = graph.makeRule {
            runs += 1
            let v = source.value
            if shouldCancel {
                graph.cancelUpdate()
                return -1
            }
            return v * 3
        }

        // First read is cancelled: rule runs, node stays dirty for retry.
        _ = graph.value(of: rule)
        #expect(runs == 1)
        #expect(graph.table.state[Int(rule.id.index)] & NodeState.dirty != 0)

        // Next read without cancelling retries and cleans dirty.
        shouldCancel = false
        #expect(graph.value(of: rule) == 30)
        #expect(runs == 2)
        #expect(graph.table.state[Int(rule.id.index)] & NodeState.dirty == 0)
    }

    @Test
    func cancellingInDirtyInputPreventsPendingParentRuleFromStarting() {
        let graph = Graph()
        let source = graph.makeInput(1)
        var shouldCancel = true
        var parentRuns = 0

        let child = graph.makeRule {
            let v = source.value
            if shouldCancel { graph.cancelUpdate() }
            return v + 10
        }
        let parent = graph.makeRule {
            parentRuns += 1
            return child.value * 2
        }

        // First evaluation without cancel establishes dependency parent -> child.
        shouldCancel = false
        #expect(graph.value(of: parent) == 22)
        #expect(parentRuns == 1)

        // Dirty child and cancel during child's re-evaluation: parent must not start.
        shouldCancel = true
        graph.setValue(2, for: source)
        _ = graph.value(of: parent)
        #expect(parentRuns == 1)
        #expect(graph.table.state[Int(parent.id.index)] & NodeState.dirty != 0)

        // Retry without cancel: parent runs once with updated child value (2 + 10) * 2 = 24.
        shouldCancel = false
        #expect(graph.value(of: parent) == 24)
        #expect(parentRuns == 2)
    }

    @Test func cancellingResumableRuleWithPreviousValuePreservesConfirmedValueAndRetries() {
        struct ResumableAdder: ResumableRule {
            typealias Value = Int
            static var initialValue: Int? { nil }
            let graph: Graph
            let source: Attribute<Int>
            let shouldCancel: () -> Bool

            mutating func resume(_ context: inout ResumableRuleContext<Int>) -> RuleStep {
                let v = source.value
                if shouldCancel() { graph.cancelUpdate() }
                context.value = v + 10
                return .finished
            }
        }

        let graph = Graph()
        let source = graph.makeInput(1)
        var shouldCancel = false
        let attr = graph.makeResumableRule(ResumableAdder(graph: graph, source: source, shouldCancel: { shouldCancel }))

        #expect(graph.value(of: attr) == 11)
        let confirmedVersion = graph.table.versions[Int(attr.id.index)]

        shouldCancel = true
        graph.setValue(2, for: source)
        #expect(graph.value(of: attr) == 11)
        #expect(graph.table.versions[Int(attr.id.index)] == confirmedVersion)
        #expect(graph.table.state[Int(attr.id.index)] & (NodeState.dirty | NodeState.pending) == (NodeState.dirty | NodeState.pending))

        shouldCancel = false
        #expect(graph.value(of: attr) == 12)
        #expect(graph.table.versions[Int(attr.id.index)] == confirmedVersion &+ 1)
        #expect(graph.table.state[Int(attr.id.index)] & NodeState.dirty == 0)
    }

    @Test func cancellingResumableRuleWithoutPreviousValueKeepsProvisionalValueAndRetries() {
        struct FirstRunResumable: ResumableRule {
            typealias Value = Int
            static var initialValue: Int? { nil }
            let graph: Graph
            let source: Attribute<Int>
            let shouldCancel: () -> Bool

            mutating func resume(_ context: inout ResumableRuleContext<Int>) -> RuleStep {
                let v = source.value
                if shouldCancel() { graph.cancelUpdate() }
                context.value = v + 10
                return .finished
            }
        }

        let graph = Graph()
        let source = graph.makeInput(1)
        var shouldCancel = true
        let attr = graph.makeResumableRule(FirstRunResumable(graph: graph, source: source, shouldCancel: { shouldCancel }))

        #expect(graph.value(of: attr) == 11)
        #expect(graph.table.state[Int(attr.id.index)] & NodeState.hasValue == 0)
        #expect(graph.table.state[Int(attr.id.index)] & (NodeState.dirty | NodeState.pending) == (NodeState.dirty | NodeState.pending))

        shouldCancel = false
        graph.setValue(2, for: source)
        #expect(graph.value(of: attr) == 12)
        #expect(graph.table.state[Int(attr.id.index)] & NodeState.hasValue != 0)
        #expect(graph.table.state[Int(attr.id.index)] & NodeState.dirty == 0)
    }

    @Test func statefulRuleInternalMutationsAreNotRolledBackOnCancellation() {
        struct CountingStatefulRule: StatefulRule {
            typealias Value = Int
            static var initialValue: Int? { nil }
            let graph: Graph
            let source: Attribute<Int>
            let shouldCancel: () -> Bool
            var attempts = 0

            mutating func updateValue(_ context: inout RuleContext<Int>) {
                attempts += 1
                let v = source.value
                if shouldCancel() { graph.cancelUpdate() }
                context.value = v + attempts * 100
            }
        }

        let graph = Graph()
        let source = graph.makeInput(1)
        var shouldCancel = false
        let attr = graph.makeStatefulRule(CountingStatefulRule(graph: graph, source: source, shouldCancel: { shouldCancel }))

        #expect(graph.value(of: attr) == 101)
        let confirmedVersion = graph.table.versions[Int(attr.id.index)]

        // Cancelled attempt mutates `attempts` to 2, but preserves confirmed value 101 and version.
        shouldCancel = true
        graph.setValue(2, for: source)
        #expect(graph.value(of: attr) == 101)
        #expect(graph.table.versions[Int(attr.id.index)] == confirmedVersion)

        // Retry mutates `attempts` to 3 (no rollback of internal rule state) and publishes 302.
        shouldCancel = false
        #expect(graph.value(of: attr) == 302)
        #expect(graph.table.versions[Int(attr.id.index)] == confirmedVersion &+ 1)
    }

    @Test func retryProducingSameValueAfterCancellationDoesNotBumpVersionOrPropagate() {
        let graph = Graph()
        let source = graph.makeInput(1)
        var shouldCancel = false
        var parentRuns = 0

        let child = graph.makeRule {
            let v = source.value
            if shouldCancel { graph.cancelUpdate() }
            return v * 0 + 10
        }
        let parent = graph.makeRule {
            parentRuns += 1
            return child.value + 1
        }

        #expect(graph.value(of: parent) == 11)
        #expect(parentRuns == 1)
        let childVersion = graph.table.versions[Int(child.id.index)]

        shouldCancel = true
        graph.setValue(2, for: source)
        #expect(graph.value(of: child) == 10)
        #expect(graph.table.versions[Int(child.id.index)] == childVersion)

        shouldCancel = false
        #expect(graph.value(of: parent) == 11)
        #expect(graph.table.versions[Int(child.id.index)] == childVersion)
        #expect(parentRuns == 1)
    }
}
