import Testing
@testable import SwiftAttributeGraph

@Suite("AttributeBodyTests")
struct AttributeBodyTests {
    struct TestRule: Rule {
        var value: Int { 42 }
    }

    struct CustomBody: _AttributeBody {
        static var comparisonMode: ComparisonMode { .bitwise }
        static var flags: AttributeTypeFlags { [.dynamicDestruction] }
    }

    struct DummyVisitor: AttributeBodyVisitor {
        var visited = false
        mutating func visit<Body: _AttributeBody>(body: UnsafePointer<Body>) {
            visited = true
        }
    }

    @Test func attributeBodyDefaults() {
        #expect(TestRule.comparisonMode == .equatableAlways)
        #expect(TestRule.flags == [])
        #expect(TestRule._hasDestroySelf == false)
        #expect(CustomBody.comparisonMode == .bitwise)
        #expect(CustomBody.flags.contains(.dynamicDestruction))
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
        #expect(type(of: map).comparisonMode == .equatableAlways)

        struct Container: Equatable { var x: Int }
        let c = graph.makeInput(Container(x: 5))
        let focus = Focus(root: c, keyPath: \Container.x)
        #expect(type(of: focus).comparisonMode == .equatableAlways)
    }

    @Test func visitBodyMethodIsCallable() {
        let graph = Graph()
        let a = graph.makeInput(1)
        var visitor = DummyVisitor()
        a.visitBody(&visitor)
        a.erased.visitBody(&visitor)
    }
}
