import Testing
@testable import SwiftAttributeGraph

@Suite("OffsetIndirectEdgeCompareTests")
struct OffsetIndirectEdgeCompareTests {
    struct Pair: BitwiseCopyable, Equatable {
        var a: Int64
        var b: Int64
    }

    @Test func offsetIndirectCutsOutsideRangeAndPropagatesInsideRange() {
        let graph = Graph()
        let source = graph.makeInput(Pair(a: 1, b: 10))
        let bOffset = MemoryLayout<Pair>.offset(of: \Pair.b)!
        let offsetInd = graph.makeOffsetIndirect(of: source, offset: bOffset, size: MemoryLayout<Int64>.size)

        var runs = 0
        let consumer = graph.makeRule {
            runs += 1
            return offsetInd.value.b * 2
        }

        #expect(graph.value(of: consumer) == 20)
        #expect(runs == 1)

        // Change `a` only (outside `[bOffset, +8)`): cuts off.
        graph.setValue(Pair(a: 99, b: 10), for: source)
        #expect(graph.value(of: consumer) == 20)
        #expect(runs == 1)

        // Change `b` (inside range): re-evaluates.
        graph.setValue(Pair(a: 99, b: 25), for: source)
        #expect(graph.value(of: consumer) == 50)
        #expect(runs == 2)
    }

    @Test func offsetZeroWithFullSizeAlwaysMarksChangedAndSizeZeroNeverMarksChanged() {
        let graph = Graph()
        let source = graph.makeInput(Pair(a: 1, b: 2))
        let fullInd = graph.makeOffsetIndirect(of: source, offset: 0, size: MemoryLayout<Pair>.size)
        let zeroInd = graph.makeOffsetIndirect(of: source, offset: 0, size: 0)

        var fullRuns = 0
        let fullConsumer = graph.makeRule {
            fullRuns += 1
            return fullInd.value.a
        }
        var zeroRuns = 0
        let zeroConsumer = graph.makeRule {
            zeroRuns += 1
            return zeroInd.value.a
        }

        #expect(graph.value(of: fullConsumer) == 1)
        #expect(graph.value(of: zeroConsumer) == 1)
        #expect(fullRuns == 1 && zeroRuns == 1)

        graph.setValue(Pair(a: 3, b: 4), for: source)
        #expect(graph.value(of: fullConsumer) == 3)
        #expect(graph.value(of: zeroConsumer) == 1)
        #expect(fullRuns == 2 && zeroRuns == 1)
    }

    @Test func offsetIndirectAToBToAKeepsStickyBit() {
        let graph = Graph()
        let source = graph.makeInput(Pair(a: 1, b: 10))
        let bOffset = MemoryLayout<Pair>.offset(of: \Pair.b)!
        let offsetInd = graph.makeOffsetIndirect(of: source, offset: bOffset, size: MemoryLayout<Int64>.size)

        var runs = 0
        let consumer = graph.makeRule {
            runs += 1
            return offsetInd.value.b
        }
        #expect(graph.value(of: consumer) == 10)
        #expect(runs == 1)

        graph.setValue(Pair(a: 1, b: 20), for: source)
        graph.setValue(Pair(a: 1, b: 10), for: source)
        #expect(graph.value(of: consumer) == 10)
        #expect(runs == 2)
    }

    @Test func chainOfTwoIndirectsWithOffsetIndirectAndCleanup() {
        let graph = Graph()
        let baseSubgraphs = graph.liveSubgraphCount
        let sg = graph.makeSubgraph()
        let source = graph.makeInput(Pair(a: 1, b: 10))
        let bOffset = MemoryLayout<Pair>.offset(of: \Pair.b)!
        let offsetInd = graph.withCurrent(sg) { graph.makeOffsetIndirect(of: source, offset: bOffset, size: MemoryLayout<Int64>.size) }
        let outerInd = graph.withCurrent(sg) { graph.makeIndirect(offsetInd) }

        var runs = 0
        let consumer = graph.withCurrent(sg) {
            graph.makeRule {
                runs += 1
                return outerInd.value.b
            }
        }
        #expect(graph.value(of: consumer) == 10)
        #expect(runs == 1)

        graph.setValue(Pair(a: 99, b: 10), for: source)
        #expect(graph.value(of: consumer) == 10)
        #expect(runs == 1)

        graph.invalidate(sg)
        #expect(graph.liveSubgraphCount == baseSubgraphs)
        #expect(graph.offsetIndirects[offsetInd.id.index] == nil)
    }

