import Testing
@testable import SwiftAttributeGraph

/// Tests for `WeakAttribute` (C15): reading a live target, returning `nil` after its subgraph is invalidated, and
/// keeping cached values on outside readers until another live input dirties them.
@Suite struct WeakAttributeTests {
    private final class Counter { var runs = 0 }

    @Test func aDefaultWeakAttributeResolvesToNil() {
        let graph = Graph()
        let weak = WeakAttribute<Int>()
        #expect(graph.attribute(of: weak) == nil)
        #expect(graph.value(of: weak) == nil)
    }

    @Test func aWeakAttributeReadsItsTargetWhileAliveAndReturnsNilAfterSubgraphInvalidation() {
        let graph = Graph()
        let sub = graph.makeSubgraph()
        let target = graph.withCurrent(sub) { graph.makeInput(42) }
        let weak = WeakAttribute(target)

        #expect(graph.attribute(of: weak) == target)
        #expect(graph.value(of: weak) == 42)
        #expect(graph.changedValue(of: weak)?.value == 42)
        #expect(graph.changedValue(of: weak)?.changed == false)

        graph.setValue(99, for: target)
        #expect(graph.value(of: weak) == 99)

        graph.invalidate(sub)
        #expect(graph.attribute(of: weak) == nil)
        #expect(graph.value(of: weak) == nil)
        #expect(graph.changedValue(of: weak) == nil)
    }

    @Test func aRuleReadingAWeakAttributeTracksItWhileAliveAndKeepsCachedValueUponInvalidation() {
        let graph = Graph()
        let sub = graph.makeSubgraph()
        let trigger = graph.makeInput(0)
        let target = graph.withCurrent(sub) { graph.makeInput(55) }
        let weak = WeakAttribute(target)
        let counter = Counter()

        let reader = graph.makeRule {
            counter.runs += 1
            _ = trigger.value
            return (weak.value ?? -1)
        }

        // 1. Initial read while target is alive:
        #expect(graph.value(of: reader) == 55)
        #expect(counter.runs == 1)

        // 2. Mutating target dirties reader through the tracked dependency:
        graph.setValue(66, for: target)
        #expect(graph.value(of: reader) == 66)
        #expect(counter.runs == 2)

        // 3. Invalidating `sub` detaches the edge without dirtying `reader` (matches native AttributeGraph C15):
        graph.invalidate(sub)
        #expect(graph.value(of: reader) == 66)
        #expect(counter.runs == 2)

        // 4. When another live input (`trigger`) changes, `reader` runs and sees `weak.value == nil`:
        graph.setValue(1, for: trigger)
        #expect(graph.value(of: reader) == -1)
        #expect(counter.runs == 3)
    }

    @Test func aStatefulRuleContextCanReadAndCheckChangedValueOfAWeakAttribute() {
        let graph = Graph()
        let sub = graph.makeSubgraph()
        let tick = graph.makeInput(0)
        let target = graph.withCurrent(sub) { graph.makeInput(10) }
        let weak = WeakAttribute(target)

        let rule = graph.makeStatefulRule(initialValue: 0) { context in
            _ = tick.value
            if let cv = context.changedValue(of: weak) {
                context.value = cv.changed ? cv.value * 10 : cv.value
            } else {
                context.value = -999
            }
        }

        #expect(graph.value(of: rule) == 100)
        graph.setValue(1, for: tick)
        #expect(graph.value(of: rule) == 10)
        graph.setValue(20, for: target)
        #expect(graph.value(of: rule) == 200)

        graph.invalidate(sub)
        #expect(graph.value(of: rule) == 200) // cached until `tick` changes
        graph.setValue(2, for: tick)
        #expect(graph.value(of: rule) == -999)
    }

    @Test func optionalAttributeResolvesWhenSetAndReturnsNilWhenEmpty() {
        let graph = Graph()
        let empty = OptionalAttribute<Int>()
        #expect(graph.attribute(of: empty) == nil)
        #expect(graph.value(of: empty) == nil)
        #expect(graph.changedValue(of: empty) == nil)

        let source = graph.makeInput(42)
        let wrapped = OptionalAttribute(source)
        #expect(graph.attribute(of: wrapped) == source)
        #expect(graph.value(of: wrapped) == 42)

        let reader = graph.makeRule { wrapped.value ?? -1 }
        #expect(graph.value(of: reader) == 42)
        graph.setValue(99, for: source)
        #expect(graph.value(of: reader) == 99)
    }

    private struct PropertyWrapperRule: Rule {
        @Attribute var primary: Int
        @WeakAttribute var secondary: Int?
        @OptionalAttribute var overrideValue: Int?

        init(primary: Attribute<Int>, secondary: WeakAttribute<Int>, overrideValue: OptionalAttribute<Int>) {
            self._primary = primary
            self._secondary = secondary
            self._overrideValue = overrideValue
        }

        var value: Int {
            if let overrideValue { return overrideValue }
            return $primary.value + (secondary ?? -10)
        }
    }

    @Test func propertyWrappersOnAttributeWeakAttributeAndOptionalAttributeReadAndTrackInsideRule() {
        let graph = Graph()
        let sub = graph.makeSubgraph()
        let p = graph.makeInput(5)
        let s = graph.withCurrent(sub) { graph.makeInput(20) }
        let o = graph.makeInput(100)

        let ruleNoOverride = graph.makeRule(
            PropertyWrapperRule(primary: p, secondary: WeakAttribute(s), overrideValue: OptionalAttribute())
        )
        #expect(graph.value(of: ruleNoOverride) == 25)

        graph.setValue(7, for: p)
        #expect(graph.value(of: ruleNoOverride) == 27)

        graph.invalidate(sub)
        graph.setValue(8, for: p)
        #expect(graph.value(of: ruleNoOverride) == -2)

        let ruleWithOverride = graph.makeRule(
            PropertyWrapperRule(primary: p, secondary: WeakAttribute(), overrideValue: OptionalAttribute(o))
        )
        #expect(graph.value(of: ruleWithOverride) == 100)
    }
}
