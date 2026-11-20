import Testing
@testable import SwiftAttributeGraph

/// `AnyWeakAttribute` (`AGWeakAttribute`), the untyped weak reference that `WeakAttribute<Value>` wraps. Apple's
/// behavior, measured with the `any-weak-attribute` oracle scenario: an empty one resolves to `nil`, one made from a live
/// attribute resolves to it, one made from an attribute whose subgraph was invalidated resolves to `nil`, and two of the
/// same attribute compare equal.
@Suite struct AnyWeakAttributeTests {
    @Test func emptyResolvesToNil() {
        let weak = AnyWeakAttribute(nil)
        #expect(weak.attribute == nil)
    }

    @Test func aLiveAttributeResolvesToItself() {
        let graph = Graph()
        let input = graph.makeInput(1)
        let weak = AnyWeakAttribute(input.erased)
        #expect(weak.attribute == input.erased)
    }

    @Test func anAttributeWhoseSubgraphWasInvalidatedResolvesToNil() {
        let graph = Graph()
        let subgraph = graph.makeSubgraph()
        let input = graph.withCurrent(subgraph) { graph.makeInput(1) }
        let weak = AnyWeakAttribute(input.erased)
        #expect(weak.attribute != nil)
        subgraph.invalidate()
        #expect(weak.attribute == nil)
    }

    @Test func twoWeakReferencesToTheSameAttributeAreEqual() {
        let graph = Graph()
        let input = graph.makeInput(1)
        #expect(AnyWeakAttribute(input.erased) == AnyWeakAttribute(input.erased))
        #expect(AnyWeakAttribute(nil) != AnyWeakAttribute(input.erased))
    }

    @Test func aTypedWeakAttributeConvertsToTheUntypedOne() {
        let graph = Graph()
        let input = graph.makeInput(3)
        let typed = WeakAttribute(input)
        #expect(AnyWeakAttribute(typed).attribute == input.erased)
    }
}
