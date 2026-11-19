import Testing
@testable import SwiftAttributeGraph

/// The minimal model of shared contexts (`AGGraphCreateShared`): a second context over the same graph with its own
/// identifier, update callback, `needsUpdate` flag and `contextThreadUpdating`, and its own subgraphs. Expected values
/// were measured on macOS 15.8.3 with `native-scratch/nc6b.swift` [O].
@Suite struct SharedGraphContextTests {
    @Test func sharedContextKeepsTheGraphIDAndTakesTheNextCounterNumber() {
        let graph = Graph()
        let other = Graph()
        let shared = graph.makeSharedContext()
        let after = Graph()
        #expect(graph.defaultContext.contextID == graph.counter(for: .graphID) + 1)
        #expect(shared.graphID == graph.counter(for: .graphID), "native: same graphID as the original [O]")
        #expect(shared.contextID > other.counter(for: .contextID), "native: advances the process counter [O]")
        #expect(after.counter(for: .graphID) > shared.contextID)
        #expect(shared.counter(for: .contextID) == shared.contextID)
        #expect(shared.counter(for: .graphID) == graph.counter(for: .graphID))
        #expect(shared !== graph.defaultContext, "native: the object returned is not the original [O]")
    }

    @Test func subgraphsBelongToTheContextTheyWereCreatedWith() {
        let graph = Graph()
        let shared = graph.makeSharedContext()
        let sg1 = graph.defaultContext.makeSubgraph()
        let sg2 = shared.makeSubgraph()
        let a1 = graph.withCurrent(sg1) { graph.makeInput(Int64(1)) }
        let a2 = graph.withCurrent(sg2) { graph.makeInput(Int64(2)) }
        #expect(graph.graphContext(of: sg1) === graph.defaultContext)
        #expect(graph.graphContext(of: sg2) === shared)
        #expect(graph.graphContext(of: a1) === graph.defaultContext)
        #expect(graph.graphContext(of: a2) === shared)
        #expect(graph.graphContext(of: graph.rootSubgraph) === graph.defaultContext)
    }

    @Test func needsUpdateIsPerContextAndAnyRuleReadClearsAllOfThem() {
        let graph = Graph()
        let shared = graph.makeSharedContext()
        let original = graph.defaultContext
        let sg1 = original.makeSubgraph()
        let sg2 = shared.makeSubgraph()
        let a = graph.withCurrent(sg1) { graph.makeInput(Int64(1)) }
        let r1 = graph.withCurrent(sg1) { graph.makeRule { graph.value(of: a) + 1 } }
        let r2 = graph.withCurrent(sg2) { graph.makeRule { graph.value(of: a) + 2 } }
        func flags() -> [UInt64] {
            [original.counter(for: .needsUpdate), original.counter(for: .contextNeedsUpdate),
             shared.counter(for: .needsUpdate), shared.counter(for: .contextNeedsUpdate)]
        }
        #expect(flags() == [0, 0, 0, 0])
        graph.setNeedsUpdate()
        #expect(flags() == [1, 1, 1, 0], "native: nu is graph-wide, cnu only of the original [O]")
        _ = graph.value(of: r2)
        #expect(flags() == [0, 0, 0, 0], "native: a rule read in the other context clears both [O]")
        shared.setNeedsUpdate()
        #expect(flags() == [1, 0, 1, 1])
        _ = graph.value(of: r1)
        #expect(flags() == [0, 0, 0, 0])
        graph.setNeedsUpdate(); shared.setNeedsUpdate()
        #expect(flags() == [1, 1, 1, 1])
        _ = graph.value(of: a)
        #expect(flags() == [1, 1, 1, 1], "native: reading an input clears nothing [O]")
        _ = graph.value(of: r2)
        #expect(flags() == [0, 0, 0, 0])
    }

