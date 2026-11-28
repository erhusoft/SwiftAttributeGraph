import Testing
@testable import SwiftAttributeGraph

/// When the invalidations a rule asks for reach the observers and free the subgraphs. Native lines measured on macOS 15.8.3 (oracle scenarios
/// `invalidate-graph-list-order`, `invalidate-graph-list-live` and `invalidate-freeing-timing`): the subgraphs are marked invalid at once,
/// but nothing is delivered when the read that ran the rule ends; the delivery happens in the next explicit update or invalidation, most
/// recent request first.
@Suite struct DeferredInvalidationDeliveryTests {
    final class Events { var names: [String] = [] }

    /// Four subgraphs under `scope`, a rule that invalidates all of them when it runs, and its trigger.
    final class Fixture {
        let graph: Graph
        let scope: Subgraph
        let trigger: Attribute<Int>
        let rule: Attribute<Int>
        let events = Events()
        var tokens: [SubgraphObservationToken] = []

        init() {
            let graph = Graph()
            let scope = graph.makeSubgraph()
            var subs: [Subgraph] = []
            for _ in 0..<4 { subs.append(graph.makeSubgraph(parent: scope)) }
            let trigger = graph.withCurrent(scope) { graph.makeInput(0) }
            let invalidated = subs
            let rule = graph.withCurrent(scope) {
                graph.makeRule { () -> Int in
                    _ = trigger.value
                    for s in invalidated { graph.invalidate(s) }
                    return 1
                }
            }
            self.graph = graph
            self.scope = scope
            self.trigger = trigger
            self.rule = rule
            let events = self.events
            for (i, s) in subs.enumerated() {
                tokens.append(graph.observe(s) { events.names.append("S\(i + 1)") })
            }
        }

        func run() {
            graph.setValue(1, for: trigger)
            _ = graph.value(of: rule)
        }
    }

    @Test func nothingIsDeliveredWhenTheReadEndsAndTheCloseDeliversMostRecentFirst() { // invalidate-graph-list-order
        let f = Fixture()
        f.run()
        #expect(f.events.names.isEmpty)                                        // events=[]
        f.graph.invalidate(f.scope)                                            // d.close()
        #expect(f.events.names == ["S4", "S3", "S2", "S1"])                    // afterClose
    }

    @Test func anExplicitUpdateDelivers() { // invalidate-graph-list-live
        let f = Fixture()
        f.run()
        #expect(f.events.names.isEmpty)                                        // afterRead=[]
        f.graph.update(f.scope, flags: .all)
        #expect(f.events.names == ["S4", "S3", "S2", "S1"])                    // afterUpdate
        let other = f.graph.withCurrent(f.scope) { f.graph.makeInput(5) }
        let otherRule = f.graph.withCurrent(f.scope) { f.graph.makeRule { other.value + 1 } }
        #expect(f.graph.value(of: otherRule) == 6)
        #expect(f.events.names == ["S4", "S3", "S2", "S1"])                    // afterUnrelatedRead
        f.graph.invalidate(f.scope)
        #expect(f.events.names == ["S4", "S3", "S2", "S1"])                    // afterClose
    }

    final class Deinits { nonisolated(unsafe) static var count = 0 }
    final class Owned { deinit { Deinits.count += 1 } }

    @Test func theSubgraphIsInvalidAtOnceButFreedAndNotifiedLater() { // invalidate-freeing-timing
        Deinits.count = 0
        let graph = Graph()
        let scope = graph.makeSubgraph()
        let s1 = graph.makeSubgraph(parent: scope)
        var notices = 0
        let token = graph.observe(s1) { notices += 1 }
        let owned = graph.withCurrent(s1) { graph.makeInput(Owned()) }
        let trigger = graph.withCurrent(scope) { graph.makeInput(0) }
        let rule = graph.withCurrent(scope) { graph.makeRule { _ = trigger.value; graph.invalidate(s1); return 1 } }
        _ = owned
        graph.setValue(1, for: trigger)
        _ = graph.value(of: rule)
        #expect((Deinits.count, notices, graph.isValid(s1)) == (0, 0, false))  // afterRead=(0, 0, false)
        graph.update(scope, flags: .all)
        #expect((Deinits.count, notices, graph.isValid(s1)) == (1, 1, false))  // afterUpdate=(1, 1, false)
        graph.invalidate(scope)
        #expect((Deinits.count, notices) == (1, 1))                            // afterClose=(1, 1)
        withExtendedLifetime(token) {}
    }
}

extension Graph {
    /// "The next explicit update": what delivers the invalidations a rule asked for. Native delivers them there, not when the read that ran the
    /// rule ends (oracle scenarios `invalidate-graph-list-order`, `-live` and `invalidate-freeing-timing`).
    func deliverPendingInvalidations() {
        update(rootSubgraph, flags: .all)
    }
}
