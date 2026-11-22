import Testing
@testable import SwiftAttributeGraph

@Suite("AnyOptionalAttributeTests")
struct AnyOptionalAttributeTests {
    @Test func defaultInitIsEmpty() {
        let opt = AnyOptionalAttribute()
        #expect(opt.attribute == nil)
        #expect(opt.identifier.id == AttributeID.nil)
        #expect(opt.description == "nil")
    }

    @Test func initWithAnyAttribute() {
        let graph = Graph()
        let a = graph.makeInput(100)
        let anyA = a.erased
        var opt = AnyOptionalAttribute(anyA)

        #expect(opt.attribute == anyA)
        #expect(opt.identifier == anyA)
        #expect(opt.description.contains("AnyOptionalAttribute"))

        // Mutating attribute
        opt.attribute = nil
        #expect(opt.attribute == nil)
        #expect(opt.identifier.id == AttributeID.nil)

        // Mutating identifier
        opt.identifier = anyA
        #expect(opt.attribute == anyA)
        opt.identifier = AnyAttribute(id: AttributeID.nil)
        #expect(opt.attribute == nil)
    }

    @Test func conversionToAndFromTypedOptionalAttribute() {
        let graph = Graph()
        let a = graph.makeInput("hello")
        let typed = OptionalAttribute(a)

        let anyOpt = AnyOptionalAttribute(typed)
        #expect(anyOpt.attribute == a.erased)

        let castBack = anyOpt.unsafeCast(to: String.self)
        #expect(castBack.attribute == a)

        let fromBase = OptionalAttribute<String>(base: anyOpt)
        #expect(fromBase.attribute == a)
        #expect(fromBase.base == anyOpt)
    }

    @Test func conversionFromWeakAttribute() {
        let graph = Graph()
        let a = graph.makeInput(42)
        let weakA = AnyWeakAttribute(a.erased)
        let anyOpt = AnyOptionalAttribute(weakA)
        #expect(anyOpt.attribute == a.erased)

        let typedWeak = WeakAttribute(a)
        let typedOpt = OptionalAttribute(typedWeak)
        #expect(typedOpt.attribute == a)
    }

    @Test func mapAndEquality() {
        let graph = Graph()
        let a = graph.makeInput(55)
        let opt1 = AnyOptionalAttribute(a.erased)
        let opt2 = AnyOptionalAttribute(a.erased)
        let empty = AnyOptionalAttribute()

        #expect(opt1 == opt2)
        #expect(opt1 != empty)

        let mapped = opt1.map { $0.id.index }
        #expect(mapped == a.id.index)
        #expect(empty.map { $0.id.index } == nil)
    }

    @Test func currentAttributeReflectsRunningRule() {
        let graph = Graph()
        let input = graph.makeInput(1)
        var insideCurrent: AnyOptionalAttribute?

        let rule = graph.makeRule {
            insideCurrent = AnyOptionalAttribute.current
            return input.value + 10
        }

        #expect(AnyOptionalAttribute.current.attribute == nil)
        #expect(graph.value(of: rule) == 11)
        #expect(insideCurrent?.attribute == rule.erased)
        #expect(AnyOptionalAttribute.current.attribute == nil)
    }
}
