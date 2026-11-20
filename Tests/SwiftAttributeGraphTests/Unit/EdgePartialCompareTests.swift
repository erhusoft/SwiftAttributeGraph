import Testing
@testable import SwiftAttributeGraph

@Suite("EdgePartialCompareTests")
struct EdgePartialCompareTests {
    struct Payload: Equatable {
        var x: Int
        var y: Int
    }

    struct NonEquatableSlice {
        var tag: Int
    }

    @Test func changeInsideProjectionReevaluatesAndOutsideCutsOff() {
        let graph = Graph()
        let source = graph.makeInput(Payload(x: 1, y: 10))
        var runs = 0
        let consumer = graph.makeRule {
            runs += 1
            return graph.read(source) { $0.x } * 2
        }

        #expect(graph.value(of: consumer) == 2)
        #expect(runs == 1)

        // Change outside projection (`y` only): consumer is not dirtied or re-evaluated.
        graph.setValue(Payload(x: 1, y: 99), for: source)
        #expect(graph.value(of: consumer) == 2)
        #expect(runs == 1)

        // Change inside projection (`x`): consumer re-evaluates.
        graph.setValue(Payload(x: 5, y: 99), for: source)
        #expect(graph.value(of: consumer) == 10)
        #expect(runs == 2)
    }

    @Test func aToBToABeforeConsumerEvaluationKeepsEdgeStickyChanged() {
        let graph = Graph()
        let source = graph.makeInput(Payload(x: 1, y: 0))
        var runs = 0
        let consumer = graph.makeRule {
            runs += 1
            return graph.read(source) { $0.x }
        }

        #expect(graph.value(of: consumer) == 1)
        #expect(runs == 1)

        // A -> B marks sticky changed; B -> A does not clear it.
        graph.setValue(Payload(x: 2, y: 0), for: source)
        graph.setValue(Payload(x: 1, y: 0), for: source)

        #expect(graph.value(of: consumer) == 1)
        #expect(runs == 2)
    }

    @Test func aToBEvaluateThenBToAReevaluatesTwice() {
        let graph = Graph()
        let source = graph.makeInput(Payload(x: 1, y: 0))
        var runs = 0
        let consumer = graph.makeRule {
            runs += 1
            return graph.read(source) { $0.x }
        }

        #expect(graph.value(of: consumer) == 1)
        #expect(runs == 1)

        graph.setValue(Payload(x: 2, y: 0), for: source)
        #expect(graph.value(of: consumer) == 2)
        #expect(runs == 2)

        graph.setValue(Payload(x: 1, y: 0), for: source)
        #expect(graph.value(of: consumer) == 1)
        #expect(runs == 3)
    }

    @Test func customComparatorWithNonEquatableProjectedType() {
        let graph = Graph()
        let source = graph.makeInput(Payload(x: 10, y: 0))
        var runs = 0
        let consumer = graph.makeRule {
            runs += 1
            return graph.read(source, project: { NonEquatableSlice(tag: $0.x) }, isEqual: { $0.tag / 10 == $1.tag / 10 }).tag
        }

        #expect(graph.value(of: consumer) == 10)
        #expect(runs == 1)

        // 10 -> 15: same decade (1 == 1) -> cuts off.
        graph.setValue(Payload(x: 15, y: 0), for: source)
        #expect(graph.value(of: consumer) == 10)
        #expect(runs == 1)

        // 15 -> 20: different decade (1 != 2) -> re-evaluates.
        graph.setValue(Payload(x: 20, y: 0), for: source)
        #expect(graph.value(of: consumer) == 20)
        #expect(runs == 2)
    }

    @Test func pruningAndOwnerInvalidationCleanUpEdgeComparators() {
        let graph = Graph()
        let sg = graph.makeSubgraph()
        let flag = graph.makeInput(true)
        let source = graph.makeInput(Payload(x: 1, y: 2))

        let consumer = graph.withCurrent(sg) {
            graph.makeRule {
                if flag.value {
                    return graph.read(source) { $0.x }
                }
                return 0
            }
        }

        #expect(graph.value(of: consumer) == 1)
        #expect(graph.edgeComparators[consumer.id.index]?[source.id.index] != nil)

        // Prune edge to `source`.
        graph.setValue(false, for: flag)
        #expect(graph.value(of: consumer) == 0)
        #expect(graph.edgeComparators[consumer.id.index]?[source.id.index] == nil)

        // Re-add and invalidate owner subgraph.
        graph.setValue(true, for: flag)
        #expect(graph.value(of: consumer) == 1)
        sg.invalidate()
        #expect(graph.edgeComparators[consumer.id.index] == nil)
    }

