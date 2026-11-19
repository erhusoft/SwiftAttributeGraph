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
}
