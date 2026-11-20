import Testing
@testable import SwiftAttributeGraph

/// Deadlines for `cancelUpdateIfNeeded()` (`AGGraphSetDeadline`, `AGGraphHasDeadlinePassed`, `AGGraphCancelUpdateIfNeeded`
/// in native AttributeGraph). Measured on macOS 15.8 with the oracle probes:
/// - a passed deadline makes `cancelUpdateIfNeeded()` cancel the running update; a future one does not;
/// - a passed deadline does not cancel by itself: the rule must call `cancelUpdateIfNeeded()`;
/// - the innermost `withDeadline` decides, and the outer deadline is restored when the inner block returns.
/// The engine uses `ContinuousClock` instants; Apple uses mach ticks (same meaning, different unit).
@Suite struct DeadlineTests {
    /// Reads a rule that calls `cancelUpdateIfNeeded()` and records `updateWasCancelled`, under `deadline`.
    private func wasCancelled(under deadline: ContinuousClock.Instant?) -> Bool {
        let graph = Graph()
        var was = false
        let rule = graph.makeRule { () -> Int in
            graph.cancelUpdateIfNeeded()
            was = graph.updateWasCancelled
            return 1
        }
        if let deadline {
            _ = graph.withDeadline(deadline) { graph.value(of: rule) }
        } else {
            _ = graph.value(of: rule)
        }
        return was
    }

    @Test func passedDeadlineCancelsWhenTheRuleAsksIfNeeded() {
        let past = ContinuousClock.now.advanced(by: .seconds(-3600))
        #expect(wasCancelled(under: past) == true)
    }

    @Test func futureDeadlineDoesNotCancel() {
        let future = ContinuousClock.now.advanced(by: .seconds(3600))
        #expect(wasCancelled(under: future) == false)
    }

    @Test func noDeadlineDoesNotCancel() {
        #expect(wasCancelled(under: nil) == false)
    }

    @Test func passedDeadlineDoesNotCancelByItselfWithoutTheCall() {
        let graph = Graph()
        var was = true
        let rule = graph.makeRule { () -> Int in
            was = graph.updateWasCancelled
            return 1
        }
        let past = ContinuousClock.now.advanced(by: .seconds(-3600))
        _ = graph.withDeadline(past) { graph.value(of: rule) }
        #expect(was == false)
    }

    @Test func innermostDeadlineDecidesAndTheOuterOneIsRestored() {
        let graph = Graph()
        let past = ContinuousClock.now.advanced(by: .seconds(-3600))
        let future = ContinuousClock.now.advanced(by: .seconds(3600))
        var innerPastOuterFuture = false
        var innerFutureOuterPast = false
        var restoredOuterPast = false
        let a = graph.makeRule { () -> Int in graph.cancelUpdateIfNeeded(); innerPastOuterFuture = graph.updateWasCancelled; return 1 }
        let b = graph.makeRule { () -> Int in graph.cancelUpdateIfNeeded(); innerFutureOuterPast = graph.updateWasCancelled; return 2 }
        let c = graph.makeRule { () -> Int in graph.cancelUpdateIfNeeded(); restoredOuterPast = graph.updateWasCancelled; return 3 }

        _ = graph.withDeadline(future) { graph.withDeadline(past) { graph.value(of: a) } }
        _ = graph.withDeadline(past) {
            graph.withDeadline(future) { graph.value(of: b) }
            graph.value(of: c)
        }
        #expect(innerPastOuterFuture == true)
        #expect(innerFutureOuterPast == false)
        #expect(restoredOuterPast == true)
    }

    @Test func hasDeadlinePassedReflectsTheCurrentDeadline() {
        let graph = Graph()
        #expect(graph.hasDeadlinePassed == false)
        let past = ContinuousClock.now.advanced(by: .seconds(-3600))
        _ = graph.withDeadline(past) { graph.hasDeadlinePassed }
        #expect(graph.hasDeadlinePassed == false)
        #expect(graph.withDeadline(past) { graph.hasDeadlinePassed } == true)
    }
}
