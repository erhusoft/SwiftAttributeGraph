import Testing
@testable import SwiftAttributeGraph

/// The creation API spelled as native AttributeGraph spells it: `Attribute(value:)`, `Attribute(type:)`, `Attribute(_:)` for rules and stateful
/// rules, `Attribute(identifier:)`, `WeakAttribute(base:)`, `ComparisonOptions(mode:)` and the Swift names of the tuple types. They take the graph
/// from the current subgraph and stop the program without one. Native lines measured on macOS 15.8.3 (the cases `mode`, `typed-empty`,
/// `value-no-subgraph`, `rule-no-subgraph`, `stateful`, `identifier` of the creation measurements).
@Suite struct AppleCreationAPITests {
    struct PlainRule: Rule { var value: Int { 1 } }
    struct CountingStateful: StatefulRule {
        typealias Value = Int
        mutating func updateValue() { context.value = 3 }
    }

    @Test func comparisonOptionsTakeTheRawValueOfTheMode() { // mode-options raw=0, 1, 2, 3
        #expect(ComparisonOptions(mode: .bitwise).rawValue == 0)
        #expect(ComparisonOptions(mode: .indirect).rawValue == 1)
        #expect(ComparisonOptions(mode: .equatableUnlessPOD).rawValue == 2)
        #expect(ComparisonOptions(mode: .equatableAlways).rawValue == 3)
    }

    @Test func theTupleTypesHaveTheirSwiftNames() {
        let type = TupleType([Int.self, Double.self])
        #expect(type.count == 2)
        #expect(TupleType(Int.self).count == 1)
        let tuple = UnsafeMutableTuple(with: type)
        tuple.initialize(at: 0, to: 4)
        tuple.initialize(at: 1, to: 2.5)
        #expect(UnsafeTuple(tuple)[1] as Double == 2.5)
        tuple.deallocate()
        let options: TupleType.CopyOptions = []
        _ = options
    }

    @Test func aValueAttributeIsMadeInTheCurrentSubgraph() {
        let graph = Graph(); let sg = graph.makeSubgraph()
        let a = graph.withCurrent(sg) { Attribute(value: 5) }
        #expect(graph.value(of: a) == 5)
        #expect(graph.subgraph(of: a) == sg)
        graph.setValue(6, for: a)
        #expect(a.value == 6)
    }

    @Test func aValueAttributeWithoutACurrentSubgraphStopsTheProgram() async { // value-no-subgraph: "attempting to create attribute with no subgraph: External<Int>"
        await #expect(processExitsWith: .failure) {
            _ = Graph()
            _ = Attribute(value: 1)
        }
    }

    @Test func aRuleAttributeRunsAndWithoutASubgraphStopsTheProgram() async { // rule-no-subgraph
        let graph = Graph(); let sg = graph.makeSubgraph()
        let a = graph.withCurrent(sg) { Attribute(PlainRule()) }
        #expect(graph.value(of: a) == 1)
        await #expect(processExitsWith: .failure) {
            _ = Graph()
            _ = Attribute(PlainRule())
        }
    }

    @Test func aStatefulRuleAttributeRuns() { // stateful value=3
        let graph = Graph(); let sg = graph.makeSubgraph()
        let a = graph.withCurrent(sg) { Attribute(CountingStateful()) }
        #expect(graph.value(of: a) == 3)
    }

    @Test func anAttributeBuiltFromItsIdentifierIsTheSameAttribute() { // identifier same=true value=5
        let graph = Graph(); let sg = graph.makeSubgraph()
        let a = graph.withCurrent(sg) { Attribute(value: 5) }
        let b = Attribute<Int>(identifier: a.identifier)
        #expect(b == a)
        #expect(graph.value(of: b) == 5)
    }

    @Test func aTypedAttributeHasNoValueUntilItIsWritten() { // typed-empty: valueState 3 before; value 7 after the write
        let graph = Graph(); let sg = graph.makeSubgraph()
        let a = graph.withCurrent(sg) { Attribute<Int>(type: Int.self) }
        #expect(a.valueState.rawValue == 3)
        graph.setValue(7, for: a)
        #expect(graph.value(of: a) == 7)
        #expect(a.valueState.contains(.valueExists))
    }

    @Test func readingATypedAttributeBeforeItIsWrittenStopsTheProgram() async { // typed-empty-read
        await #expect(processExitsWith: .failure) {
            let graph = Graph(); let sg = graph.makeSubgraph()
            let a = graph.withCurrent(sg) { Attribute<Int>(type: Int.self) }
            _ = graph.value(of: a)
        }
    }

    @Test func aWeakAttributeCanBeBuiltFromItsErasedBase() {
        let graph = Graph(); let sg = graph.makeSubgraph()
        let a = graph.withCurrent(sg) { Attribute(value: 1) }
        let weak = WeakAttribute<Int>(base: AnyWeakAttribute(a.erased))
        #expect(weak == WeakAttribute(a))
    }
}