    @Test func indirectRedirectResetAndAToBToAWithEdgePartialCompare() {
        let graph = Graph()
        let sg1 = graph.makeSubgraph()
        let sg2 = graph.makeSubgraph()
        let a = graph.withCurrent(sg1) { graph.makeInput(Payload(x: 1, y: 10)) }
        let bSameProj = graph.withCurrent(sg2) { graph.makeInput(Payload(x: 1, y: 99)) }
        let cDiffProj = graph.withCurrent(sg2) { graph.makeInput(Payload(x: 7, y: 99)) }

        let indirect = graph.makeIndirect(a)
        var runs = 0
        let consumer = graph.makeRule {
            runs += 1
            return graph.read(indirect) { $0.x } * 10
        }

        #expect(graph.value(of: consumer) == 10)
        #expect(runs == 1)

        // Redirect across subgraphs to `bSameProj` (`x == 1`, `y` changed) -> cuts off.
        graph.setSource(bSameProj, for: indirect)
        #expect(graph.value(of: consumer) == 10)
        #expect(runs == 1)

        // Redirect to `cDiffProj` (`x == 7`) -> re-evaluates.
        graph.setSource(cDiffProj, for: indirect)
        #expect(graph.value(of: consumer) == 70)
        #expect(runs == 2)

        // Reset back to `a` (`x == 1`) -> re-evaluates.
        graph.resetSource(for: indirect)
        #expect(graph.value(of: consumer) == 10)
        #expect(runs == 3)

        // A -> B -> A via setSource/resetSource before consumer evaluation -> sticky changed, re-evaluates.
        graph.setSource(cDiffProj, for: indirect)
        graph.resetSource(for: indirect)
        #expect(graph.value(of: consumer) == 10)
        #expect(runs == 4)
    }

    @Test func intermediateIndirectChainPropagatesPartialCompareAndStickyBit() {
        let graph = Graph()
        let sg = graph.makeSubgraph()
        let flag = graph.makeInput(true)
        let s1 = graph.makeInput(Payload(x: 1, y: 10))
        let s2SameProj = graph.makeInput(Payload(x: 1, y: 99))
        let s3DiffProj = graph.makeInput(Payload(x: 8, y: 99))

        let indirectB = graph.withCurrent(sg) { graph.makeIndirect(s1) }
        let indirectA = graph.withCurrent(sg) { graph.makeIndirect(indirectB) }

        var runs = 0
        let consumer = graph.makeRule {
            runs += 1
            if flag.value {
                return graph.read(indirectA) { $0.x } * 10
            }
            return 0
        }

        #expect(graph.value(of: consumer) == 10)
        #expect(runs == 1)

        // Redirect intermediate `indirectB` to `s2SameProj` (same `x = 1`, different `y`) -> cuts off.
        graph.setSource(s2SameProj, for: indirectB)
        #expect(graph.value(of: consumer) == 10)
        #expect(runs == 1)

        // Redirect intermediate `indirectB` to `s3DiffProj` (`x = 8`) -> re-evaluates.
        graph.setSource(s3DiffProj, for: indirectB)
        #expect(graph.value(of: consumer) == 80)
        #expect(runs == 2)

        // Reset intermediate `indirectB` back to `s1` (`x = 1`) -> re-evaluates.
        graph.resetSource(for: indirectB)
        #expect(graph.value(of: consumer) == 10)
        #expect(runs == 3)

        // A -> B -> A on intermediate `indirectB` before consumer evaluation -> sticky changed, re-evaluates.
        graph.setSource(s3DiffProj, for: indirectB)
        graph.resetSource(for: indirectB)
        #expect(graph.value(of: consumer) == 10)
        #expect(runs == 4)

        // Prune edge to `indirectA` -> cleans up comparator.
        graph.setValue(false, for: flag)
        #expect(graph.value(of: consumer) == 0)
        #expect(graph.edgeComparators[consumer.id.index]?[indirectA.id.index] == nil)

        // Invalidate `sg` owning the indirects -> no dangling references.
        sg.invalidate()
        #expect(!graph.table.isLive(indirectA.id))
        #expect(!graph.table.isLive(indirectB.id))
    }

    @Test func observedConsumerBehindIndirectsIsNotDirtiedOrNotifiedWhenProjectionUnchanged() {
        let graph = Graph()
        let source = graph.makeInput(Payload(x: 1, y: 10))
        let ind1 = graph.makeIndirect(source)
        let ind2 = graph.makeIndirect(ind1)

        let consumer = graph.makeRule {
            graph.read(ind2) { $0.x } * 2
        }
        var notifications = 0
        let token = graph.observe(consumer.erased) { notifications += 1 }
        defer { token.cancel() }

        #expect(graph.value(of: consumer) == 2)
        #expect(notifications == 0)

        // Write outside projection: consumer must stay clean and not notify.
        graph.setValue(Payload(x: 1, y: 99), for: source)
        #expect(graph.table.state[Int(consumer.id.index)] & NodeState.dirty == 0)
        #expect(notifications == 0)
        #expect(graph.value(of: consumer) == 2)
    }

