import Testing
@testable import SwiftAttributeGraph

@Suite("AttributeBodyTests")
struct AttributeBodyTests {
    struct TestRule: Rule {
        var value: Int { 42 }
    }

    struct CustomBody: _AttributeBody {
        static var comparisonMode: ComparisonMode { .bitwise }
        static var flags: AttributeTypeFlags { [.hasDestroySelf] }
    }

    struct DummyVisitor: AttributeBodyVisitor {
        var visited = false
        mutating func visit<Body: _AttributeBody>(body: UnsafePointer<Body>) {
            visited = true
        }
    }

    @Test func attributeBodyDefaults() {
        #expect(TestRule.comparisonMode == .equatableUnlessPOD)   // native: mode 2, flags 8 (oracle scenarios f1 to f3)
        #expect(TestRule.flags == [.mainThread])
        #expect(TestRule._hasDestroySelf == false)
        #expect(CustomBody.comparisonMode == .bitwise)
        #expect(CustomBody.flags.contains(.hasDestroySelf))
    }

    @Test func externalBodyTypes() {
        let ext = External<Int>()
        #expect(ext.description == "External<Int>")
        #expect(External<Int>.comparisonMode == .equatableAlways)

        let untypedExt = _External()
        #expect(untypedExt.description == "_External")
    }

    @Test func mapAndFocusConformToAttributeBody() {
        let graph = Graph()
        let a = graph.makeInput(10)
        let map = Map(a) { $0 * 2 }
        #expect(type(of: map).comparisonMode == .equatableUnlessPOD)

        struct Container: Equatable { var x: Int }
        let c = graph.makeInput(Container(x: 5))
        let focus = Focus(root: c, keyPath: \Container.x)
        #expect(type(of: focus).comparisonMode == .equatableUnlessPOD)
    }

    @Test func visitBodyMethodIsCallable() {
        let graph = Graph()
        let a = graph.makeInput(1)
        var visitor = DummyVisitor()
        a.visitBody(&visitor)
        a.erased.visitBody(&visitor)
    }

    struct FactorRule: Rule {
        let factor: Int
        var value: Int { factor * 2 }
    }

    struct FactorStatefulRule: StatefulRule {
        typealias Value = Int
        let factor: Int
        mutating func updateValue() { context.value = factor }
    }

    struct BodyRecorder: AttributeBodyVisitor {
        var visits = 0
        var bodyIsFactorRule = false
        var bodyIsFactorStatefulRule = false
        var seenFactor = -1
        mutating func visit<Body: _AttributeBody>(body: UnsafePointer<Body>) {
            visits += 1
            bodyIsFactorRule = Body.self == FactorRule.self
            bodyIsFactorStatefulRule = Body.self == FactorStatefulRule.self
            if let rule = body.pointee as? FactorRule { seenFactor = rule.factor }
            if let rule = body.pointee as? FactorStatefulRule { seenFactor = rule.factor }
        }
    }

    /// `visitBody` hands the stored body of a rule to the visitor, with its real type. Oracle scenario `cov79-e-visit-body`:
    /// native gives `typed=[true, 17]` and `erased=[true, 17]`; before this the method did nothing.
    @Test func visitBodyGivesTheStoredBodyOfATypedRule() {
        let graph = Graph()
        let rule = graph.makeRule(FactorRule(factor: 17))

        var typed = BodyRecorder()
        rule.visitBody(&typed)
        var erased = BodyRecorder()
        rule.erased.visitBody(&erased)

        #expect(typed.visits == 1 && typed.bodyIsFactorRule && typed.seenFactor == 17)
        #expect(erased.visits == 1 && erased.bodyIsFactorRule && erased.seenFactor == 17)
    }

    @Test func visitBodyGivesTheStoredBodyOfAStatefulRule() {
        let graph = Graph()
        let rule = graph.makeStatefulRule(FactorStatefulRule(factor: 5))

        var recorder = BodyRecorder()
        rule.visitBody(&recorder)

        #expect(recorder.visits == 1 && recorder.bodyIsFactorStatefulRule && recorder.seenFactor == 5)
    }

    @Test func visitBodyDoesNothingForANodeWithoutATypedBody() {
        let graph = Graph()
        let input = graph.makeInput(3)

        var recorder = BodyRecorder()
        input.visitBody(&recorder)

        #expect(recorder.visits == 0)
    }
}
