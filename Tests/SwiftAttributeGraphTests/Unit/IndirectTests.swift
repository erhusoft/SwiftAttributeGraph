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

    // MARK: - Indirect to a rule and source redirection (M6 / C18)

    @Test func anIndirectAttributeCanRedirectToARule() {
        let graph = Graph()
        let input = graph.makeInput(5)
        var runs = 0
        let rule = graph.makeRule {
            runs += 1
            return input.value * 3
        }
        let indirect = graph.makeIndirect(rule)
        #expect(graph.source(of: indirect) == rule)
        #expect(runs == 0, "creating an indirect to a rule is lazy")

        let reader = graph.makeRule { indirect.value + 1 }
        #expect(graph.value(of: reader) == 16)
        #expect(runs == 1)
        // Reader only records the single edge to the indirect attribute (matching native AttributeGraph).
        #expect(graph.inputs(of: reader.id) == [indirect.id])

        // Mutating the underlying input dirties the rule and the reader through the indirect attribute.
        graph.setValue(7, for: input)
        #expect(graph.isDirty(reader.id))
        #expect(graph.value(of: reader) == 22)
        #expect(runs == 2)
    }

    @Test func redirectingAnIndirectAttributeToTheSameSourceDoesNotDirtyReaders() {
        let graph = Graph()
        let a = graph.makeInput(10)
        let indirect = graph.makeIndirect(a)
        var runs = 0
        let reader = graph.makeRule {
            runs += 1
            return indirect.value * 2
        }
        #expect(graph.value(of: reader) == 20)
        #expect(runs == 1)

        // Setting the exact same source is a no-op.
        graph.setSource(a, for: indirect)
        #expect(!graph.isDirty(reader.id))
        #expect(graph.value(of: reader) == 20)
        #expect(runs == 1)
    }

    @Test func redirectingAnIndirectAttributeDirtiesReadersEvenWhenValuesMatchAndDetachesOldSource() {
        let graph = Graph()
        let a = graph.makeInput(10)
        let b = graph.makeInput(10)
        let indirect = graph.makeIndirect(a)
        var runs = 0
        let reader = graph.makeRule {
            runs += 1
            return indirect.value * 2
        }
        #expect(graph.value(of: reader) == 20)
        #expect(runs == 1)

        // Redirecting to a different attribute with the same value still marks the reader dirty and re-evaluates it.
        graph.setSource(b, for: indirect)
        #expect(graph.source(of: indirect) == b)
        #expect(graph.isDirty(reader.id))
        #expect(graph.value(of: reader) == 20)
        #expect(runs == 2)

        // Changing the old source `a` no longer dirties `reader`; changing `b` does.
        graph.setValue(99, for: a)
        #expect(!graph.isDirty(reader.id))
        #expect(graph.value(of: reader) == 20)
        #expect(runs == 2)

        graph.setValue(25, for: b)
        #expect(graph.isDirty(reader.id))
        #expect(graph.value(of: reader) == 50)
        #expect(runs == 3)
    }

    @Test func statefulRuleDetectsChangeWhenIndirectIsRedirectedOrItsSourceChanges() {
        let graph = Graph()
        let a = graph.makeInput(10)
        let b = graph.makeInput(20)
        let indirect = graph.makeIndirect(a)
        var changes: [Bool] = []
        let rule = graph.makeStatefulRule(initialValue: 0) { context in
            let cv = context.changedValue(of: indirect)
            changes.append(cv.changed)
            context.value = cv.value
        }
        #expect(graph.value(of: rule) == 10)
        #expect(changes == [true])

        graph.setSource(b, for: indirect)
        #expect(graph.value(of: rule) == 20)
        #expect(changes == [true, true])

        graph.setValue(30, for: b)
        #expect(graph.value(of: rule) == 30)
        #expect(changes == [true, true, true])
    }

    @Test func invalidatingRedirectedSourceSubgraphResetsIndirectToInitialSourceWithoutDirtyingReaders() {
        let graph = Graph()
        let initial = graph.makeInput(10)
        let indirect = graph.makeIndirect(initial)
        var runs = 0
        let reader = graph.makeRule {
            runs += 1
            return indirect.value + 1
        }
        #expect(graph.value(of: reader) == 11)
        #expect(runs == 1)

        let child = graph.makeSubgraph()
        let childTarget = graph.withCurrent(child) { graph.makeInput(77) }
        graph.setSource(childTarget, for: indirect)
        #expect(graph.source(of: indirect) == childTarget)
        #expect(graph.value(of: reader) == 78)
        #expect(runs == 2)

        // Invalidating `child` resets `indirect` back to `initial` without dirtying `reader`.
        graph.invalidate(child)
        #expect(graph.source(of: indirect) == initial)
        #expect(!graph.isDirty(reader.id))
        #expect(graph.value(of: reader) == 78)
        #expect(runs == 2)

        // Writing to `initial` propagates through `indirect` and updates `reader`.
        graph.setValue(100, for: initial)
        #expect(graph.value(of: reader) == 101)
        #expect(runs == 3)

        // Explicit `resetSource(for:)` redirects back to `initial` and dirties `reader`.
        let another = graph.makeInput(50)
        graph.setSource(another, for: indirect)
        #expect(graph.value(of: reader) == 51)
        #expect(runs == 4)

        graph.resetSource(for: indirect)
        #expect(graph.source(of: indirect) == initial)
        #expect(graph.value(of: reader) == 101)
        #expect(runs == 5)
    }

    // MARK: - KeyPath projection / Focus (M6 / C14)

    private struct Pair {
        var left: Int
        var right: Int
    }

    @Test func focusProjectsKeyPathAndCutsWhenOtherFieldsChange() {
        let graph = Graph()
        let root = graph.makeInput(Pair(left: 1, right: 100))
        var focusRuns = 0
        let leftAttr = graph.makeRule(Focus(root: root, keyPath: \.left))
        let reader = graph.makeRule {
            focusRuns += 1
            return leftAttr.value * 10
        }
        #expect(graph.value(of: reader) == 10)
        #expect(focusRuns == 1)

        // Changing `right` leaves `left` unchanged: `leftAttr` evaluates and cuts `reader`.
        graph.setValue(Pair(left: 1, right: 200), for: root)
        #expect(graph.value(of: reader) == 10)
        #expect(focusRuns == 1)

        // Changing `left` updates `leftAttr` and runs `reader`.
        graph.setValue(Pair(left: 5, right: 200), for: root)
        #expect(graph.value(of: reader) == 50)
        #expect(focusRuns == 2)
    }

    @Test func makeFocusConvenienceCreatesKeyPathProjectionRule() {
        let graph = Graph()
        let root = graph.makeInput(Pair(left: 3, right: 4))
        let rightAttr = graph.makeFocus(root, keyPath: \.right)
        var runs = 0
        let reader = graph.makeRule {
            runs += 1
            return rightAttr.value + 1
        }
        #expect(graph.value(of: reader) == 5)
        #expect(runs == 1)

        graph.setValue(Pair(left: 99, right: 4), for: root)
        #expect(graph.value(of: reader) == 5)
        #expect(runs == 1)

        graph.setValue(Pair(left: 99, right: 10), for: root)
        #expect(graph.value(of: reader) == 11)
        #expect(runs == 2)
    }

    @Test func mapRuleTransformsSourceAndCutsWhenMappedOutputIsUnchanged() {
        let graph = Graph()
        let source = graph.makeInput(4)
        let parity = graph.makeMap(source) { $0 % 2 }
        var runs = 0
        let downstream = graph.makeRule {
            runs += 1
            return parity.value * 100
        }
        #expect(graph.value(of: downstream) == 0)
        #expect(runs == 1)

        // 4 -> 6 keeps `parity == 0`, cutting `downstream`.
        graph.setValue(6, for: source)
        #expect(graph.value(of: downstream) == 0)
        #expect(runs == 1)

        // 6 -> 7 changes `parity` to 1, running `downstream`.
        graph.setValue(7, for: source)
        #expect(graph.value(of: downstream) == 100)
        #expect(runs == 2)
    }

    // MARK: - Indirect dependency & setSource inside a rule (C27)

    @Test func indirectDependencyRunsProducerBeforeSourceAndCutsWhenSourceIsUnchanged() {
        let graph = Graph()
        let a = graph.makeInput(10)
        let b = graph.makeInput(100)
        let sel = graph.makeInput(0)
        let ind = graph.makeIndirect(a)

        var producerRuns = 0
        let producer = graph.makeRule { () -> Int in
            producerRuns += 1
            let s = sel.value
            if s >= 0 {
                graph.setSource(s == 0 ? a : b, for: ind)
            }
            return s
        }
        #expect(graph.dependency(of: ind) == nil)
        graph.setDependency(producer.erased, for: ind)
        #expect(graph.dependency(of: ind) == producer.erased)

        var readerRuns = 0
        let reader = graph.makeRule {
            readerRuns += 1
            return ind.value * 2
        }

        // 1. Initial pull: `ind` updates `producer` (which keeps `ind` pointing to `a`), then `reader` reads `a` (10 * 2 = 20).
        #expect(graph.value(of: reader) == 20)
        #expect(producerRuns == 1)
        #expect(readerRuns == 1)

        // 2. `sel = -1`: `producer` runs (`producerRuns == 2`) and does NOT call `setSource`; `a` did not change, so `reader` is cut!
        graph.setValue(-1, for: sel)
        #expect(graph.isDirty(ind.id))
        #expect(graph.isDirty(reader.id))
        #expect(graph.value(of: reader) == 20)
        #expect(producerRuns == 2)
        #expect(readerRuns == 1, "reader must be cut when dependency runs without changing the indirect source or its value")

        // 3. `sel = 1`: `producer` runs (`producerRuns == 3`) and redirects `ind` to `b` (100); `reader` runs (`readerRuns == 2`).
        graph.setValue(1, for: sel)
        #expect(graph.value(of: reader) == 200)
        #expect(producerRuns == 3)
        #expect(readerRuns == 2)

        // 4. Clearing `dependency` detaches `producer` from `ind`.
        graph.setDependency(nil, for: ind)
        #expect(graph.dependency(of: ind) == nil)
        graph.setValue(0, for: sel)
        #expect(!graph.isDirty(ind.id))
        #expect(!graph.isDirty(reader.id))
        #expect(graph.value(of: reader) == 200)
        #expect(producerRuns == 3)
        #expect(readerRuns == 2)
    }

    @Test func settingDependencyFromDifferentSubgraphStopsTheProgram() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            let a = graph.makeInput(10)
            let ind = graph.makeIndirect(a)
            let child = graph.makeSubgraph()
            let childProducer = graph.withCurrent(child) { graph.makeRule { 1 } }
            graph.setDependency(childProducer.erased, for: ind)
        }
    }

    // MARK: - C33: Attribute[keyPath:] and @dynamicMemberLookup

    @Test func attributeDynamicMemberAndKeyPathSubscriptsProjectFieldsAndCutOnUnchangedField() {
        let graph = Graph()
        let p = graph.makeInput(Pair(left: 1, right: 100))
        var runs = 0
        let reader = graph.makeRule { () -> Int in
            runs += 1
            let leftSub = p[keyPath: \.left]
            let leftDyn = p.left
            return leftSub.value + leftDyn.value
        }

        #expect(graph.value(of: reader) == 2)
        #expect(runs == 1)

        // Changing `right` leaves `left` unchanged -> `reader` is cut.
        graph.setValue(Pair(left: 1, right: 200), for: p)
        #expect(graph.value(of: reader) == 2)
        #expect(runs == 1)

        // Changing `left` updates the projected fields and re-runs `reader`.
        graph.setValue(Pair(left: 5, right: 200), for: p)
        #expect(graph.value(of: reader) == 10)
        #expect(runs == 2)
    }
}
