import Testing
@testable import SwiftAttributeGraph

@Suite("NodeCacheAndUpdateCallbackTests")
struct NodeCacheAndUpdateCallbackTests {
    @Test func nodeCacheHitsAndReusesSameAttribute() {
        let graph = Graph()
        let source = graph.makeInput(10)
        var creations = 0

        let a1: Attribute<Int> = graph.readCachedAttribute(key: "k") {
            creations += 1
            return graph.makeRule { source.value + 1 }
        }
        let a2: Attribute<Int> = graph.readCachedAttribute(key: "k") {
            creations += 1
            return graph.makeRule { source.value + 1 }
        }

        #expect(creations == 1)
        #expect(a1.id == a2.id)
        #expect(graph.value(of: a1) == 11)
    }

    @Test func readCachedAttributeUsesEvaluatingNodesOwnerNotCurrentSubgraph() {
        let graph = Graph()
        let ownerSG = graph.makeSubgraph()
        let otherSG = graph.makeSubgraph()
        var cachedID: AttributeID?

        let reader = graph.withCurrent(ownerSG) {
            graph.makeRule {
                graph.withCurrent(otherSG) {
                    let cached: Attribute<Int> = graph.readCachedAttribute(key: "owned") {
                        graph.makeInput(77)
                    }
                    cachedID = cached.id
                    return cached.value
                }
            }
        }

        #expect(graph.value(of: reader) == 77)
        #expect(graph.table.owner(at: cachedID!.index) == ownerSG.id.index)
    }

    @Test func parkedCachedNodeIsCollectedAfterMaxAgeUnlessReactivated() {
        let graph = Graph()
        let sg = graph.makeSubgraph()
        let cached: Attribute<Int> = graph.readCachedAttribute(key: "park", owner: sg) {
            graph.makeInput(5)
        }
        #expect(graph.table.isLive(cached.id))

        // First collect ages from 1 -> 2, hitting maxAge = 3 keeps it alive if maxAge is 3.
        graph.collectCachedNodes(maxAge: 3)
        #expect(graph.table.isLive(cached.id))

        // Reactivating resets age to 0, then parks again at 1 (outside update).
        _ = graph.readCachedAttribute(key: "park", owner: sg) { graph.makeInput(999) }
        graph.collectCachedNodes(maxAge: 3)
        #expect(graph.table.isLive(cached.id))

        // Aging past maxAge = 2 collects and frees the node.
        graph.collectCachedNodes(maxAge: 2)
        #expect(!graph.table.isLive(cached.id))
    }

    @Test func invalidatingOwnerSubgraphClearsNodeCache() {
        let graph = Graph()
        let sg = graph.makeSubgraph()
        let cached: Attribute<Int> = graph.readCachedAttribute(key: "die", owner: sg) {
            graph.makeInput(12)
        }
        #expect(graph.table.isLive(cached.id))
        graph.invalidate(sg)
        #expect(!graph.table.isLive(cached.id))
        #expect(graph.nodeCaches[sg.id.index] == nil)
    }

    @Test func updateCallbackFiresOnDirtyTransitionAndRespectsBatching() {
        let graph = Graph()
        let source = graph.makeInput(1)
        let rule = graph.makeRule { source.value * 2 }
        #expect(graph.value(of: rule) == 2)

        var callbackCount = 0
        graph.setUpdateCallback { callbackCount += 1 }

        // Equal write does not dirty -> no callback.
        graph.setValue(1, for: source)
        #expect(callbackCount == 0)

        // Dirtying write outside batch -> fires once.
        graph.setValue(2, for: source)
        #expect(callbackCount == 1)
        #expect(graph.value(of: rule) == 4)

        // Multiple writes inside batch -> deferred and coalesced to one callback.
        graph.withBatch {
            graph.setValue(3, for: source)
            graph.setValue(4, for: source)
            #expect(callbackCount == 1)
        }
        #expect(callbackCount == 2)
        #expect(graph.value(of: rule) == 8)
    }

