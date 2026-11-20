import Testing
@testable import SwiftAttributeGraph

@Suite("AppleNamesFlagsTests")
struct AppleNamesFlagsTests {
    /// Apple's subgraph methods `intersects(flags:)`, `isDirty(flags:)` and `update(flags:)` [O, native headers
    /// AGSubgraph.h], on the handle.
    @Test func subgraphFlagMethodsMatchTheAppleNames() {
        let graph = Graph()
        let subgraph = graph.makeSubgraph()
        let flagged = graph.withCurrent(subgraph) {
            graph.makeRule { 1 }
        }
        graph.setFlags(AttributeFlags(rawValue: 0x2), for: flagged)

        #expect(subgraph.intersects(flags: AttributeFlags(rawValue: 0x2)))
        #expect(subgraph.intersects(flags: AttributeFlags(rawValue: 0x4)) == false)

        graph.invalidate(subgraph)
        #expect(subgraph.isValid == false)

        let fresh = graph.makeSubgraph()
        _ = graph.withCurrent(fresh) { graph.makeRule { 1 } }
        fresh.update(flags: .all)
        #expect(fresh.isDirty(flags: .all) == false)
    }
}
