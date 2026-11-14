import Testing
@testable import SwiftAttributeGraph

/// Tests for M6: indirect attributes (redirection to another attribute).
@Suite struct IndirectTests {

    // MARK: - Redirection delegates read/write to the source

    @Test func anIndirectAttributeReadsTheSourceValue() {
        let graph = Graph()
        let source = graph.makeInput(42)
        let indirect = graph.makeIndirect(source)

        #expect(graph.value(of: indirect) == 42)
        #expect(graph.value(of: source) == 42)
    }

    @Test func writingToAnIndirectAttributeWritesTheSource() {
        let graph = Graph()
        let source = graph.makeInput(1)
        let indirect = graph.makeIndirect(source)

        graph.setValue(100, for: indirect)

        #expect(graph.value(of: source) == 100)
        #expect(graph.value(of: indirect) == 100)
    }

    @Test func writingToTheSourceIsVisibleThroughTheIndirect() {
        let graph = Graph()
        let source = graph.makeInput(1)
        let indirect = graph.makeIndirect(source)

        graph.setValue(200, for: source)

        #expect(graph.value(of: indirect) == 200)
        #expect(graph.value(of: source) == 200)
    }

    // MARK: - Version cut is shared with the source

    @Test func anIndirectAttributeSharesTheSourcesVersionCut() {
        let graph = Graph()
        let source = graph.makeInput(7)
        let indirect = graph.makeIndirect(source)

        // Writing the same value: source version does not rise, indirect reflects the same value.
        graph.setValue(7, for: source)
        #expect(graph.value(of: indirect) == 7)

        // Writing a different value: source version rises, indirect reflects the new value.
        graph.setValue(8, for: source)
        #expect(graph.value(of: indirect) == 8)
    }

    // MARK: - Dependencies are tracked through the indirect attribute

    @Test func aRuleReadingAnIndirectAttributeDependsOnTheSource() {
        let graph = Graph()
        let source = graph.makeInput(1)
        let indirect = graph.makeIndirect(source)

        let rule = graph.makeRule { indirect.value + 10 }
        #expect(graph.value(of: rule) == 11)

        // Changing the source must dirty the rule (through the indirect dependency).
        graph.setValue(2, for: source)
        #expect(graph.value(of: rule) == 12)
    }

    @Test func aRuleReadingAnIndirectAttributeIsNotDirtyWhenTheSourceIsUnchanged() {
        let graph = Graph()
        let source = graph.makeInput(5)
        let indirect = graph.makeIndirect(source)

        let rule = graph.makeRule { indirect.value * 2 }
        _ = graph.value(of: rule) // first run

        // Write the same value: no version change, rule is not re-run.
        var runs = 0
        let countingRule = graph.makeRule {
            runs += 1
            return indirect.value
        }
        _ = graph.value(of: countingRule)
        let firstRuns = runs

        graph.setValue(5, for: source)
        _ = graph.value(of: countingRule)
        #expect(runs == firstRuns, "the rule must not re-run when the source value did not change")
    }

    // MARK: - Multiple indirections and sharing

    @Test func multipleIndirectsShareTheSameSource() {
        let graph = Graph()
        let source = graph.makeInput(0)
        let a = graph.makeIndirect(source)
        let b = graph.makeIndirect(source)

        graph.setValue(3, for: a)
        #expect(graph.value(of: b) == 3)
        #expect(graph.value(of: source) == 3)
    }

    @Test func anIndirectToAnInputIsNotARule() {
        let graph = Graph()
        let source = graph.makeInput(9)
        let indirect = graph.makeIndirect(source)

        // Writing to an indirect must be allowed (it's not a rule).
        graph.setValue(42, for: indirect)
        #expect(graph.value(of: indirect) == 42)
    }
}
