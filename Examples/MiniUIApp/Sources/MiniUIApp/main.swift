import AppKit
import Foundation
import MiniUIAppCore
import SwiftUI

private func check(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) {
    if !condition() {
        fputs("Verification failed: \(message)\n", stderr)
        exit(1)
    }
}

@MainActor
private func assertSnapshotState(
    _ bridge: EngineBridge,
    label: String,
    counter: Int,
    altValue: Int,
    parityText: String,
    parityRuns: Int,
    indirect: Int,
    detail: String?,
    detailRuns: Int,
    nodes: Int,
    edges: Int,
    subgraphs: Int,
    recalcs: Int,
    publishes: Int,
    dirtyNotifications: Int
) {
    let s = bridge.snapshot
    print(
        "[\(label)] counter=\(s.counter) alt=\(s.altValue) parity=\"\(s.parityText)\" "
            + "parityRuns=\(s.parityRuns) indirect=\(s.activeIndirectValue) "
            + "detail=\(s.detailText ?? "nil") detailRuns=\(s.detailRuns) "
            + "nodes=\(s.nodeCount) edges=\(s.edgeCount) subgraphs=\(s.subgraphCount) "
            + "recalcs=\(s.recalculationCount) publishes=\(bridge.snapshotPublishCount) "
            + "dirty=\(bridge.dirtyNotificationCount)"
    )

    check(s.counter == counter, "\(label): expected counter=\(counter), got \(s.counter)")
    check(s.altValue == altValue, "\(label): expected altValue=\(altValue), got \(s.altValue)")
    check(
        s.parityText == parityText,
        "\(label): expected parityText=\"\(parityText)\", got \"\(s.parityText)\""
    )
    check(
        s.parityRuns == parityRuns,
        "\(label): expected parityRuns=\(parityRuns), got \(s.parityRuns)"
    )
    check(
        s.activeIndirectValue == indirect,
        "\(label): expected indirect=\(indirect), got \(s.activeIndirectValue)"
    )
    check(
        s.detailText == detail,
        "\(label): expected detail=\(detail ?? "nil"), got \(s.detailText ?? "nil")"
    )
    check(
        s.detailRuns == detailRuns,
        "\(label): expected detailRuns=\(detailRuns), got \(s.detailRuns)"
    )
    check(s.nodeCount == nodes, "\(label): expected nodes=\(nodes), got \(s.nodeCount)")
    check(s.edgeCount == edges, "\(label): expected edges=\(edges), got \(s.edgeCount)")
    check(
        s.subgraphCount == subgraphs,
        "\(label): expected subgraphs=\(subgraphs), got \(s.subgraphCount)"
    )
    check(
        s.recalculationCount == recalcs,
        "\(label): expected recalcs=\(recalcs), got \(s.recalculationCount)"
    )
    check(
        bridge.snapshotPublishCount == publishes,
        "\(label): expected publishes=\(publishes), got \(bridge.snapshotPublishCount)"
    )
    check(
        bridge.dirtyNotificationCount == dirtyNotifications,
        "\(label): expected dirtyNotifications=\(dirtyNotifications), got \(bridge.dirtyNotificationCount)"
    )
}

