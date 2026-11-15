import Testing
@testable import MiniUIAppCore

@Suite
@MainActor
struct MiniUIAppTests {
    @Test
    func verifyStepByStepCountsAndSubgraphTeardown() {
        let bridge = EngineBridge()

        #expect(bridge.snapshot.counter == 0)
        #expect(bridge.snapshot.altValue == 100)
        #expect(bridge.snapshot.parityText == "Par (even)")
        #expect(bridge.snapshot.parityRuns == 1)
        #expect(bridge.snapshot.activeIndirectValue == 0)
        #expect(bridge.snapshot.detailText == nil)
        #expect(bridge.snapshot.detailRuns == 0)
        #expect(bridge.snapshot.nodeCount == 7)
        #expect(bridge.snapshot.edgeCount == 7)
        #expect(bridge.snapshot.subgraphCount == 1)
        #expect(bridge.snapshot.recalculationCount == 3)
        #expect(bridge.snapshotPublishCount == 0)
        #expect(bridge.dirtyNotificationCount == 0)

        // +2 keeps parity even -> parityRuns remains 1.
        bridge.incrementCounter(by: 2)
        bridge.flushUI()
        #expect(bridge.snapshot.counter == 2)
        #expect(bridge.snapshot.parityText == "Par (even)")
        #expect(bridge.snapshot.parityRuns == 1)
        #expect(bridge.snapshot.activeIndirectValue == 2)
        #expect(bridge.snapshot.recalculationCount == 5)
        #expect(bridge.snapshotPublishCount == 1)
        #expect(bridge.dirtyNotificationCount == 1)

        // +1 changes parity to odd -> parityRuns becomes 2.
        bridge.incrementCounter(by: 1)
        bridge.flushUI()
        #expect(bridge.snapshot.counter == 3)
        #expect(bridge.snapshot.parityText == "Impar (odd)")
        #expect(bridge.snapshot.parityRuns == 2)
        #expect(bridge.snapshot.activeIndirectValue == 3)
        #expect(bridge.snapshot.recalculationCount == 8)
        #expect(bridge.snapshotPublishCount == 2)
        #expect(bridge.dirtyNotificationCount == 2)

        // Updating inactive alt branch does not trigger indirect or parity recalcs.
        bridge.incrementAlt(by: 10)
        bridge.flushUI()
        #expect(bridge.snapshot.altValue == 110)
        #expect(bridge.snapshot.activeIndirectValue == 3)
        #expect(bridge.snapshot.parityRuns == 2)
        #expect(bridge.snapshot.recalculationCount == 9)
        #expect(bridge.snapshotPublishCount == 3)
        #expect(bridge.dirtyNotificationCount == 3)

        // Switching indirect source to alt exposes 110.
        bridge.toggleIndirectSource()
        bridge.flushUI()
        #expect(bridge.snapshot.activeIndirectValue == 110)
        #expect(bridge.snapshot.recalculationCount == 10)
        #expect(bridge.snapshotPublishCount == 4)
        #expect(bridge.dirtyNotificationCount == 4)

        // Mounting detailSubgraph adds 1 node, 3 edges, 1 subgraph.
        bridge.setShowDetail(true)
        bridge.flushUI()
        #expect(bridge.snapshot.detailText == "Detalle vivo: counter=3, indirect=110")
        #expect(bridge.snapshot.detailRuns == 1)
        #expect(bridge.snapshot.nodeCount == 8)
        #expect(bridge.snapshot.edgeCount == 10)
        #expect(bridge.snapshot.subgraphCount == 2)
        #expect(bridge.snapshot.recalculationCount == 12)
        #expect(bridge.snapshotPublishCount == 5)
        #expect(bridge.dirtyNotificationCount == 5)

        // Updating counter while detailSubgraph is mounted updates detailRuns to 2.
        bridge.incrementCounter(by: 2)
        bridge.flushUI()
        #expect(bridge.snapshot.counter == 5)
        #expect(bridge.snapshot.detailText == "Detalle vivo: counter=5, indirect=110")
        #expect(bridge.snapshot.detailRuns == 2)
        #expect(bridge.snapshot.nodeCount == 8)
        #expect(bridge.snapshot.edgeCount == 10)
        #expect(bridge.snapshot.subgraphCount == 2)
        #expect(bridge.snapshot.recalculationCount == 15)
        #expect(bridge.snapshotPublishCount == 6)
        #expect(bridge.dirtyNotificationCount == 6)

        // Unmounting detailSubgraph returns nodeCount/edgeCount/subgraphCount to baseline.
        bridge.setShowDetail(false)
        bridge.flushUI()
        #expect(bridge.snapshot.detailText == nil)
        #expect(bridge.snapshot.detailRuns == 2)
        #expect(bridge.snapshot.nodeCount == 7)
        #expect(bridge.snapshot.edgeCount == 7)
        #expect(bridge.snapshot.subgraphCount == 1)
        #expect(bridge.snapshot.recalculationCount == 16)
        #expect(bridge.snapshotPublishCount == 7)
        #expect(bridge.dirtyNotificationCount == 7)
    }

    @Test
    func batchCoalescesMultipleMutationsIntoSingleRefresh() {
        let bridge = EngineBridge()
        #expect(bridge.snapshotPublishCount == 0)
        #expect(bridge.dirtyNotificationCount == 0)

        bridge.performBatch {
            bridge.incrementCounter(by: 2)
            bridge.incrementAlt(by: 5)
        }
        bridge.flushUI()

        #expect(bridge.snapshot.counter == 2)
        #expect(bridge.snapshot.altValue == 105)
        #expect(bridge.snapshot.parityRuns == 1)
        #expect(bridge.dirtyNotificationCount == 1)
        #expect(bridge.snapshotPublishCount == 1)
    }

    @Test
    func repeatedMountUnmountCyclesReturnToBaseline() {
        let bridge = EngineBridge()
        for cycle in 1...10 {
            bridge.setShowDetail(true)
            bridge.flushUI()
            #expect(bridge.snapshot.nodeCount == 8)
            #expect(bridge.snapshot.edgeCount == 10)
            #expect(bridge.snapshot.subgraphCount == 2)
            #expect(bridge.snapshot.detailRuns == cycle)

            bridge.setShowDetail(false)
            bridge.flushUI()
            #expect(bridge.snapshot.nodeCount == 7)
            #expect(bridge.snapshot.edgeCount == 7)
            #expect(bridge.snapshot.subgraphCount == 1)
        }
    }

    @Test
    func realSwiftUIParityAgainstObservableShowsEqualityCutAdvantage() {
        let report = runRealSwiftUIParityComparison()

        // Dynamic dependency tracking matches between @Observable and SwiftAttributeGraph:
        #expect(report.native.counterBodyRuns == 4)
        #expect(report.engine.counterBodyRuns == 4)
        #expect(report.native.altBodyRuns == 2)
        #expect(report.engine.altBodyRuns == 2)
        #expect(report.native.indirectBodyRuns == 4)
        #expect(report.engine.indirectBodyRuns == 4)
        #expect(report.native.detailBodyRuns == 3)
        #expect(report.engine.detailBodyRuns == 3)

        // @Observable re-runs parity body whenever `counter` changes (4 runs),
        // while SwiftAttributeGraph cuts equal outputs ("Par" == "Par", "Impar" == "Impar") -> 2 runs.
        #expect(report.native.parityBodyRuns == 4)
        #expect(report.engine.parityBodyRuns == 2)
        #expect(report.engineParityNodeRuns == 2)
        #expect(report.engineDetailNodeRuns == 2)
        #expect(report.engine.totalBodyRuns < report.native.totalBodyRuns)
    }
}
