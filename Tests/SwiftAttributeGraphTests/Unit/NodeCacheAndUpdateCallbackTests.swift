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
}
