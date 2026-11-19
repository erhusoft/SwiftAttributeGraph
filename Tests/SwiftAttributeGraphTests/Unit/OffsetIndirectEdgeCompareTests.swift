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

    @Test func mixedChainSourceToOffsetToNormalIndirectToConsumer() {
        let graph = Graph()
        let source = graph.makeInput(Pair(a: 1, b: 10))
        let bOffset = MemoryLayout<Pair>.offset(of: \Pair.b)!
        let offsetO = graph.makeOffsetIndirect(of: source, offset: bOffset, size: MemoryLayout<Int64>.size)
        let normalP = graph.makeIndirect(offsetO)

        var runs = 0
        let consumer = graph.makeRule {
            runs += 1
            return normalP.value.b * 2
        }
        #expect(graph.value(of: consumer) == 20)
        #expect(runs == 1)

        // Range unchanged (`a` changed): consumer stays clean and does not re-run.
        graph.setValue(Pair(a: 99, b: 10), for: source)
        #expect(graph.table.state[Int(consumer.id.index)] & NodeState.dirty == 0)
        #expect(graph.value(of: consumer) == 20)
        #expect(runs == 1)

        // Range changed (`b` changed): consumer re-runs.
        graph.setValue(Pair(a: 99, b: 25), for: source)
        #expect(graph.value(of: consumer) == 50)
        #expect(runs == 2)

        // A -> B -> A before consumer evaluation: keeps sticky bit and re-runs.
        graph.setValue(Pair(a: 99, b: 30), for: source)
        graph.setValue(Pair(a: 99, b: 25), for: source)
        #expect(graph.value(of: consumer) == 50)
        #expect(runs == 3)
    }

    @Test func twoConsumersOnSameNormalIndirectOneWithOffsetOneFull() {
        let graph = Graph()
        let source = graph.makeInput(Pair(a: 1, b: 10))
        let bOffset = MemoryLayout<Pair>.offset(of: \Pair.b)!
        let offsetO = graph.makeOffsetIndirect(of: source, offset: bOffset, size: MemoryLayout<Int64>.size)
        let normalP = graph.makeIndirect(offsetO)
        let fullP = graph.makeIndirect(source)

        var offsetRuns = 0
        let offsetConsumer = graph.makeRule {
            offsetRuns += 1
            return normalP.value.b
        }
        var fullRuns = 0
        let fullConsumer = graph.makeRule {
            fullRuns += 1
            return fullP.value.a
        }

        #expect(graph.value(of: offsetConsumer) == 10)
        #expect(graph.value(of: fullConsumer) == 1)
        #expect(offsetRuns == 1 && fullRuns == 1)

        graph.setValue(Pair(a: 2, b: 10), for: source)
        #expect(graph.value(of: fullConsumer) == 2)
        #expect(graph.value(of: offsetConsumer) == 10)
        #expect(fullRuns == 2 && offsetRuns == 1)
    }

    @Test func redirectingIndirectTogglesOffsetInChainAndResetRestoresIt() {
        let graph = Graph()
        let source = graph.makeInput(Pair(a: 1, b: 10))
        let bOffset = MemoryLayout<Pair>.offset(of: \Pair.b)!
        let offsetO = graph.makeOffsetIndirect(of: source, offset: bOffset, size: MemoryLayout<Int64>.size)
        let normalInd = graph.makeIndirect(offsetO)
        let childInd = graph.makeIndirect(normalInd)

        #expect(graph.indirectsWithOffsetInChain.contains(normalInd.id.index))
        #expect(graph.indirectsWithOffsetInChain.contains(childInd.id.index))

        // Redirect away from offset chain -> clears flag on `normalInd` and `childInd`.
        graph.setSource(source, for: normalInd)
        #expect(!graph.indirectsWithOffsetInChain.contains(normalInd.id.index))
        #expect(!graph.indirectsWithOffsetInChain.contains(childInd.id.index))

        // Reset back to `offsetO` -> restores flag on both.
        graph.resetSource(for: normalInd)
        #expect(graph.indirectsWithOffsetInChain.contains(normalInd.id.index))
        #expect(graph.indirectsWithOffsetInChain.contains(childInd.id.index))
    }

    @Test func diamondWithDifferentOffsetRangesUsesFirstDiscoveredInBFS() {
        let graph = Graph()
        let source = graph.makeInput(Pair(a: 1, b: 10))
        let aOffset = MemoryLayout<Pair>.offset(of: \Pair.a)!
        let bOffset = MemoryLayout<Pair>.offset(of: \Pair.b)!
        let indA = graph.makeOffsetIndirect(of: source, offset: aOffset, size: MemoryLayout<Int64>.size)
        let indB = graph.makeOffsetIndirect(of: source, offset: bOffset, size: MemoryLayout<Int64>.size)
        let consumer = graph.makeRule { indA.value.a + indB.value.b }
        #expect(graph.value(of: consumer) == 11)

        // Changing `a` triggers `indA` edge; consumer re-runs.
        graph.setValue(Pair(a: 2, b: 10), for: source)
        #expect(graph.value(of: consumer) == 12)
    }

    @Test func redirectingUpstreamIndirectPreservesDownstreamOffsetIndirectFlag() {
        let graph = Graph()
        let s1 = graph.makeInput(Pair(a: 1, b: 10))
        let s2 = graph.makeInput(Pair(a: 2, b: 10))
        let indA = graph.makeIndirect(s1)
        let bOffset = MemoryLayout<Pair>.offset(of: \Pair.b)!
        let offsetO = graph.makeOffsetIndirect(of: indA, offset: bOffset, size: MemoryLayout<Int64>.size)
        let indP = graph.makeIndirect(offsetO)

        var runs = 0
        let consumer = graph.makeRule {
            runs += 1
            return indP.value.b * 2
        }
        #expect(graph.value(of: consumer) == 20)
        #expect(runs == 1)

        // Redirect `indA` to `s2` (same `b = 10`, `a = 2`): `indP` must still be in `indirectsWithOffsetInChain`
        // because it is under `offsetO`.
        graph.setSource(s2, for: indA)
        #expect(graph.indirectsWithOffsetInChain.contains(indP.id.index))

        // Writing `a` only on `s2` must still cut off `consumer`.
        graph.setValue(Pair(a: 99, b: 10), for: s2)
        #expect(graph.value(of: consumer) == 20)
        #expect(runs == 1)

        // Writing `b` on `s2` re-evaluates `consumer`.
        graph.setValue(Pair(a: 99, b: 30), for: s2)
        #expect(graph.value(of: consumer) == 60)
        #expect(runs == 2)
    }
}