    @Test func updateCallbacksFireForTheContextThatRaisedTheFlag() {
        let graph = Graph()
        let shared = graph.makeSharedContext()
        var calls1 = 0, calls2 = 0
        graph.setUpdateCallback { calls1 += 1 }
        shared.setUpdateCallback { calls2 += 1 }
        let sg1 = graph.defaultContext.makeSubgraph()
        let sg2 = shared.makeSubgraph()
        let a = graph.withCurrent(sg1) { graph.makeInput(Int64(1)) }
        let r1 = graph.withCurrent(sg1) { graph.makeRule { graph.value(of: a) + 1 } }
        let r2 = graph.withCurrent(sg2) { graph.makeRule { graph.value(of: a) + 2 } }
        _ = graph.value(of: r1); _ = graph.value(of: r2)
        #expect([calls1, calls2] == [0, 0], "native: nothing fires without setNeedsUpdate [O]")
        graph.setNeedsUpdate()
        _ = graph.value(of: r2)
        #expect([calls1, calls2] == [1, 0], "native: the callback of the context that raised it, read in the other one [O]")
        shared.setNeedsUpdate()
        _ = graph.value(of: r1)
        #expect([calls1, calls2] == [1, 1])
        graph.setNeedsUpdate(); shared.setNeedsUpdate()
        _ = graph.value(of: r1)
        #expect([calls1, calls2] == [2, 2])
    }

    @Test func readingAnInputDrainsNoCallbackButReadingATopLevelRuleDrainsAllContexts() {
        let graph = Graph()
        let shared = graph.makeSharedContext()
        var calls1 = 0, calls2 = 0
        graph.setUpdateCallback { calls1 += 1 }
        shared.setUpdateCallback { calls2 += 1 }
        let sg1 = graph.defaultContext.makeSubgraph()
        let a = graph.withCurrent(sg1) { graph.makeInput(Int64(1)) }
        let r1 = graph.withCurrent(sg1) { graph.makeRule { graph.value(of: a) + 1 } }
        graph.setNeedsUpdate(); shared.setNeedsUpdate()
        _ = graph.value(of: a)
        #expect([calls1, calls2] == [0, 0], "native: an input read drains nothing, afterInput=0,0 [O]")
        _ = graph.value(of: r1)
        #expect([calls1, calls2] == [1, 1], "native: a top-level rule read drains every context, afterRule=1,1 [O]")
    }

    @Test func contextThreadUpdatingIsOnlyOneForTheContextOfTheRunningRule() {
        let graph = Graph()
        let shared = graph.makeSharedContext()
        let original = graph.defaultContext
        let sg1 = original.makeSubgraph()
        let sg2 = shared.makeSubgraph()
        var seen: [String] = []
        func probe(_ label: String) {
            seen.append("\(label): g1[\(original.counter(for: .threadUpdating)),\(original.counter(for: .contextThreadUpdating))] "
                        + "g2[\(shared.counter(for: .threadUpdating)),\(shared.counter(for: .contextThreadUpdating))]")
        }
        let t1 = graph.withCurrent(sg1) { graph.makeRule { probe("r1"); return Int64(1) } }
        let t2 = graph.withCurrent(sg2) { graph.makeRule { probe("r2"); return Int64(2) } }
        _ = graph.value(of: t1); _ = graph.value(of: t2)
        #expect(seen == ["r1: g1[1,1] g2[1,0]", "r2: g1[1,0] g2[1,1]"], "native [O]")
    }

    @Test func invalidatingTheSubgraphOfOneContextLeavesTheOtherAlive() {
        let graph = Graph()
        let shared = graph.makeSharedContext()
        let sg1 = graph.defaultContext.makeSubgraph()
        let sg2 = shared.makeSubgraph()
        let a1 = graph.withCurrent(sg1) { graph.makeInput(Int64(1)) }
        _ = graph.withCurrent(sg2) { graph.makeInput(Int64(2)) }
        #expect(graph.counter(for: .nodes) == 2)
        graph.invalidate(sg2)
        #expect(graph.isValid(sg1) && !graph.isValid(sg2))
        #expect(graph.value(of: a1) == 1)
        #expect(shared.counter(for: .nodes) == 1 && graph.counter(for: .nodes) == 1, "native: counters are graph-wide [O]")
        #expect(graph.counter(for: .subgraphs) == 1)
        graph.invalidate(sg1)
        #expect(graph.counter(for: .nodes) == 0 && graph.counter(for: .subgraphs) == 0)
    }

    @Test func aContextOfAGraphWithoutSharedContextsMatchesTheGraphCounters() {
        let graph = Graph()
        graph.setNeedsUpdate()
        #expect(graph.defaultContext.counter(for: .contextNeedsUpdate) == graph.counter(for: .contextNeedsUpdate))
        #expect(graph.defaultContext.counter(for: .needsUpdate) == 1)
    }
}
