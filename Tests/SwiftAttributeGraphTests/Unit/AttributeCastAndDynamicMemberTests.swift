import Testing
@testable import SwiftAttributeGraph

/// `unsafeCast(to:)` on `Attribute` and `AnyAttribute`, and the dynamic member subscript of `WeakAttribute` and
/// `OptionalAttribute`. Oracle scenarios `cov79-a-attr-unsafe-cast` (native `eq=[true, true, true]`) and
/// `cov79-a-weak-opt-dynamic-member` (native `v1=[10, 4, 20, -1]`, `v2=[30, 40]`).
@Suite struct AttributeCastAndDynamicMemberTests {
    struct Pair { var left: Int; var right: Int }

    @Test func unsafeCastKeepsTheSameAttribute() {
        let graph = Graph()
        let a = graph.makeInput(10)
        let erased: AnyAttribute = a.erased

        let fromErased: Attribute<Int> = erased.unsafeCast(to: Int.self)
        let fromTyped: Attribute<Int> = a.unsafeCast(to: Int.self)

        #expect(fromErased == a)
        #expect(fromTyped == a)
        #expect(fromErased.erased == erased)
    }

    @Test func unsafeCastReinterpretsTheValueTypeWithoutChangingTheIdentity() {
        let graph = Graph()
        let a = graph.makeInput(10)

        let asOther: Attribute<UInt> = a.unsafeCast(to: UInt.self)

        #expect(asOther.id == a.id)
    }

    @Test func aWeakAttributeProjectsAFieldOfItsTarget() {
        let graph = Graph()
        let pair = graph.makeInput(Pair(left: 10, right: 20))
        let weak = WeakAttribute(pair)

        let left: Attribute<Int>? = weak.left

        #expect(left != nil)
        #expect(left.map { graph.value(of: $0) } == 10)
        graph.setValue(Pair(left: 30, right: 40), for: pair)
        #expect(left.map { graph.value(of: $0) } == 30)
    }

    @Test func aWeakAttributeThatIsEmptyOrDeadProjectsNothing() {
        let graph = Graph()
        let empty = WeakAttribute<Pair>()
        #expect(empty.left == nil)

        let subgraph = graph.makeSubgraph()
        let pair = graph.withCurrent(subgraph) { graph.makeInput(Pair(left: 3, right: 4)) }
        let dead = WeakAttribute(pair)
        graph.invalidate(subgraph)

        #expect(dead.right == nil)
    }

    @Test func anOptionalAttributeProjectsAFieldWhenItHoldsAnAttribute() {
        let graph = Graph()
        let pair = graph.makeInput(Pair(left: 10, right: 20))
        let some = OptionalAttribute(pair)
        let none = OptionalAttribute<Pair>(nil)

        let right: Attribute<Int>? = some.right

        #expect(right.map { graph.value(of: $0) } == 20)
        #expect(none.right == nil)
        graph.setValue(Pair(left: 30, right: 40), for: pair)
        #expect(right.map { graph.value(of: $0) } == 40)
    }
}
