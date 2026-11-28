import Testing
@testable import SwiftAttributeGraph

/// `AnyAttribute.unsafeOffset(at:)`: an attribute with no type yet whose value, once cast, is the bytes `offset` into the source.
/// Native lines measured on macOS 15.8.3 (oracle scenarios `u5a` and `u5b`: `any0`/`any8` read through `unsafeCast(to: Int.self)` give
/// `[111, 222]`, on a rule and on an indirect attribute).
@Suite struct AnyAttributeUnsafeOffsetTests {
    struct Pair: Equatable { var first: Int; var second: Int }

    @Test func anErasedOffsetReadsItsBytesOnceCast() { // u5 any0, any8 [111, 222]
        let graph = Graph(); let sg = graph.makeSubgraph()
        let pair = graph.withCurrent(sg) { graph.makeInput(Pair(first: 111, second: 222)) }
        let any0 = graph.withCurrent(sg) { pair.erased.unsafeOffset(at: 0) }
        let any8 = graph.withCurrent(sg) { pair.erased.unsafeOffset(at: 8) }
        #expect(graph.value(of: any0.unsafeCast(to: Int.self)) == 111)
        #expect(graph.value(of: any8.unsafeCast(to: Int.self)) == 222)
    }

    @Test func anErasedOffsetOfARuleReads() { // u5a [111, 222, 111, 222]
        let graph = Graph(); let sg = graph.makeSubgraph()
        let input = graph.withCurrent(sg) { graph.makeInput(Pair(first: 111, second: 222)) }
        let rule = graph.withCurrent(sg) { graph.makeRule { input.value } }
        let any0 = graph.withCurrent(sg) { rule.erased.unsafeOffset(at: 0) }
        let any8 = graph.withCurrent(sg) { rule.erased.unsafeOffset(at: 8) }
        #expect(any0.unsafeCast(to: Int.self).wrappedValue == 111)
        #expect(any8.unsafeCast(to: Int.self).wrappedValue == 222)
    }

    @Test func anErasedOffsetOfAnIndirectAttributeReads() { // u5b
        let graph = Graph(); let sg = graph.makeSubgraph()
        let input = graph.withCurrent(sg) { graph.makeInput(Pair(first: 111, second: 222)) }
        let indirect = graph.withCurrent(sg) { graph.makeIndirect(input) }
        let any0 = graph.withCurrent(sg) { indirect.erased.unsafeOffset(at: 0) }
        let any8 = graph.withCurrent(sg) { indirect.erased.unsafeOffset(at: 8) }
        #expect(graph.value(of: any0.unsafeCast(to: Int.self)) == 111)
        #expect(graph.value(of: any8.unsafeCast(to: Int.self)) == 222)
    }

    @Test func anErasedOffsetFollowsItsSource() {
        let graph = Graph(); let sg = graph.makeSubgraph()
        let pair = graph.withCurrent(sg) { graph.makeInput(Pair(first: 111, second: 222)) }
        let any8 = graph.withCurrent(sg) { pair.erased.unsafeOffset(at: 8) }
        let cast = any8.unsafeCast(to: Int.self)
        #expect(graph.value(of: cast) == 222)
        graph.setValue(Pair(first: 333, second: 444), for: pair)
        #expect(graph.value(of: cast) == 444)
    }

    @Test func castingTwiceToTheSameTypeGivesTheSameAttribute() {
        let graph = Graph(); let sg = graph.makeSubgraph()
        let pair = graph.withCurrent(sg) { graph.makeInput(Pair(first: 1, second: 2)) }
        let any8 = graph.withCurrent(sg) { pair.erased.unsafeOffset(at: 8) }
        #expect(any8.unsafeCast(to: Int.self) == any8.unsafeCast(to: Int.self))
    }

    @Test func anErasedOffsetIsNotDirectNorIndirect() async { // u3a, u3b
        await #expect(processExitsWith: .failure) {
            let graph = Graph(); let sg = graph.makeSubgraph()
            let pair = graph.withCurrent(sg) { graph.makeInput(Pair(first: 1, second: 2)) }
            let any8 = graph.withCurrent(sg) { pair.erased.unsafeOffset(at: 8) }
            _ = any8.valueType
        }
        await #expect(processExitsWith: .failure) {
            let graph = Graph(); let sg = graph.makeSubgraph()
            let pair = graph.withCurrent(sg) { graph.makeInput(Pair(first: 1, second: 2)) }
            let any8 = graph.withCurrent(sg) { pair.erased.unsafeOffset(at: 8) }
            _ = any8.indirectDependency
        }
    }

    @Test func anOffsetOutOfRangeStopsTheProgramWhenRead() async { // u4
        await #expect(processExitsWith: .failure) {
            let graph = Graph(); let sg = graph.makeSubgraph()
            let pair = graph.withCurrent(sg) { graph.makeInput(Pair(first: 1, second: 2)) }
            let far = graph.withCurrent(sg) { pair.erased.unsafeOffset(at: 64) }
            _ = graph.value(of: far.unsafeCast(to: Int.self))
        }
    }

    // Creating one with no current subgraph stops the program natively (`attempting to create attribute with no subgraph`). The engine does
    // not stop for any attribute made on a graph whose current subgraph was never set or cleared: the known difference `b1`.
}
