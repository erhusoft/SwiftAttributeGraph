import Testing
@testable import SwiftAttributeGraph

/// Observation and batches. Parity E9: two synchronous writes produce a single notification.
@Suite struct ObservationTests {
    private final class Counter { var count = 0 }

    @Test func anObserverIsToldWhenAnObservedRuleBecomesDirty() {
        let graph = Graph()
        let a = graph.makeInput(1)
        let frame = graph.makeRule { a.value }
        _ = graph.value(of: frame)
        let told = Counter()
        _ = graph.observe(frame.erased) { told.count += 1 }

        graph.setValue(2, for: a)
        #expect(told.count == 1)
    }

    @Test func anObserverIsNotToldAgainUntilTheNodeIsReadAgain() {
        let graph = Graph()
        let a = graph.makeInput(1)
        let frame = graph.makeRule { a.value }
        _ = graph.value(of: frame)
        let told = Counter()
        _ = graph.observe(frame.erased) { told.count += 1 }

        graph.setValue(2, for: a)
        graph.setValue(3, for: a)
        #expect(told.count == 1, "the node was already dirty: the observer already knows")
        _ = graph.value(of: frame)
        graph.setValue(4, for: a)
        #expect(told.count == 2)
    }

    @Test func anEqualWriteDoesNotNotify() {
        let graph = Graph()
        let a = graph.makeInput(1)
        let frame = graph.makeRule { a.value }
        _ = graph.value(of: frame)
        let told = Counter()
        _ = graph.observe(frame.erased) { told.count += 1 }
        graph.setValue(1, for: a)
        #expect(told.count == 0)
    }

    @Test func aBatchOfWritesNotifiesOnceAfterItCloses() {
        let graph = Graph()
        let a = graph.makeInput(1)
        let frame = graph.makeRule { a.value }
        _ = graph.value(of: frame)
        let told = Counter()
        _ = graph.observe(frame.erased) { told.count += 1 }

        graph.withBatch {
            graph.setValue(2, for: a)
            graph.setValue(3, for: a)
            #expect(told.count == 0, "notifications wait for the end of the batch")
        }
        #expect(told.count == 1, "E9: two writes, one notification")
    }

    @Test func nestedBatchesNotifyWhenTheOutermostCloses() {
        let graph = Graph()
        let a = graph.makeInput(1)
        let frame = graph.makeRule { a.value }
        _ = graph.value(of: frame)
        let told = Counter()
        _ = graph.observe(frame.erased) { told.count += 1 }
        graph.withBatch {
            graph.withBatch { graph.setValue(2, for: a) }
            #expect(told.count == 0)
        }
        #expect(told.count == 1)
    }

    @Test func anObservedInputNotifiesWhenItsValueChanges() {
        let graph = Graph()
        let a = graph.makeInput(1)
        let told = Counter()
        _ = graph.observe(a.erased) { told.count += 1 }
        graph.setValue(2, for: a)
        graph.setValue(2, for: a)
        #expect(told.count == 1)
    }

    @Test func aCancelledObservationStopsNotifying() {
        let graph = Graph()
        let a = graph.makeInput(1)
        let frame = graph.makeRule { a.value }
        _ = graph.value(of: frame)
        let told = Counter()
        let token = graph.observe(frame.erased) { told.count += 1 }
        token.cancel()
        graph.setValue(2, for: a)
        #expect(told.count == 0)
    }

    @Test func aNotificationMayWriteToTheGraphAndIsHandledAfterwards() {
        let graph = Graph()
        let a = graph.makeInput(1)
        let b = graph.makeInput(10)
        let frame = graph.makeRule { a.value + b.value }
        _ = graph.value(of: frame)
        let told = Counter()
        _ = graph.observe(frame.erased) {
            told.count += 1
            _ = graph.value(of: frame)          // the observer re-reads, so the node is clean again
            if told.count == 1 { graph.setValue(20, for: b) }   // and writes again from the callback
        }
        graph.setValue(2, for: a)
        #expect(told.count == 2)
        #expect(graph.value(of: frame) == 22)
    }

    @Test func invalidatingASubgraphDoesNotDirtyOrNotifyDependentsOutsideIt() {
        let graph = Graph()
        let sub = graph.makeSubgraph()
        let inside = graph.withCurrent(sub) { graph.makeInput(1) }
        let frame = graph.makeRule { inside.value }
        _ = graph.value(of: frame)
        let told = Counter()
        _ = graph.observe(frame.erased) { told.count += 1 }
        sub.invalidate()
        #expect(told.count == 0)
    }
}