    @Test func removingLastConsumerParksCachedNodeAndCollectingDisconnectsInputs() {
        let graph = Graph()
        let sg = graph.makeSubgraph()
        let flag = graph.makeInput(true)
        let source = graph.makeInput(10)
        var creations = 0
        var cachedID: AttributeID?

        let consumer = graph.withCurrent(sg) {
            graph.makeRule {
                if flag.value {
                    let cached: Attribute<Int> = graph.readCachedAttribute(key: "dep") {
                        creations += 1
                        return graph.makeRule { source.value + 5 }
                    }
                    cachedID = cached.id
                    return cached.value
                }
                return 0
            }
        }

        #expect(graph.value(of: consumer) == 15)
        #expect(creations == 1)
        #expect(graph.table.outputs[Int(source.id.index)].contains(cachedID!.index))

        // Stop reading `cached`: pruneEdges removes consumer from cached.outputs -> cached is parked.
        graph.setValue(false, for: flag)
        #expect(graph.value(of: consumer) == 0)
        #expect(graph.nodeCaches[sg.id.index]?.entries.values.first?.age == 1)

        // Reading again before expiration reuses the same cached node.
        graph.setValue(true, for: flag)
        #expect(graph.value(of: consumer) == 15)
        #expect(creations == 1)

        // Park again and collect past maxAge: cached is freed and disconnected from `source.outputs`.
        graph.setValue(false, for: flag)
        #expect(graph.value(of: consumer) == 0)
        graph.collectCachedNodes(maxAge: 2)
        #expect(!graph.table.isLive(cachedID!))
        #expect(!graph.table.outputs[Int(source.id.index)].contains(cachedID!.index))

        // Reading again after expiration creates a fresh cached node.
        graph.setValue(true, for: flag)
        #expect(graph.value(of: consumer) == 15)
        #expect(creations == 2)
    }

    @Test func updateCallbackIsDrainedBeforeReadAndHandlesReentrantWriteSafely() {
        let graph = Graph()
        let source = graph.makeInput(1)
        let rule = graph.makeRule { source.value * 10 }
        #expect(graph.value(of: rule) == 10)

        var calls = 0
        graph.setUpdateCallback {
            calls += 1
            if calls == 1 {
                // Re-entrant read + write inside callback: must not infinite-loop, and leaves pending work for next drain.
                _ = graph.value(of: rule)
                graph.setValue(3, for: source)
            }
        }

        graph.withBatch {
            graph.setValue(2, for: source)
            #expect(calls == 0)
        }
        // Same-pass draining: call 1 dirtied `rule` again, so call 2 drains in the same pass.
        #expect(calls == 2)
        #expect(graph.value(of: rule) == 30)
    }

    @Test func twoGraphContextsReceiveOnlyTheirOwnCallbacksAndCoalesce() {
        let graph = Graph()
        let ctx1 = graph.makeContext()
        let ctx2 = graph.makeContext()
        var count1 = 0
        var count2 = 0
        ctx1.setUpdateCallback { count1 += 1 }
        ctx2.setUpdateCallback { count2 += 1 }

        graph.withBatch {
            ctx1.setNeedsUpdate()
            ctx1.setNeedsUpdate()
            ctx1.setNeedsUpdate()
            #expect(count1 == 0)
            #expect(count2 == 0)
        }
        #expect(count1 == 1)
        #expect(count2 == 0)

        ctx2.setNeedsUpdate()
        #expect(count1 == 1)
        #expect(count2 == 1)
    }

    @Test func contextCallbackRequestingAnotherUpdateDrainsInSamePassAndUpdatesSource() {
        let graph = Graph()
        let source = graph.makeInput(1)
        let rule = graph.makeRule { source.value * 5 }
        #expect(graph.value(of: rule) == 5)

        let ctx = graph.makeContext()
        var runs = 0
        ctx.setUpdateCallback {
            runs += 1
            if runs == 1 {
                graph.setValue(4, for: source)
                ctx.setNeedsUpdate()
            }
        }

        ctx.setNeedsUpdate()
        #expect(runs == 2)
        #expect(graph.value(of: rule) == 20)
    }
}