    @Test func redirectingIntermediateIndirectToUnevaluatedSourceMarksStickyEdge() {
        let graph = Graph()
        let s1 = graph.makeInput(Payload(x: 1, y: 10))
        let unevaluated = graph.makeRule { Payload(x: 5, y: 20) }
        let indB = graph.makeIndirect(s1)
        let indA = graph.makeIndirect(indB)

        var runs = 0
        let consumer = graph.makeRule {
            runs += 1
            return graph.read(indA) { $0.x }
        }
        #expect(graph.value(of: consumer) == 1)
        #expect(runs == 1)

        graph.setSource(unevaluated, for: indB)
        #expect(graph.stickyChangedEdges[consumer.id.index]?.contains(indA.id.index) == true)
        #expect(graph.value(of: consumer) == 5)
        #expect(runs == 2)
    }

    @Test func threeIndirectsChainAndTwoConsumersOneWithComparatorOneWithout() {
        let graph = Graph()
        let source = graph.makeInput(Payload(x: 3, y: 10))
        let i1 = graph.makeIndirect(source)
        let i2 = graph.makeIndirect(i1)
        let i3 = graph.makeIndirect(i2)

        var partialRuns = 0
        let partialConsumer = graph.makeRule {
            partialRuns += 1
            return graph.read(i3) { $0.x }
        }
        var fullRuns = 0
        let fullConsumer = graph.makeRule {
            fullRuns += 1
            return i3.value.y
        }

        #expect(graph.value(of: partialConsumer) == 3)
        #expect(graph.value(of: fullConsumer) == 10)
        #expect(partialRuns == 1 && fullRuns == 1)

        // Change `y` only: `fullConsumer` re-runs, `partialConsumer` cuts off.
        graph.setValue(Payload(x: 3, y: 42), for: source)
        #expect(graph.value(of: fullConsumer) == 42)
        #expect(graph.value(of: partialConsumer) == 3)
        #expect(fullRuns == 2 && partialRuns == 1)
    }

    @Test func deepIndirectChainTwentyThousandLevelsIsIterative() {
        let graph = Graph()
        let source = graph.makeInput(Payload(x: 1, y: 2))
        var tail = graph.makeIndirect(source)
        for _ in 1..<20_000 {
            tail = graph.makeIndirect(tail)
        }
        var runs = 0
        let consumer = graph.makeRule {
            runs += 1
            return graph.read(tail) { $0.x }
        }
        #expect(graph.value(of: consumer) == 1)
        #expect(runs == 1)

        graph.setValue(Payload(x: 1, y: 99), for: source)
        #expect(graph.value(of: consumer) == 1)
        #expect(runs == 1)

        graph.setValue(Payload(x: 7, y: 99), for: source)
        #expect(graph.value(of: consumer) == 7)
        #expect(runs == 2)
    }

    @Test func aToBToAOnIntermediateIndirectKeepsStickyBit() {
        let graph = Graph()
        let s1 = graph.makeInput(Payload(x: 1, y: 10))
        let s2 = graph.makeInput(Payload(x: 9, y: 10))
        let indB = graph.makeIndirect(s1)
        let indA = graph.makeIndirect(indB)

        var runs = 0
        let consumer = graph.makeRule {
            runs += 1
            return graph.read(indA) { $0.x }
        }
        #expect(graph.value(of: consumer) == 1)
        #expect(runs == 1)

        graph.setSource(s2, for: indB)
        graph.resetSource(for: indB)
        #expect(graph.value(of: consumer) == 1)
        #expect(runs == 2)
    }

    @Test func pruningAndOwnerInvalidationThroughIndirectsLeaveNoDanglingState() {
        let graph = Graph()
        let baseSubgraphs = graph.liveSubgraphCount
        let sg = graph.makeSubgraph()
        let flag = graph.makeInput(true)
        let source = graph.makeInput(Payload(x: 1, y: 2))
        let indB = graph.withCurrent(sg) { graph.makeIndirect(source) }
        let indA = graph.withCurrent(sg) { graph.makeIndirect(indB) }

        let consumer = graph.withCurrent(sg) {
            graph.makeRule {
                flag.value ? graph.read(indA) { $0.x } : 0
            }
        }
        #expect(graph.value(of: consumer) == 1)

        graph.setValue(false, for: flag)
        #expect(graph.value(of: consumer) == 0)
        #expect(graph.edgeComparators[consumer.id.index]?[indA.id.index] == nil)

        sg.invalidate()
        #expect(graph.liveSubgraphCount == baseSubgraphs)
        #expect(graph.edgeComparators[consumer.id.index] == nil)
    }

    @Test func writePerformanceOverLongIndirectChainWithPartialComparator() {
        let graph = Graph()
        let source = graph.makeInput(Payload(x: 1, y: 2))
        var tail = graph.makeIndirect(source)
        for _ in 1..<20_000 {
            tail = graph.makeIndirect(tail)
        }
        let consumer = graph.makeRule { graph.read(tail) { $0.x } }
        #expect(graph.value(of: consumer) == 1)

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for i in 0..<20 {
                graph.setValue(Payload(x: 1, y: i), for: source)
            }
        }
        print("PERF 20 writes over 20k indirect chain with partial comparator: \(elapsed)")
        #expect(graph.value(of: consumer) == 1)
    }
}
