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
        graph.invalidate(sg)
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
}
