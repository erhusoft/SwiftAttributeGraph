import Testing
@testable import SwiftAttributeGraph

/// Identity and slot storage: an `AttributeID` is a slot index plus a generation, freed slots are reused, and an ID of
/// a dead attribute never resolves to the attribute that reuses its slot.
@Suite struct IdentityTests {
    private func index(of id: AttributeID) -> UInt64 { id.rawValue & 0xFFFF_FFFF }

    @Test func eachAttributeGetsADistinctNonNullID() {
        let graph = Graph()
        var seen = Set<AttributeID>()
        for value in 0..<100 {
            let id = graph.makeInput(value).id
            #expect(id.rawValue != 0)
            #expect(seen.insert(id).inserted)
        }
        #expect(graph.nodeCount == 100)
    }

    @Test func aReadReturnsWhatWasStored() {
        let graph = Graph()
        let a = graph.makeInput(41)
        let s = graph.makeInput("hello")
        #expect(graph.value(of: a) == 41)
        #expect(graph.value(of: s) == "hello")
    }

    @Test func invalidatingASubgraphFreesItsAttributesAndOnlyThose() {
        let graph = Graph()
        let keep = graph.makeInput(1)
        let sub = graph.makeSubgraph()
        let (a, b) = graph.withCurrent(sub) { (graph.makeInput(2), graph.makeInput(3)) }
        #expect(graph.nodeCount == 3)
        sub.invalidate()
        #expect(graph.nodeCount == 1)
        #expect(graph.contains(keep.id))
        #expect(!graph.contains(a.id))
        #expect(!graph.contains(b.id))
    }

    @Test func aFreedSlotIsReusedWithANewGeneration() {
        let graph = Graph()
        let sub = graph.makeSubgraph()
        let a = graph.withCurrent(sub) { graph.makeInput(1) }
        sub.invalidate()
        let b = graph.makeInput(2)
        #expect(index(of: b.id) == index(of: a.id), "the freed slot should be reused")
        #expect(b.id != a.id, "a reused slot must get a new generation")
    }

    @Test func aStaleIDNeverResolvesToTheAttributeThatReusesItsSlot() {
        let graph = Graph()
        let sub = graph.makeSubgraph()
        let stale = graph.withCurrent(sub) { graph.makeInput(1) }.id
        sub.invalidate()
        let fresh = graph.makeInput(2)
        #expect(!graph.contains(stale))
        #expect(graph.contains(fresh.id))
        #expect(graph.value(of: fresh) == 2)
    }

    @Test func theNullIDIsNeverHandedOut() {
        let graph = Graph()
        for round in 0..<10 {
            let sub = graph.makeSubgraph()
            let id = graph.withCurrent(sub) { graph.makeInput(round) }.id
            #expect(id != AttributeID(rawValue: 0))
            sub.invalidate()
        }
    }

    @Test func churnKeepsTheSlotTableBounded() {
        let graph = Graph()
        for round in 0..<200 {
            let sub = graph.makeSubgraph()
            graph.withCurrent(sub) { for _ in 0..<50 { _ = graph.makeInput(round) } }
            sub.invalidate()
        }
        #expect(graph.nodeCount == 0)
        let probe = graph.makeInput(0)
        #expect(index(of: probe.id) <= 51, "freed slots should be reused instead of growing the table")
    }

    @Test func attributesAreBornInTheCurrentSubgraph() {
        let graph = Graph()
        let outer = graph.makeSubgraph()
        let inner = graph.makeSubgraph()
        let o = graph.withCurrent(outer) { () -> Attribute<Int> in
            let o = graph.makeInput(1)
            _ = graph.withCurrent(inner) { graph.makeInput(2) }
            return o
        }
        #expect(graph.subgraph(of: o.id) == outer)
        inner.invalidate()
        #expect(graph.nodeCount == 1)
        outer.invalidate()
        #expect(graph.nodeCount == 0)
    }

    @Test func aSubgraphThatWasInvalidatedCannotBeInvalidatedTwice() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            let sub = graph.makeSubgraph()
            sub.invalidate()
            sub.invalidate()
        }
    }

    @Test func theRootSubgraphCannotBeInvalidated() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            graph.rootSubgraph.invalidate()
        }
    }
}
