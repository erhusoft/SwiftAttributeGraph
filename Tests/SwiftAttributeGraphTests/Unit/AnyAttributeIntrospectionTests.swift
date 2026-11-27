import Testing
@testable import SwiftAttributeGraph

/// `AnyAttribute.valueType`, `_bodyType`, `_bodyPointer`, `indirectDependency` and `Attribute.unsafeOffset(at:as:)`. Native
/// lines measured on macOS 15.8.3 by oracle scenarios `v*`, `b*`, `p*`, `d*`, `u*` (in the comments).
@Suite struct AnyAttributeIntrospectionTests {
    struct Pair: Equatable { var first: Int; var second: Int }

    struct StructRule: Rule {
        var number: Int
        var text: String
        var value: Int { number }
    }

    @Test func theValueTypeOfAnInputAndOfARuleIsTheTypeOfTheirValue() { // v1, v2 [Swift.Int]
        let graph = Graph(); let sg = graph.makeSubgraph()
        let input = graph.withCurrent(sg) { graph.makeInput(7) }
        let rule = graph.withCurrent(sg) { graph.makeRule { 1 } }
        #expect(ObjectIdentifier(input.erased.valueType) == ObjectIdentifier(Int.self))
        #expect(ObjectIdentifier(rule.erased.valueType) == ObjectIdentifier(Int.self))
    }

    @Test func aCastDoesNotChangeTheValueType() { // v5 [Swift.Int]
        let graph = Graph(); let sg = graph.makeSubgraph()
        let input = graph.withCurrent(sg) { graph.makeInput(7) }
        let cast: Attribute<Double> = input.erased.unsafeCast(to: Double.self)
        #expect(ObjectIdentifier(cast.erased.valueType) == ObjectIdentifier(Int.self))
    }

    @Test func theBodyTypeOfAnInputIsExternal() { // b1 [AttributeGraph.External<Swift.Int>]
        let graph = Graph(); let sg = graph.makeSubgraph()
        let input = graph.withCurrent(sg) { graph.makeInput(7) }
        #expect(ObjectIdentifier(input.erased._bodyType) == ObjectIdentifier(External<Int>.self))
    }

    @Test func theBodyTypeOfARuleIsTheRule() { // b2
        let graph = Graph(); let sg = graph.makeSubgraph()
        let rule = graph.withCurrent(sg) { graph.makeRule(StructRule(number: 123, text: "hola")) }
        #expect(ObjectIdentifier(rule.erased._bodyType) == ObjectIdentifier(StructRule.self))
    }

    @Test func theBodyPointerOfARuleReadsBackTheRule() { // p1 [true, true, 123, hola]
        let graph = Graph(); let sg = graph.makeSubgraph()
        let rule = graph.withCurrent(sg) { graph.makeRule(StructRule(number: 123, text: "hola")) }
        let body = rule.erased._bodyPointer.assumingMemoryBound(to: StructRule.self).pointee
        #expect(body.number == 123)
        #expect(body.text == "hola")
    }

