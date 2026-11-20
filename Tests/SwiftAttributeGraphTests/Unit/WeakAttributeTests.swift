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

        sub.invalidate()
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
        sub.invalidate()
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

        sub.invalidate()
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

        sub.invalidate()
        graph.setValue(8, for: p)
        #expect(graph.value(of: ruleNoOverride) == -2)

        let ruleWithOverride = graph.makeRule(
            PropertyWrapperRule(primary: p, secondary: WeakAttribute(), overrideValue: OptionalAttribute(o))
        )
        #expect(graph.value(of: ruleWithOverride) == 100)
    }

    @Test func weakAttributeValueAndAttributeWorkOutsideRuleAndAcrossGraphs() {
        let g1 = Graph()
        let root1 = g1.makeSubgraph()
        let child1 = g1.makeSubgraph(parent: root1)

        // (a) Read a live WeakAttribute outside a rule via weak.value and weak.attribute:
        let src1 = g1.withCurrent(child1) { g1.makeInput(5) }
        let counter1 = Counter()
        let target1 = g1.withCurrent(child1) {
            g1.makeRule {
                counter1.runs += 1
                return src1.value + 10
            }
        }
        let weak1 = WeakAttribute(target1)
        #expect(weak1.attribute == target1)

        // (c) Target is dirty (initial): reading weak1.value outside a rule brings it up to date without dependency:
        #expect(weak1.value == 15)
        #expect(counter1.runs == 1)

        // Dirtying target1 again and reading outside a rule updates it:
        g1.setValue(20, for: src1)
        #expect(weak1.value == 30)
        #expect(counter1.runs == 2)
        // Reading while clean does not re-run:
        #expect(weak1.value == 30)
        #expect(counter1.runs == 2)

        // (d) Reading with options 0, 2 (.dependency), 4 (.noDependency) outside a rule updates and creates no edge:
        g1.setValue(30, for: src1)
        #expect(g1.value(of: weak1, options: []) == 40)
        g1.setValue(40, for: src1)
        #expect(g1.value(of: weak1, options: .dependency) == 50)
        g1.setValue(50, for: src1)
        #expect(g1.value(of: weak1, options: .noDependency) == 60)
        #expect(counter1.runs == 5)

        g1.setValue(60, for: src1)
        let cv0 = weak1.changedValue(options: [])
        #expect(cv0?.value == 70 && cv0?.changed == false)
        let cv2 = weak1.changedValue(options: .dependency)
        #expect(cv2?.value == 70 && cv2?.changed == false)
        let cv4 = weak1.changedValue(options: .noDependency)
        #expect(cv4?.value == 70 && cv4?.changed == false)

        // (e) Read a WeakAttribute of another graph outside a rule:
        let g2 = Graph()
        let sub2 = g2.makeSubgraph()
        let src2 = g2.withCurrent(sub2) { g2.makeInput(7) }
        let r2 = g2.withCurrent(sub2) { g2.makeRule { src2.value * 2 } }
        let weak2 = WeakAttribute(r2)
        #expect(weak2.attribute == r2)
        #expect(weak2.value == 14)
        #expect(g1.value(of: weak2) == 14)
        #expect(g1.attribute(of: weak2) == r2)
        g2.setValue(9, for: src2)
        #expect(weak2.value == 18)
        #expect(g1.value(of: weak2) == 18)

        // (b) After invalidating the target's subgraph, reading outside a rule returns nil:
        g1.invalidate(child1)
        #expect(weak1.attribute == nil)
        #expect(weak1.value == nil)
        #expect(weak1.changedValue() == nil)
        #expect(g1.value(of: weak1, options: .noDependency) == nil)

        g2.invalidate(sub2)
        #expect(weak2.attribute == nil)
        #expect(weak2.value == nil)
        #expect(g1.value(of: weak2) == nil)
    }

    @Test func weakAttributeValueWithNoDependencyOptionInsideRuleDoesNotRecordEdge() {
        let graph = Graph()
        let src = graph.makeInput(10)
        let weak = WeakAttribute(src)
        let counter = Counter()
        let reader = graph.makeRule {
            counter.runs += 1
            return graph.value(of: weak, options: .noDependency) ?? -1
        }
        #expect(graph.value(of: reader) == 10)
        #expect(counter.runs == 1)
        graph.setValue(25, for: src)
        #expect(graph.value(of: reader) == 10)
        #expect(counter.runs == 1)
    }
}
