import Testing
@testable import SwiftAttributeGraph

@Suite("OffsetAttributeTests")
struct OffsetAttributeTests {
    struct Pair: BitwiseCopyable, Equatable {
        var first: Int64
        var second: Int64
    }

    @Test func changeInsideProjectedRangePropagatesAndOutsideRangeCutsOff() {
        let graph = Graph()
        let source = graph.makeInput(Pair(first: 1, second: 2))
        let secondOffset = MemoryLayout<Pair>.offset(of: \Pair.second)!
        let projected: Attribute<Int64> = graph.makeOffsetAttribute(of: source, offset: secondOffset)

        var consumerRuns = 0
        let consumer = graph.makeRule {
            consumerRuns += 1
            return projected.value * 10
        }

        #expect(graph.value(of: consumer) == 20)
        #expect(consumerRuns == 1)

        // Change outside projected range (`first` only): `projected` cuts off, `consumer` does not re-run.
        graph.setValue(Pair(first: 99, second: 2), for: source)
        #expect(graph.value(of: consumer) == 20)
        #expect(consumerRuns == 1)

        // Change inside projected range (`second`): `consumer` re-runs with new value.
        graph.setValue(Pair(first: 99, second: 5), for: source)
        #expect(graph.value(of: consumer) == 50)
        #expect(consumerRuns == 2)
    }

    @Test func fullRangeReturnsSourceDirectlyWithoutExtraNode() {
        let graph = Graph()
        let source = graph.makeInput(Pair(first: 3, second: 4))
        let full: Attribute<Pair> = graph.makeOffsetAttribute(of: source, offset: 0, as: Pair.self)
        #expect(full.id == source.id)
        #expect(graph.value(of: full) == Pair(first: 3, second: 4))
    }

    @Test func zeroSizeRangeNeverPropagatesChanges() {
        let graph = Graph()
        let source = graph.makeInput(Pair(first: 1, second: 2))
        let zero = graph.makeZeroSizeOffsetAttribute(of: source, offset: 0)

        var runs = 0
        let consumer = graph.makeRule {
            runs += 1
            return zero.value + 1
        }

        #expect(graph.value(of: consumer) == 1)
        #expect(runs == 1)

        graph.setValue(Pair(first: 100, second: 200), for: source)
        #expect(graph.value(of: consumer) == 1)
        #expect(runs == 1)
    }

    @Test func outOfBoundsOrOverflowOffsetStopsTheProgram() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            let source = graph.makeInput(Pair(first: 1, second: 2))
            let _: Attribute<Int64> = graph.makeOffsetAttribute(of: source, offset: MemoryLayout<Pair>.size)
        }
    }

    @Test func focusHandlesNonTrivialTypesSafely() {
        struct NonTrivial: Equatable {
            var title: String
            var count: Int
        }
        let graph = Graph()
        let source = graph.makeInput(NonTrivial(title: "a", count: 1))
        let titleAttr = graph.makeFocus(source, keyPath: \.title)
        #expect(graph.value(of: titleAttr) == "a")
        graph.setValue(NonTrivial(title: "a", count: 2), for: source)
        #expect(graph.value(of: titleAttr) == "a")
    }
}