    @Test func offsetIndirectChainTwentyThousandLevelsIsIterative() {
        let graph = Graph()
        let source = graph.makeInput(Pair(a: 1, b: 10))
        let bOffset = MemoryLayout<Pair>.offset(of: \Pair.b)!
        var tail = graph.makeOffsetIndirect(of: source, offset: bOffset, size: MemoryLayout<Int64>.size)
        for _ in 1..<20_000 {
            tail = graph.makeIndirect(tail)
        }
        var runs = 0
        let consumer = graph.makeRule {
            runs += 1
            return tail.value.b
        }
        #expect(graph.value(of: consumer) == 10)
        #expect(runs == 1)

        graph.setValue(Pair(a: 99, b: 10), for: source)
        #expect(graph.value(of: consumer) == 10)
        #expect(runs == 1)
    }

    @Test func offsetIndirectReleaseWritePerformance() {
        let graph = Graph()
        let source = graph.makeInput(Pair(a: 1, b: 10))
        let bOffset = MemoryLayout<Pair>.offset(of: \Pair.b)!
        var tail = graph.makeOffsetIndirect(of: source, offset: bOffset, size: MemoryLayout<Int64>.size)
        for _ in 1..<20_000 {
            tail = graph.makeIndirect(tail)
        }
        let consumer = graph.makeRule { tail.value.b }
        #expect(graph.value(of: consumer) == 10)

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for i in 0..<20 {
                graph.setValue(Pair(a: Int64(i), b: 10), for: source)
            }
        }
        print("PERF 20 writes over 20k offset-indirect chain: \(elapsed)")
        #expect(graph.value(of: consumer) == 10)
    }

    @Test func consumerDirtiedByOtherInputDoesNotReevaluateOffsetEdgeWhenRangeUnchanged() {
        let graph = Graph()
        let source = graph.makeInput(Pair(a: 1, b: 10))
        let other = graph.makeInput(100)
        let bOffset = MemoryLayout<Pair>.offset(of: \Pair.b)!
        let offsetInd = graph.makeOffsetIndirect(of: source, offset: bOffset, size: MemoryLayout<Int64>.size)

        var runs = 0
        let consumer = graph.makeRule {
            runs += 1
            return offsetInd.value.b + Int64(other.value)
        }
        #expect(graph.value(of: consumer) == 110)
        #expect(runs == 1)

        // Change `a` (outside range) and `other` (triggers consumer): `offsetInd` edge is not sticky-changed.
        graph.setValue(Pair(a: 99, b: 10), for: source)
        graph.setValue(200, for: other)
        #expect(graph.value(of: consumer) == 210)
        #expect(runs == 2)

        // Change `b` (inside range): consumer re-evaluates.
        graph.setValue(Pair(a: 99, b: 30), for: source)
        #expect(graph.value(of: consumer) == 230)
        #expect(runs == 3)
    }

    @Test func typedOffsetFieldAttributeProjectsFieldAndCutsOutsideChanges() {
        let graph = Graph()
        let source = graph.makeInput(Pair(a: 1, b: 10))
        let fieldAttr: Attribute<Int64> = graph.makeOffsetFieldAttribute(of: source, keyPath: \.b)

        var runs = 0
        let consumer = graph.makeRule {
            runs += 1
            return fieldAttr.value * 3
        }
        #expect(graph.value(of: consumer) == 30)
        #expect(runs == 1)

        graph.setValue(Pair(a: 99, b: 10), for: source)
        #expect(graph.value(of: consumer) == 30)
        #expect(runs == 1)

        graph.setValue(Pair(a: 99, b: 20), for: source)
        #expect(graph.value(of: consumer) == 60)
        #expect(runs == 2)
    }

    @Test func floatNaNAndNegativeZeroFollowRawByteComparison() {
        struct FloatPair: BitwiseCopyable, Equatable {
            var x: Float
            var y: Float
        }
        let graph = Graph()
        let source = graph.makeInput(FloatPair(x: 1.0, y: 0.0))
        let yOffset = MemoryLayout<FloatPair>.offset(of: \FloatPair.y)!
        let offsetInd = graph.makeOffsetIndirect(of: source, offset: yOffset, size: MemoryLayout<Float>.size)

        var runs = 0
        let consumer = graph.makeRule {
            runs += 1
            return offsetInd.value.y.bitPattern
        }
        #expect(graph.value(of: consumer) == Float(0.0).bitPattern)
        #expect(runs == 1)

        // +0.0 -> -0.0: raw bytes differ (sign bit), so consumer re-runs.
        graph.setValue(FloatPair(x: 1.0, y: -0.0), for: source)
        #expect(graph.value(of: consumer) == Float(-0.0).bitPattern)
        #expect(runs == 2)

        // NaN -> NaN (same bit pattern): raw bytes match, so consumer cuts off.
        graph.setValue(FloatPair(x: 1.0, y: .nan), for: source)
        #expect(graph.value(of: consumer) == Float.nan.bitPattern)
        #expect(runs == 3)
        graph.setValue(FloatPair(x: 2.0, y: .nan), for: source)
        #expect(runs == 3)
    }
}
