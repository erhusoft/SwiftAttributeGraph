import Testing
@testable import SwiftAttributeGraph

/// `Graph.onUpdate(_:)` (Swift interface, over the default context's update callback). Measured with `graph-on-update` and
/// `graph-on-update-needs` on macOS 15.8: in a single context neither a dirtying write nor `setNeedsUpdate()` runs it. Its
/// multi-context behaviour is the one `shared-context-update-callback` measures.
@Suite struct GraphOnUpdateTests {
    @Test func aSingleContextDoesNotRunItForWritesOrNeedsUpdate() {
        let graph = Graph()
        var notices = 0
        graph.onUpdate { notices += 1 }
        let source = graph.makeInput(1)
        let rule = graph.makeRule { graph.value(of: source) + 1 }
        _ = graph.value(of: rule)
        graph.setValue(2, for: source)
        _ = graph.value(of: rule)
        graph.setNeedsUpdate()
        #expect(notices == 0)
    }
}
