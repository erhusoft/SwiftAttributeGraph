import Testing
@testable import SwiftAttributeGraph

/// `AGGraphBeginDeferringSubgraphInvalidation` / `AGGraphEndDeferringSubgraphInvalidation`. Measured with the `deferring`
/// oracle scenario on macOS 15.8: the first begin reports `false`, a nested begin reports `true`, and an invalidated
/// subgraph is not valid at once even while deferring. Deferring only holds back the freeing and the observer callbacks.
@Suite struct DeferringSubgraphInvalidationTests {
    @Test func beginReportsWhetherAlreadyDeferring() {
        let graph = Graph()
        let outer = graph.beginDeferringSubgraphInvalidation()
        let inner = graph.beginDeferringSubgraphInvalidation()
        #expect(outer == false)
        #expect(inner == true)
        graph.endDeferringSubgraphInvalidation(wasDeferring: inner)
        graph.endDeferringSubgraphInvalidation(wasDeferring: outer)
    }

    @Test func invalidationIsNotValidAtOnceEvenWhileDeferring() {
        let graph = Graph()
        let subgraph = graph.makeSubgraph()
        let outer = graph.beginDeferringSubgraphInvalidation()
        subgraph.invalidate()
        #expect(subgraph.isValid == false)
        graph.endDeferringSubgraphInvalidation(wasDeferring: outer)
        #expect(subgraph.isValid == false)
    }
}