    @Test func anIndirectAttributeStopsTheProgramOnValueType() async { // v3 "non-direct attribute id"
        await #expect(processExitsWith: .failure) {
            let graph = Graph(); let sg = graph.makeSubgraph()
            let input = graph.withCurrent(sg) { graph.makeInput(7) }
            let indirect = graph.withCurrent(sg) { graph.makeIndirect(input) }
            _ = indirect.erased.valueType
        }
    }

    @Test func anIndirectAttributeStopsTheProgramOnBodyType() async { // b4
        await #expect(processExitsWith: .failure) {
            let graph = Graph(); let sg = graph.makeSubgraph()
            let input = graph.withCurrent(sg) { graph.makeInput(7) }
            let indirect = graph.withCurrent(sg) { graph.makeIndirect(input) }
            _ = indirect.erased._bodyType
        }
    }

    @Test func anIndirectAttributeStopsTheProgramOnBodyPointer() async { // p3
        await #expect(processExitsWith: .failure) {
            let graph = Graph(); let sg = graph.makeSubgraph()
            let input = graph.withCurrent(sg) { graph.makeInput(7) }
            let indirect = graph.withCurrent(sg) { graph.makeIndirect(input) }
            _ = indirect.erased._bodyPointer
        }
    }

    @Test func theIndirectDependencyIsNilThenTheOneAssignedThenNilAgain() { // d2 [false], d3 eq=true, d4 [false]
        let graph = Graph(); let sg = graph.makeSubgraph()
        let input = graph.withCurrent(sg) { graph.makeInput(7) }
        let dep = graph.withCurrent(sg) { graph.makeInput(1) }
        let indirect = graph.withCurrent(sg) { graph.makeIndirect(input) }.erased
        #expect(indirect.indirectDependency == nil)
        indirect.indirectDependency = dep.erased
        #expect(indirect.indirectDependency == dep.erased)
        indirect.indirectDependency = nil
        #expect(indirect.indirectDependency == nil)
    }

    @Test func aDirectAttributeStopsTheProgramOnIndirectDependency() async { // d1 ("not an indirect attribute")
        await #expect(processExitsWith: .failure) {
            let graph = Graph(); let sg = graph.makeSubgraph()
            let input = graph.withCurrent(sg) { graph.makeInput(7) }
            _ = input.erased.indirectDependency
        }
    }

    @Test func aDependencyFromAnotherSubgraphStopsTheProgram() async { // d3-other-subgraph
        await #expect(processExitsWith: .failure) {
            let graph = Graph(); let a = graph.makeSubgraph(); let b = graph.makeSubgraph()
            let input = graph.withCurrent(a) { graph.makeInput(7) }
            let dep = graph.withCurrent(b) { graph.makeInput(1) }
            let indirect = graph.withCurrent(a) { graph.makeIndirect(input) }.erased
            indirect.indirectDependency = dep.erased
        }
    }

    @Test func anOffsetAttributeReadsTheBytesAtItsOffset() { // u1 [111, 222]
        let graph = Graph(); let sg = graph.makeSubgraph()
        let pair = graph.withCurrent(sg) { graph.makeInput(Pair(first: 111, second: 222)) }
        let first = graph.withCurrent(sg) { pair.unsafeOffset(at: 0, as: Int.self) }
        let second = graph.withCurrent(sg) { pair.unsafeOffset(at: 8, as: Int.self) }
        #expect(graph.value(of: first) == 111)
        #expect(graph.value(of: second) == 222)
    }

    @Test func anOffsetAttributeFollowsItsInput() { // u2 [[111, 222], [333, 444]]
        let graph = Graph(); let sg = graph.makeSubgraph()
        let pair = graph.withCurrent(sg) { graph.makeInput(Pair(first: 111, second: 222)) }
        let first = graph.withCurrent(sg) { pair.unsafeOffset(at: 0, as: Int.self) }
        let second = graph.withCurrent(sg) { pair.unsafeOffset(at: 8, as: Int.self) }
        #expect([graph.value(of: first), graph.value(of: second)] == [111, 222])
        graph.setValue(Pair(first: 333, second: 444), for: pair)
        #expect([graph.value(of: first), graph.value(of: second)] == [333, 444])
    }

    @Test func anOffsetAttributeOfARuleAndOfAnIndirectAttributeAlsoRead() { // u5a, u5b [111, 222, 111, 222]
        let graph = Graph(); let sg = graph.makeSubgraph()
        let input = graph.withCurrent(sg) { graph.makeInput(Pair(first: 111, second: 222)) }
        let rule = graph.withCurrent(sg) { graph.makeRule { input.value } }
        let indirect = graph.withCurrent(sg) { graph.makeIndirect(input) }
        let fromRule = graph.withCurrent(sg) { (rule.unsafeOffset(at: 0, as: Int.self), rule.unsafeOffset(at: 8, as: Int.self)) }
        let fromIndirect = graph.withCurrent(sg) { (indirect.unsafeOffset(at: 0, as: Int.self), indirect.unsafeOffset(at: 8, as: Int.self)) }
        #expect([graph.value(of: fromRule.0), graph.value(of: fromRule.1)] == [111, 222])
        #expect([graph.value(of: fromIndirect.0), graph.value(of: fromIndirect.1)] == [111, 222])
    }

    @Test func anOffsetOutOfRangeStopsTheProgramWhenRead() async { // u4 ("invalid value size for attribute")
        await #expect(processExitsWith: .failure) {
            let graph = Graph(); let sg = graph.makeSubgraph()
            let pair = graph.withCurrent(sg) { graph.makeInput(Pair(first: 1, second: 2)) }
            let far = graph.withCurrent(sg) { pair.unsafeOffset(at: 64, as: Int.self) }
            _ = graph.value(of: far)
        }
    }

    @Test func anOffsetAttributeIsNotDirectNorIndirect() async { // u3a, u3b
        await #expect(processExitsWith: .failure) {
            let graph = Graph(); let sg = graph.makeSubgraph()
            let pair = graph.withCurrent(sg) { graph.makeInput(Pair(first: 1, second: 2)) }
            let first = graph.withCurrent(sg) { pair.unsafeOffset(at: 0, as: Int.self) }
            _ = first.erased.valueType
        }
        await #expect(processExitsWith: .failure) {
            let graph = Graph(); let sg = graph.makeSubgraph()
            let pair = graph.withCurrent(sg) { graph.makeInput(Pair(first: 1, second: 2)) }
            let first = graph.withCurrent(sg) { pair.unsafeOffset(at: 0, as: Int.self) }
            _ = first.erased.indirectDependency
        }
    }
}
