import Testing
@testable import SwiftAttributeGraph

/// `Graph.onInvalidation(_:)` (Swift interface, over `AGGraphSetInvalidationCallback` of the default context). Measured
/// with `graph-on-invalidation` on macOS 15.8: writes and re-reads inside one context send no notice, and a subgraph
/// invalidation sends none either. The notice needs a cross-context edge (`shared-context-invalidation-callback`).
@Suite struct GraphOnInvalidationTests {
    @Test func sameContextWritesAndSubgraphInvalidationSendNoNotice() {
        let graph = Graph()
        var notices = 0
        graph.onInvalidation { _ in notices += 1 }
        let source = graph.makeInput(1)
        let rule = graph.makeRule { graph.value(of: source) + 1 }
        _ = graph.value(of: rule)
        graph.setValue(2, for: source)
        _ = graph.value(of: rule)
        graph.setValue(3, for: source)
        let subgraph = graph.makeSubgraph()
        _ = graph.withCurrent(subgraph) { graph.makeInput(4) }
        subgraph.invalidate()
        #expect(notices == 0)
    }
}
