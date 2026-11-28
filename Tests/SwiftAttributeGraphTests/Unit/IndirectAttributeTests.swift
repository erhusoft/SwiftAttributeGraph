import Testing
@testable import SwiftAttributeGraph

@Suite("IndirectAttributeTests")
struct IndirectAttributeTests {
    struct Model: Equatable {
        var count: Int
        var title: String
    }

    @Test
    func indirectAttributeBasics() {
        let graph = Graph()
        let source1 = graph.makeInput(Model(count: 10, title: "first"))
        var indirect = IndirectAttribute(source: source1)

        #expect(indirect.attribute.id != source1.id)
        #expect(indirect.source == source1)
        #expect(indirect.identifier == AnyAttribute(id: indirect.attribute.id))
        #expect(indirect.projectedValue == indirect.attribute)
        #expect(graph.value(of: indirect.attribute) == Model(count: 10, title: "first"))

        let rule = graph.makeRule {
            indirect.wrappedValue
        }
        #expect(graph.value(of: rule) == Model(count: 10, title: "first"))

        let source2 = graph.makeInput(Model(count: 20, title: "second"))
        indirect.source = source2
        #expect(indirect.source == source2)
        #expect(graph.value(of: rule) == Model(count: 20, title: "second"))
    }

    @Test
    func indirectAttributeDynamicMemberLookup() {
        let graph = Graph()
        let source = graph.makeInput(Model(count: 42, title: "answer"))
        let indirect = IndirectAttribute(source: source)

        let rule = graph.makeRule {
            indirect.count.value
        }
        #expect(graph.value(of: rule) == 42)

        let ruleTitle = graph.makeRule {
            indirect.title.value
        }
        #expect(graph.value(of: ruleTitle) == "answer")
    }

    @Test
    func indirectAttributeResetSource() {
        let graph = Graph()
        let source1 = graph.makeInput(100)
        let source2 = graph.makeInput(200)
        var indirect = IndirectAttribute(source: source1)
        #expect(indirect.source == source1)

        indirect.source = source2
        #expect(indirect.source == source2)

        indirect.resetSource()
        #expect(indirect.source == source1)
    }

    @Test
    func indirectAttributeDependency() {
        let graph = Graph()
        let source = graph.makeInput(1)
        var indirect = IndirectAttribute(source: source)
        #expect(indirect.dependency == nil)

        let dep = graph.makeInput(2)
        indirect.dependency = AnyAttribute(id: dep.id)
        #expect(indirect.dependency == AnyAttribute(id: dep.id))

        indirect.dependency = nil
        #expect(indirect.dependency == nil)
    }

    @Test
    func indirectAttributeChangedValue() {
        let graph = Graph()
        let source = graph.makeInput(1)
        let indirect = IndirectAttribute(source: source)

        let res = indirect.changedValue(options: [])
        #expect(res.value == 1)
        #expect(res.changed == false)
    }

    @Test
    func indirectAttributeHashableAndEquatable() {
        let graph = Graph()
        let source1 = graph.makeInput(1)
        let indirect1 = IndirectAttribute(source: source1)
        let indirect2 = indirect1

        #expect(indirect1 == indirect2)
        #expect(indirect1.hashValue == indirect2.hashValue)
    }
}
