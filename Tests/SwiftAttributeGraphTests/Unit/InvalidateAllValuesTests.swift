import Testing
@testable import SwiftAttributeGraph

/// `AGGraphInvalidateAllValues` (native `AGGraphRef.invalidateAllValues(self:)`). Measured with the
/// `invalidate-all-values` oracle scenario: after the call the stored value stays (`hasValue` is still true) and the
/// next read runs the rule again.
@Suite struct InvalidateAllValuesTests {
    @Test func nextReadOfEveryRuleRunsItAgainAndKeepsTheValue() {
        let graph = Graph()
        var runs = 0
        let r = graph.makeRule { runs += 1; return 42 }
        #expect(graph.value(of: r) == 42)
        #expect(runs == 1)

        graph.invalidateAllValues()
        #expect(graph.hasValue(of: r) == true)
        #expect(graph.value(of: r) == 42)
        #expect(runs == 2)
    }

    @Test func everyRuleIsInvalidatedAndInputsAreNotRerun() {
        let graph = Graph()
        let input = graph.makeInput(3)
        var runsA = 0
        var runsB = 0
        let a = graph.makeRule { runsA += 1; return graph.value(of: input) + 1 }
        let b = graph.makeRule { runsB += 1; return graph.value(of: a) * 2 }
        #expect(graph.value(of: b) == 8)

        graph.invalidateAllValues()
        #expect(graph.value(of: b) == 8)
        #expect(runsA == 2)
        #expect(runsB == 2)
        #expect(graph.value(of: input) == 3)
    }

    @Test func invalidatingWithNoRulesDoesNothing() {
        let graph = Graph()
        _ = graph.makeInput(1)
        graph.invalidateAllValues()
        #expect(graph.nodeCount == 1)
    }
}
