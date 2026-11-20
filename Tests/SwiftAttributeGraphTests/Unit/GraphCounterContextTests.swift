import Testing
@testable import SwiftAttributeGraph

/// The context and state selectors of `AGGraphGetCounter`: `contextID`, `graphID`, `threadUpdating`,
/// `contextThreadUpdating`, `mainThreadUpdates`, `needsUpdate` and `contextNeedsUpdate`. Expected values were measured
/// on macOS 15.8.3 with the native `AGGraphGetCounter` in isolated probes [O].
///
/// Absolute identifiers (`2`/`1` for the first graph of the process) cannot be asserted here because the test process
/// creates graphs in parallel; the `get-counter-context` probe scenario compares them against native.
@Suite struct GraphCounterContextTests {
    @Test func everyGraphTakesTwoConsecutiveIdentifiersGraphFirstThenItsContext() {
        var ids: [(graph: UInt64, context: UInt64)] = []
        var graphs: [Graph] = []
        for _ in 0..<4 {
            let graph = Graph()
            graphs.append(graph)
            ids.append((graph.counter(for: .graphID), graph.counter(for: .contextID)))
        }
        for id in ids { #expect(id.context == id.graph + 1, "native: gid=2k-1, ctx=2k [O]") }
        for index in 1..<ids.count { #expect(ids[index].graph > ids[index - 1].graph) }
        #expect(graphs[0].counter(for: .graphID) == ids[0].graph, "the identifier does not change")
    }

    @Test func identifiersAreNotReusedWhenAGraphIsReleased() {
        var released: UInt64 = 0
        do { let temporary = Graph(); released = temporary.counter(for: .graphID) }
        let next = Graph()
        #expect(next.counter(for: .graphID) > released, "native: 9 and 11 after releasing graphs 1..7 [O]")
    }

    @Test func creatingSubgraphsAndAttributesDoesNotConsumeIdentifiers() {
        let first = Graph()
        let sg = first.makeSubgraph()
        _ = first.withCurrent(sg) { first.makeInput(Int64(1)) }
        let second = Graph()
        #expect(second.counter(for: .graphID) > first.counter(for: .graphID))
        #expect(second.counter(for: .contextID) == second.counter(for: .graphID) + 1)
    }

    @Test func threadUpdatingIsOneInsideARuleAndNestedRulesAndZeroOutside() {
        let graph = Graph()
        let sg = graph.makeSubgraph()
        let a = graph.withCurrent(sg) { graph.makeInput(Int64(1)) }
        var seen: [String] = []
        func probe(_ label: String) {
            seen.append("\(label)=\(graph.counter(for: .threadUpdating)),\(graph.counter(for: .contextThreadUpdating))")
        }
        let mid = graph.withCurrent(sg) { graph.makeRule { probe("mid"); return graph.value(of: a) } }
        let tail = graph.withCurrent(sg) {
            graph.makeRule { probe("tailPre"); let v = graph.value(of: mid); probe("tailPost"); return v }
        }
        probe("outside")
        _ = graph.value(of: tail)
        probe("after")
        graph.withoutUpdate { probe("withoutUpdate") }
        #expect(seen == ["outside=0,0", "tailPre=1,1", "mid=1,1", "tailPost=1,1", "after=0,0", "withoutUpdate=0,0"])
    }

    @Test func threadUpdatingIsPerGraph() {
        let graph = Graph(), other = Graph()
        let sg = graph.makeSubgraph()
        var inside: UInt64 = 9
        let rule = graph.withCurrent(sg) { graph.makeRule { inside = other.counter(for: .threadUpdating); return Int64(1) } }
        _ = graph.value(of: rule)
        #expect(inside == 0, "native: a rule of g does not make g2 updating [O]")
    }

    @Test func mainThreadUpdatesEqualsUpdates() {
        let graph = Graph()
        let sg = graph.makeSubgraph()
        let a = graph.withCurrent(sg) { graph.makeInput(Int64(1)) }
        let b = graph.withCurrent(sg) { graph.makeRule { graph.value(of: a) } }
        let c = graph.withCurrent(sg) { graph.makeRule { graph.value(of: b) } }
        #expect(graph.counter(for: .mainThreadUpdates) == 0)
        _ = graph.value(of: c)
        #expect(graph.counter(for: .mainThreadUpdates) == 2)
        graph.setValue(2, for: a)
        _ = graph.value(of: c)
        #expect(graph.counter(for: .mainThreadUpdates) == graph.counter(for: .updates))
        #expect(graph.counter(for: .updates) == 3, "re-evaluating the dirty chain is one update")
    }

    @Test func setNeedsUpdateRaisesBothFlagsAndTheNextRuleReadClearsThem() {
        let graph = Graph()
        let sg = graph.makeSubgraph()
        let a = graph.withCurrent(sg) { graph.makeInput(Int64(1)) }
        let rule = graph.withCurrent(sg) { graph.makeRule { graph.value(of: a) } }
        func flags() -> [UInt64] { [graph.counter(for: .needsUpdate), graph.counter(for: .contextNeedsUpdate)] }
        #expect(flags() == [0, 0])
        _ = graph.value(of: rule)
        graph.setNeedsUpdate()
        #expect(flags() == [1, 1], "d1")
        graph.setNeedsUpdate()
        #expect(flags() == [1, 1], "d2: a second call does not add up")
        _ = graph.value(of: a)
        #expect(flags() == [1, 1], "d3: reading an input does not clear")
        graph.setValue(5, for: a)
        #expect(flags() == [1, 1], "writing does not clear")
        _ = graph.value(of: rule)
        #expect(flags() == [0, 0], "d4: the next top-level read of a rule clears")
        graph.setNeedsUpdate()
        _ = graph.value(of: rule)
        #expect(flags() == [0, 0], "d6: even a clean rule")
    }

    @Test func writingAloneDoesNotRaiseNeedsUpdate() {
        let graph = Graph()
        let sg = graph.makeSubgraph()
        let a = graph.withCurrent(sg) { graph.makeInput(Int64(1)) }
        graph.setValue(2, for: a)
        #expect(graph.counter(for: .needsUpdate) == 0)
    }

    @Test func aReadThroughAnIndirectOfARuleClearsNeedsUpdate() {
        let graph = Graph()
        let sg = graph.makeSubgraph()
        let rule = graph.withCurrent(sg) { graph.makeRule { Int64(3) } }
        let indirect = graph.withCurrent(sg) { graph.makeIndirect(rule) }
        graph.setNeedsUpdate()
        _ = graph.value(of: indirect)
        #expect(graph.counter(for: .needsUpdate) == 0)
    }

    @Test func setNeedsUpdateInsideARuleSurvivesTheEndOfThatUpdate() {
        let graph = Graph()
        let sg = graph.makeSubgraph()
        let inner = graph.withCurrent(sg) { graph.makeRule { Int64(7) } }
        var inside: UInt64 = 9
        let outer = graph.withCurrent(sg) {
            graph.makeRule {
                graph.setNeedsUpdate()
                inside = graph.counter(for: .needsUpdate)
                return graph.value(of: inner)
            }
        }
        _ = graph.value(of: outer)
        #expect(inside == 1)
        #expect(graph.counter(for: .needsUpdate) == 1, "native: the flag raised in the rule stays up [O]")
        _ = graph.value(of: outer)
        #expect(graph.counter(for: .needsUpdate) == 0)
    }

    // MARK: Indirect attributes

    @Test func indirectAttributesAreNotCountedInNodesOrCreatedNodesButAreInNodeCount() {
        let graph = Graph()
        let sg = graph.makeSubgraph()
        let rule = graph.withCurrent(sg) { graph.makeRule { Int64(3) } }
        func counts() -> [UInt64] { [graph.counter(for: .nodes), graph.counter(for: .createdNodes)] }
        #expect(counts() == [1, 1])
        let indirect = graph.withCurrent(sg) { graph.makeIndirect(rule) }
        #expect(counts() == [1, 1], "a rule plus an indirect attribute over it is 1, native [O]")
        #expect(graph.nodeCount == 2, "nodeCount keeps counting every slot")
        let input = graph.withCurrent(sg) { graph.makeInput(Int64(1)) }
        _ = graph.withCurrent(sg) { graph.makeIndirect(input) }
        _ = graph.withCurrent(sg) { graph.makeIndirect(indirect) }
        #expect(counts() == [2, 2], "an input is counted, indirect attributes over an input or an indirect are not [O]")
        #expect(graph.nodeCount == 5)
    }

    @Test func indirectAttributesLeaveNodesAtZeroWhenTheirSubgraphIsInvalidated() {
        let graph = Graph()
        let parent = graph.makeSubgraph()
        let child = graph.makeSubgraph(parent: parent)
        let rule = graph.withCurrent(parent) { graph.makeRule { Int64(3) } }
        _ = graph.withCurrent(child) { graph.makeIndirect(rule) }
        child.invalidate()
        #expect(graph.counter(for: .nodes) == 1)
        #expect(graph.nodeCount == 1)
        parent.invalidate()
        #expect(graph.counter(for: .nodes) == 0, "native: 0 after the parent is invalidated [O]")
        #expect(graph.counter(for: .createdNodes) == 1, "freed nodes stay in createdNodes, indirect ones never enter")
        #expect(graph.nodeCount == 0)
    }

    @Test func offsetFieldAttributesAreNotCountedEither() {
        struct Pair { var x: Int64; var y: Int64 }
        let graph = Graph()
        let sg = graph.makeSubgraph()
        let pair = graph.withCurrent(sg) { graph.makeInput(Pair(x: 1, y: 2)) }
        _ = graph.withCurrent(sg) { graph.makeOffsetFieldAttribute(of: pair, keyPath: \Pair.y) }
        #expect(graph.counter(for: .nodes) == 1, "native: attribute[keyPath:] adds no node [O]")
        #expect(graph.counter(for: .createdNodes) == 1)
    }
}
