import Testing
@testable import SwiftAttributeGraph

/// A subgraph handle whose release invalidates the subgraph, as Apple's `AGSubgraphRef` does when its last reference
/// goes away (oracle scenario `subgraph-remove-child-parent-death`: the observer runs on the parent's death).
@Suite struct SubgraphLeaseTests {
    private final class Counter { var runs = 0 }

    @Test func droppingTheLastLeaseInvalidatesItsSubgraphAndNotifiesObservers() {
        let graph = Graph()
        let counter = Counter()
        var lease: SubgraphLease? = SubgraphLease(graph: graph)
        let subgraph = lease!.subgraph
        _ = graph.observe(subgraph) { counter.runs += 1 }
        #expect(subgraph.isValid)

        lease = nil

        #expect(counter.runs == 1)
        #expect(!subgraph.isValid)
    }

    @Test func aSubgraphStaysValidWhileALeaseIsAlive() {
        let graph = Graph()
        let lease = SubgraphLease(graph: graph)
        let copy = lease
        #expect(lease.subgraph.isValid)
        _ = copy
    }
}