@MainActor
private func runVerification() {
    let bridge = EngineBridge()
    assertSnapshotState(
        bridge,
        label: "initial",
        counter: 0,
        altValue: 100,
        parityText: "Par (even)",
        parityRuns: 1,
        indirect: 0,
        detail: nil,
        detailRuns: 0,
        nodes: 7,
        edges: 7,
        subgraphs: 1,
        recalcs: 3,
        publishes: 0,
        dirtyNotifications: 0
    )

    bridge.incrementCounter(by: 2)
    bridge.flushUI()
    assertSnapshotState(
        bridge,
        label: "+2 (misma paridad)",
        counter: 2,
        altValue: 100,
        parityText: "Par (even)",
        parityRuns: 1,
        indirect: 2,
        detail: nil,
        detailRuns: 0,
        nodes: 7,
        edges: 7,
        subgraphs: 1,
        recalcs: 5,
        publishes: 1,
        dirtyNotifications: 1
    )

    bridge.incrementCounter(by: 1)
    bridge.flushUI()
    assertSnapshotState(
        bridge,
        label: "+1 (cambia paridad)",
        counter: 3,
        altValue: 100,
        parityText: "Impar (odd)",
        parityRuns: 2,
        indirect: 3,
        detail: nil,
        detailRuns: 0,
        nodes: 7,
        edges: 7,
        subgraphs: 1,
        recalcs: 8,
        publishes: 2,
        dirtyNotifications: 2
    )

    bridge.incrementAlt(by: 10)
    bridge.flushUI()
    assertSnapshotState(
        bridge,
        label: "alt +10",
        counter: 3,
        altValue: 110,
        parityText: "Impar (odd)",
        parityRuns: 2,
        indirect: 3,
        detail: nil,
        detailRuns: 0,
        nodes: 7,
        edges: 7,
        subgraphs: 1,
        recalcs: 9,
        publishes: 3,
        dirtyNotifications: 3
    )

    bridge.toggleIndirectSource()
    bridge.flushUI()
    assertSnapshotState(
        bridge,
        label: "setSource -> alt",
        counter: 3,
        altValue: 110,
        parityText: "Impar (odd)",
        parityRuns: 2,
        indirect: 110,
        detail: nil,
        detailRuns: 0,
        nodes: 7,
        edges: 7,
        subgraphs: 1,
        recalcs: 10,
        publishes: 4,
        dirtyNotifications: 4
    )

    bridge.setShowDetail(true)
    bridge.flushUI()
    assertSnapshotState(
        bridge,
        label: "mount detailSubgraph",
        counter: 3,
        altValue: 110,
        parityText: "Impar (odd)",
        parityRuns: 2,
        indirect: 110,
        detail: "Detalle vivo: counter=3, indirect=110",
        detailRuns: 1,
        nodes: 8,
        edges: 10,
        subgraphs: 2,
        recalcs: 12,
        publishes: 5,
        dirtyNotifications: 5
    )

    bridge.incrementCounter(by: 2)
    bridge.flushUI()
    assertSnapshotState(
        bridge,
        label: "+2 con detail vivo",
        counter: 5,
        altValue: 110,
        parityText: "Impar (odd)",
        parityRuns: 2,
        indirect: 110,
        detail: "Detalle vivo: counter=5, indirect=110",
        detailRuns: 2,
        nodes: 8,
        edges: 10,
        subgraphs: 2,
        recalcs: 15,
        publishes: 6,
        dirtyNotifications: 6
    )

    bridge.setShowDetail(false)
    bridge.flushUI()
    assertSnapshotState(
        bridge,
        label: "unmount detailSubgraph",
        counter: 5,
        altValue: 110,
        parityText: "Impar (odd)",
        parityRuns: 2,
        indirect: 110,
        detail: nil,
        detailRuns: 2,
        nodes: 7,
        edges: 7,
        subgraphs: 1,
        recalcs: 16,
        publishes: 7,
        dirtyNotifications: 7
    )

    // Verify batch coalescing: multiple mutations in a single batch produce 1 dirty notification
    // and 1 snapshot publish.
    let publishesBeforeBatch = bridge.snapshotPublishCount
    let dirtyBeforeBatch = bridge.dirtyNotificationCount
    bridge.performBatch {
        bridge.incrementCounter(by: 1)
        bridge.incrementAlt(by: 5)
    }
    bridge.flushUI()
    check(
        bridge.dirtyNotificationCount == dirtyBeforeBatch + 1,
        "batch should produce 1 dirty notification, got \(bridge.dirtyNotificationCount - dirtyBeforeBatch)"
    )
    check(
        bridge.snapshotPublishCount == publishesBeforeBatch + 1,
        "batch should produce 1 snapshot publish, got \(bridge.snapshotPublishCount - publishesBeforeBatch)"
    )

    print("VERIFY OK")
}

@MainActor
private func runBenchmark() {
    let trials = 9
    let interactionsPerTrial = 1_000
    let clock = ContinuousClock()
    var perInteractionMs: [Double] = []
    perInteractionMs.reserveCapacity(trials)

    for _ in 0..<trials {
        let bridge = EngineBridge()
        bridge.setShowDetail(true)
        bridge.flushUI()
        let startPublishes = bridge.snapshotPublishCount
        let startDirty = bridge.dirtyNotificationCount

        let elapsed = clock.measure {
            for step in 0..<interactionsPerTrial {
                switch step % 4 {
                case 0:
                    bridge.incrementCounter(by: 1)
                case 1:
                    bridge.incrementCounter(by: 2)
                case 2:
                    bridge.incrementAlt(by: 3)
                default:
                    bridge.toggleIndirectSource()
                }
                bridge.flushUI()
            }
        }

        let totalSeconds =
            Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        let msPerInteraction = (totalSeconds * 1_000.0) / Double(interactionsPerTrial)
        perInteractionMs.append(msPerInteraction)

        let deltaPublishes = bridge.snapshotPublishCount - startPublishes
        let deltaDirty = bridge.dirtyNotificationCount - startDirty
        check(
            deltaPublishes == interactionsPerTrial,
            "expected \(interactionsPerTrial) publishes, got \(deltaPublishes)"
        )
        check(
            deltaDirty == interactionsPerTrial,
            "expected \(interactionsPerTrial) dirty notifications, got \(deltaDirty)"
        )
    }

    let sorted = perInteractionMs.sorted()
    let medianMs = sorted[sorted.count / 2]
    let minMs = sorted.first ?? 0
    let maxMs = sorted.last ?? 0
    let budgetMs = 1.6

    print(
        String(
            format: "BENCH (%d trials x %d interactions): median=%.4f ms/op, min=%.4f ms/op, max=%.4f ms/op, budget=%.2f ms (%.1fx headroom)",
            trials,
            interactionsPerTrial,
            medianMs,
            minMs,
            maxMs,
            budgetMs,
            budgetMs / max(medianMs, 1e-9)
        )
    )
    print("REFRESH_RATIO: 1.00 publishes/interaction, 1.00 dirtyNotifications/interaction")
}

