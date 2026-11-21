import Testing
@testable import SwiftAttributeGraph

/// `AGGraphPrefetchValue` (`Attribute.prefetchValue()`). Measured with the `prefetch` oracle scenario on macOS 15.8: a dirty
/// rule runs during the prefetch, and the read that follows does not run it again.
@Suite struct PrefetchValueTests {
    @Test func prefetchRunsADirtyRuleOnceAndTheReadDoesNotRunItAgain() {
        let graph = Graph()
        let source = graph.makeInput(1)
        var runs = 0
        let rule = graph.makeRule { () -> Int in runs += 1; return graph.value(of: source) + 1 }
        _ = graph.value(of: rule)
        #expect(runs == 1)

        graph.setValue(2, for: source)
        rule.prefetchValue()
        #expect(runs == 2)
        #expect(graph.value(of: rule) == 3)
        #expect(runs == 2)
    }
}
