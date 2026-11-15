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
}