@MainActor
private func runParity() {
    let report = runRealSwiftUIParityComparison()
    print("PARITY NATIVE @Observable body runs:")
    print(
        "  counter=\(report.native.counterBodyRuns) alt=\(report.native.altBodyRuns) "
            + "parity=\(report.native.parityBodyRuns) indirect=\(report.native.indirectBodyRuns) "
            + "detail=\(report.native.detailBodyRuns) total=\(report.native.totalBodyRuns)"
    )
    print("PARITY ENGINE SwiftAttributeGraph body runs:")
    print(
        "  counter=\(report.engine.counterBodyRuns) alt=\(report.engine.altBodyRuns) "
            + "parity=\(report.engine.parityBodyRuns) indirect=\(report.engine.indirectBodyRuns) "
            + "detail=\(report.engine.detailBodyRuns) total=\(report.engine.totalBodyRuns) "
            + "(engine parityNodeRuns=\(report.engineParityNodeRuns), detailNodeRuns=\(report.engineDetailNodeRuns))"
    )
}

@MainActor
private func runStress() {
    let report = runStressScenario()
    print(
        String(
            format: "STRESS SUBGRAPHS (%d rows): peakNodes=%d peakEdges=%d peakSubgraphs=%d -> afterUnmount nodes=%d edges=%d subgraphs=%d (%.2f ms)",
            report.rowCount,
            report.peakNodes,
            report.peakEdges,
            report.peakSubgraphs,
            report.afterUnmountNodes,
            report.afterUnmountEdges,
            report.afterUnmountSubgraphs,
            report.mountUnmountMs
        )
    )
    print(
        String(
            format: "STRESS MULTI-SOURCE (%d writes across %d batches): dirtyNotifications=%d combinedRuleRuns=%d (%.2f ms)",
            report.multiSourceWrites,
            report.multiSourceBatches,
            report.multiSourceDirtyNotifications,
            report.combinedRuleRuns,
            report.multiSourceBatchMs
        )
    )
    check(
        report.afterUnmountNodes == 0 && report.afterUnmountEdges == 0 && report.afterUnmountSubgraphs == 1,
        "expected clean teardown to 0 nodes, 0 edges, 1 root subgraph"
    )
    check(
        report.multiSourceDirtyNotifications == report.multiSourceBatches,
        "expected 1 dirty notification per batch"
    )
    check(
        report.combinedRuleRuns == 1 + report.multiSourceBatches,
        "expected 1 combined rule run per batch after initial read"
    )
    print("STRESS OK")
}

@MainActor
private func renderSnapshot(to path: String) {
    NSApplication.shared.setActivationPolicy(.accessory)
    let bridge = EngineBridge()
    bridge.incrementCounter(by: 2)
    bridge.flushUI()
    bridge.incrementCounter(by: 1)
    bridge.flushUI()
    bridge.setShowDetail(true)

    let size = NSSize(width: 780, height: 680)
    let hostingView = NSHostingView(rootView: ContentView(bridge: bridge))
    hostingView.frame = NSRect(origin: .zero, size: size)
    hostingView.appearance = NSAppearance(named: .aqua)

    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    window.appearance = NSAppearance(named: .aqua)
    window.contentView = hostingView
    hostingView.layoutSubtreeIfNeeded()

    guard let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
        fputs("Failed to allocate bitmapImageRepForCachingDisplay\n", stderr)
        exit(1)
    }
    hostingView.cacheDisplay(in: hostingView.bounds, to: rep)

    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        fputs("Failed to encode PNG\n", stderr)
        exit(1)
    }

    do {
        try pngData.write(to: URL(fileURLWithPath: path))
        print("Snapshot saved to \(path) (\(pngData.count) bytes)")
    } catch {
        fputs("Failed to write snapshot: \(error)\n", stderr)
        exit(1)
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let bridge = EngineBridge()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hostingController = NSHostingController(rootView: ContentView(bridge: bridge))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "SwiftAttributeGraph — MiniUIApp"
        window.setContentSize(NSSize(width: 780, height: 680))
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@MainActor
private func runMain() {
    let args = CommandLine.arguments
    if args.contains("--verify") {
        runVerification()
        return
    }

    if args.contains("--bench") {
        runBenchmark()
        return
    }

    if args.contains("--parity") {
        runParity()
        return
    }

    if args.contains("--stress") {
        runStress()
        return
    }

    if let idx = args.firstIndex(of: "--snapshot"), idx + 1 < args.count {
        renderSnapshot(to: args[idx + 1])
        return
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}

MainActor.assumeIsolated {
    runMain()
}
