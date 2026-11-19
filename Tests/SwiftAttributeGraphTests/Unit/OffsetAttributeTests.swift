import Testing
@testable import SwiftAttributeGraph

@Suite("OffsetAttributeTests")
struct OffsetAttributeTests {
    struct Pair: BitwiseCopyable, Equatable {
        var first: Int64
        var second: Int64
    }

    struct Empty: BitwiseCopyable, Equatable {}

    @Test func changeInsideProjectedRangePropagatesAndOutsideRangeCutsOff() {
        let graph = Graph()
        let source = graph.makeInput(Pair(first: 1, second: 2))
        let secondOffset = MemoryLayout<Pair>.offset(of: \Pair.second)!
        let projected = graph.makeByteRangeAttribute(of: source, offset: secondOffset, size: MemoryLayout<Int64>.size)

        var consumerRuns = 0
        let consumer = graph.makeRule {
            consumerRuns += 1
            return projected.value.count
        }

        #expect(graph.value(of: consumer) == MemoryLayout<Int64>.size)
        #expect(consumerRuns == 1)

        // Change outside projected range (`first` only): `projected` cuts off, `consumer` does not re-run.
        graph.setValue(Pair(first: 99, second: 2), for: source)
        #expect(graph.value(of: consumer) == MemoryLayout<Int64>.size)
        #expect(consumerRuns == 1)

        // Change inside projected range (`second`): `consumer` re-runs.
        graph.setValue(Pair(first: 99, second: 5), for: source)
        #expect(graph.value(of: consumer) == MemoryLayout<Int64>.size)
        #expect(consumerRuns == 2)
    }

    @Test func zeroSizeRangeAndZeroSizeTypeDoNotCrashOrPropagate() {
        let graph = Graph()
        let pairSource = graph.makeInput(Pair(first: 1, second: 2))
        let zeroAtEnd = graph.makeByteRangeAttribute(of: pairSource, offset: MemoryLayout<Pair>.size, size: 0)

        var runs = 0
        let consumer = graph.makeRule {
            runs += 1
            return zeroAtEnd.value.count
        }
        #expect(graph.value(of: consumer) == 0)
        #expect(runs == 1)

        graph.setValue(Pair(first: 100, second: 200), for: pairSource)
        #expect(graph.value(of: consumer) == 0)
        #expect(runs == 1)

        let emptySource = graph.makeInput(Empty())
        let emptyRange = graph.makeByteRangeAttribute(of: emptySource, offset: 0, size: 0)
        #expect(graph.value(of: emptyRange).isEmpty)
    }

    @Test func outOfBoundsOrOverflowOffsetStopsTheProgram() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            let source = graph.makeInput(Pair(first: 1, second: 2))
            _ = graph.makeByteRangeAttribute(of: source, offset: MemoryLayout<Pair>.size, size: 1)
        }
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            let source = graph.makeInput(Pair(first: 1, second: 2))
            _ = graph.makeByteRangeAttribute(of: source, offset: 8, size: Int.max)
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
