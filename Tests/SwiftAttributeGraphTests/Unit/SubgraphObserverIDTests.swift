import Testing
@testable import SwiftAttributeGraph

/// `AGSubgraphAddObserver` / `AGSubgraphRemoveObserver` (`Subgraph.addObserver(_:)` and `removeObserver(_:)`). Measured with
/// the `subgraph-observers` oracle scenario on macOS 15.8: each live observer runs once when its subgraph is invalidated, a
/// removed observer never runs, and every observer gets its own ID.
@Suite struct SubgraphObserverIDTests {
    @Test func eachLiveObserverRunsOnceAndIDsAreDistinct() {
        let graph = Graph()
        let subgraph = graph.makeSubgraph()
        var a = 0
        var b = 0
        let id1 = subgraph.addObserver { a += 1 }
        let id2 = subgraph.addObserver { b += 1 }
        #expect(id1 != id2)
        subgraph.invalidate()
        #expect(a == 1)
        #expect(b == 1)
    }

    @Test func aRemovedObserverNeverRuns() {
        let graph = Graph()
        let subgraph = graph.makeSubgraph()
        var removed = 0
        let id = subgraph.addObserver { removed += 1 }
        subgraph.removeObserver(id)
        subgraph.invalidate()
        #expect(removed == 0)
    }
}
