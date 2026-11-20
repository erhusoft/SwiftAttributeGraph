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
        sg.invalidate()
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

        // Explicit setNeedsUpdate outside batch -> deferred until read, fires once.
        graph.setValue(2, for: source)
        graph.setNeedsUpdate()
        #expect(callbackCount == 0)
        #expect(graph.value(of: rule) == 4)
        #expect(callbackCount == 1)

        // Multiple setNeedsUpdate calls inside batch -> deferred and coalesced to one callback on batch exit.
        graph.withBatch {
            graph.setValue(3, for: source)
            graph.setNeedsUpdate()
            graph.setValue(4, for: source)
            graph.setNeedsUpdate()
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
                // Re-entrant read + write + setNeedsUpdate inside callback: must not infinite-loop, and drains in same pass.
                _ = graph.value(of: rule)
                graph.setValue(3, for: source)
                graph.setNeedsUpdate()
            }
        }

        graph.withBatch {
            graph.setValue(2, for: source)
            graph.setNeedsUpdate()
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

        let dummy = graph.makeRule { 0 }   // a rule: reading an input drains nothing (shared-context-input-read [O])
        ctx2.setNeedsUpdate()
        #expect(count2 == 0)
        _ = graph.value(of: dummy)
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
        #expect(runs == 0)
        #expect(graph.value(of: rule) == 20)
        #expect(runs == 2)
    }

    @Test func releasingGraphContextInvalidatesOnlyItsOwnSubgraphs() {
        let graph = Graph()
        var ctx1: GraphContext? = graph.makeContext()
        let ctx2 = graph.makeContext()

        let sg1 = ctx1!.makeSubgraph()
        let sg2 = ctx2.makeSubgraph()
        let a1 = graph.withCurrent(sg1) { graph.makeInput(11) }
        let a2 = graph.withCurrent(sg2) { graph.makeInput(22) }

        #expect(sg1.isValid)
        #expect(sg2.isValid)

        // Releasing ctx1 triggers deinit -> invalidates sg1 only; sg2 and a2 remain alive.
        ctx1 = nil
        #expect(!sg1.isValid)
        #expect(!graph.table.isLive(a1.id))
        #expect(sg2.isValid)
        #expect(graph.value(of: a2) == 22)
    }

    @Test func invalidatingGraphContextInsideRuleDefersFreeingUntilRuleExits() {
        let graph = Graph()
        let ctx = graph.makeContext()
        let sg = ctx.makeSubgraph()
        let attr = graph.withCurrent(sg) { graph.makeInput(7) }

        var notices = 0
        graph.observe(sg) { notices += 1 }

        let reader = graph.makeRule {
            ctx.invalidate()
            #expect(!sg.isValid)
            #expect(notices == 0)
            return attr.value * 3
        }

        #expect(graph.value(of: reader) == 21)
        #expect(notices == 1)
        #expect(!graph.table.isLive(attr.id))
    }

    @Test func invalidatedGraphContextDoesNotFirePendingCallback() {
        let graph = Graph()
        let ctx = graph.makeContext()
        var calls = 0
        ctx.setUpdateCallback { calls += 1 }

        graph.withBatch {
            ctx.setNeedsUpdate()
            ctx.invalidate()
        }
        #expect(calls == 0)

        ctx.setNeedsUpdate()
        #expect(calls == 0)
    }

    @Test func contextUpdateCallbackCoalescesBeforeReadAndDrainsReentrantly() {
        let graph = Graph()
        var calls = 0
        var drainExtra = false
        graph.setUpdateCallback {
            calls += 1
            if drainExtra {
                drainExtra = false
                graph.setNeedsUpdate()
            }
        }
        let a = graph.makeInput(Int64(1))
        let r = graph.makeRule { a.value + 1 }
        _ = graph.value(of: r)

        // Two setNeedsUpdate calls before any read: coalesced and deferred until read/update.
        graph.setNeedsUpdate()
        graph.setNeedsUpdate()
        #expect(calls == 0)
        _ = graph.value(of: r)
        #expect(calls == 1)

        // Requesting another update from inside the callback drains in the same pass.
        drainExtra = true
        graph.setNeedsUpdate()
        _ = graph.value(of: r)
        #expect(calls == 3)
    }

    @Test func setValueDoesNotTriggerUpdateCallback() {
        let graph = Graph()
        var calls = 0
        graph.setUpdateCallback { calls += 1 }
        let a = graph.makeInput(Int64(10))
        let r = graph.makeRule { a.value * 2 }
        _ = graph.value(of: r)
        #expect(calls == 0)

        graph.setValue(20, for: a)
        #expect(calls == 0)

        #expect(graph.value(of: r) == 40)
        #expect(calls == 0)
    }
}
