import AppKit
import Foundation
import SwiftAttributeGraph
import SwiftUI

/// Summary statistics (median, minimum, maximum) in milliseconds across repeated trials.
public struct TimingStats: Equatable, Sendable {
    public let medianMs: Double
    public let minMs: Double
    public let maxMs: Double

    public init(samplesMs: [Double]) {
        let sorted = samplesMs.sorted()
        self.minMs = sorted.first ?? 0
        self.maxMs = sorted.last ?? 0
        self.medianMs = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }
}

/// Results from stressing `SwiftAttributeGraph` with thousands of dynamic subgraphs
/// and rapid multi-source batched writes across repeated trials.
public struct StressReport: Equatable, Sendable {
    public let trials: Int
    public let rowCount: Int
    public let peakNodes: Int
    public let peakEdges: Int
    public let peakSubgraphs: Int
    public let afterHalfUnmountNodes: Int
    public let afterHalfUnmountEdges: Int
    public let afterHalfUnmountSubgraphs: Int
    public let afterUnmountNodes: Int
    public let afterUnmountEdges: Int
    public let afterUnmountSubgraphs: Int
    public let mountUnmountStats: TimingStats

    public let multiSourceWrites: Int
    public let multiSourceBatches: Int
    public let multiSourceDirtyNotifications: Int
    public let combinedRuleRuns: Int
    public let multiSourceBatchStats: TimingStats
}

/// Results from mounting a 2,000-row `LazyVStack` in a real `NSHostingView`, mutating
/// specific rows, and unmounting everything, separating engine cost from SwiftUI cost.
public struct RealSwiftUIStressReport: Equatable, Sendable {
    public let rowCount: Int
    public let mutatedRowCount: Int
    public let initialRowBodyRuns: Int
    public let afterMutationRowBodyRuns: Int
    public let afterUnmountNodes: Int
    public let afterUnmountEdges: Int
    public let afterUnmountSubgraphs: Int
    public let engineMountMs: Double
    public let swiftUIMountMs: Double
    public let engineMutationMs: Double
    public let swiftUIMutationMs: Double
    public let engineUnmountMs: Double
    public let swiftUIUnmountMs: Double
}

private struct RowEntry {
    let subgraph: Subgraph
    let input: Attribute<Int>
    let label: Attribute<String>
}

private func elapsedMs(_ duration: Duration) -> Double {
    (Double(duration.components.seconds)
        + Double(duration.components.attoseconds) / 1e18) * 1_000.0
}

/// Runs two engine-only stress checks across `trials` rounds (default 9):
/// 1. Mounts `rowCount` row subgraphs, unmounts the even half (capturing intermediate counts),
///    remounts replacements, unmounts all, and verifies `nodeCount == 0`, `edgeCount == 0`,
///    and `liveSubgraphCount == 1`.
/// 2. Fires `batchCount` rapid multi-source write batches (4 sources per batch) and verifies
///    1 dirty notification and 1 combined recalculation per batch (no redundant work).
public func runStressScenario(
    rowCount: Int = 2_000,
    batchCount: Int = 250,
    trials: Int = 9
) -> StressReport {
    let clock = ContinuousClock()
    var mountSamplesMs: [Double] = []
    var batchSamplesMs: [Double] = []
    mountSamplesMs.reserveCapacity(trials)
    batchSamplesMs.reserveCapacity(trials)

    var lastPeakNodes = 0
    var lastPeakEdges = 0
    var lastPeakSubgraphs = 0
    var lastHalfNodes = 0
    var lastHalfEdges = 0
    var lastHalfSubgraphs = 0
    var lastAfterNodes = 0
    var lastAfterEdges = 0
    var lastAfterSubgraphs = 0
    var lastDirtyCount = 0
    var lastCombinedRuns = 0

    for _ in 0..<trials {
        // Part A: Massive subgraph mount/unmount stress (engine only).
        let gRows = Graph()
        var rows: [RowEntry] = []
        rows.reserveCapacity(rowCount)

        let partAElapsed = clock.measure {
            for i in 0..<rowCount {
                let sub = gRows.makeSubgraph()
                let entry = gRows.withCurrent(sub) {
                    let input = gRows.makeInput(i)
                    let label = gRows.makeRule { "Row \(i): \(input.value)" }
                    _ = gRows.value(of: label)
                    return RowEntry(subgraph: sub, input: input, label: label)
                }
                rows.append(entry)
            }

            lastPeakNodes = gRows.nodeCount
            lastPeakEdges = gRows.edgeCount
            lastPeakSubgraphs = gRows.liveSubgraphCount

            // Unmount even rows and record intermediate counts.
            var surviving: [RowEntry] = []
            surviving.reserveCapacity(rowCount / 2)
            for (idx, entry) in rows.enumerated() {
                if idx.isMultiple(of: 2) {
                    gRows.invalidate(entry.subgraph)
                } else {
                    surviving.append(entry)
                }
            }

            lastHalfNodes = gRows.nodeCount
            lastHalfEdges = gRows.edgeCount
            lastHalfSubgraphs = gRows.liveSubgraphCount

            // Remount replacements for the unmounted half.
            for i in 0..<(rowCount - surviving.count) {
                let sub = gRows.makeSubgraph()
                let entry = gRows.withCurrent(sub) {
                    let input = gRows.makeInput(rowCount + i)
                    let label = gRows.makeRule { "Row \(rowCount + i): \(input.value)" }
                    _ = gRows.value(of: label)
                    return RowEntry(subgraph: sub, input: input, label: label)
                }
                surviving.append(entry)
            }

            // Unmount all remaining rows.
            for entry in surviving {
                gRows.invalidate(entry.subgraph)
            }
        }

        lastAfterNodes = gRows.nodeCount
        lastAfterEdges = gRows.edgeCount
        lastAfterSubgraphs = gRows.liveSubgraphCount
        mountSamplesMs.append(elapsedMs(partAElapsed))

        // Part B: Rapid multi-source batched writes (engine only).
        let gMulti = Graph()
        let s0 = gMulti.makeInput(0)
        let s1 = gMulti.makeInput(0)
        let s2 = gMulti.makeInput(0)
        let s3 = gMulti.makeInput(0)

        var combinedRuns = 0
        let combined = gMulti.makeRule { () -> Int in
            combinedRuns += 1
            return s0.value + s1.value + s2.value + s3.value
        }

        _ = gMulti.value(of: combined)
        var dirtyCount = 0
        let token = gMulti.observe(combined.erased) {
            dirtyCount += 1
        }

        let partBElapsed = clock.measure {
            for step in 1...batchCount {
                gMulti.withBatch {
                    gMulti.setValue(step, for: s0)
                    gMulti.setValue(step * 2, for: s1)
                    gMulti.setValue(step * 3, for: s2)
                    gMulti.setValue(step * 4, for: s3)
                }
                _ = gMulti.value(of: combined)
            }
        }
        _ = token

        lastDirtyCount = dirtyCount
        lastCombinedRuns = combinedRuns
        batchSamplesMs.append(elapsedMs(partBElapsed))
    }

    return StressReport(
        trials: trials,
        rowCount: rowCount,
        peakNodes: lastPeakNodes,
        peakEdges: lastPeakEdges,
        peakSubgraphs: lastPeakSubgraphs,
        afterHalfUnmountNodes: lastHalfNodes,
        afterHalfUnmountEdges: lastHalfEdges,
        afterHalfUnmountSubgraphs: lastHalfSubgraphs,
        afterUnmountNodes: lastAfterNodes,
        afterUnmountEdges: lastAfterEdges,
        afterUnmountSubgraphs: lastAfterSubgraphs,
        mountUnmountStats: TimingStats(samplesMs: mountSamplesMs),
        multiSourceWrites: batchCount * 4,
        multiSourceBatches: batchCount,
        multiSourceDirtyNotifications: lastDirtyCount,
        combinedRuleRuns: lastCombinedRuns,
        multiSourceBatchStats: TimingStats(samplesMs: batchSamplesMs)
    )
}

@MainActor
private final class StressRowItem: Identifiable {
    let id: Int
    let subgraph: Subgraph
    let input: Attribute<Int>
    let box: AttributeBox<String>

    init(id: Int, subgraph: Subgraph, input: Attribute<Int>, box: AttributeBox<String>) {
        self.id = id
        self.subgraph = subgraph
        self.input = input
        self.box = box
    }
}

@MainActor
private final class StressListModel: ObservableObject {
    let graph = Graph()
    @Published var rows: [StressRowItem] = []
    var rowBodyRuns = 0

    func mountRows(_ count: Int) {
        var created: [StressRowItem] = []
        created.reserveCapacity(count)
        for i in 0..<count {
            let sub = graph.makeSubgraph()
            let (input, label) = graph.withCurrent(sub) {
                let input = graph.makeInput(i)
                let label = graph.makeRule { "Row \(i): \(input.value)" }
                return (input, label)
            }
            let box = AttributeBox(graph: graph, attribute: label)
            created.append(StressRowItem(id: i, subgraph: sub, input: input, box: box))
        }
        rows = created
    }

    func mutateFirstRows(_ count: Int) {
        for i in 0..<min(count, rows.count) {
            let row = rows[i]
            let next = graph.value(of: row.input) + 100
            graph.setValue(next, for: row.input)
            row.box.syncIfChanged()
        }
    }

    func unmountAllRows() {
        let existing = rows
        rows = []
        for row in existing {
            graph.invalidate(row.subgraph)
        }
    }
}

private struct StressRowView: View {
    @ObservedObject var box: AttributeBox<String>
    let model: StressListModel

    var body: some View {
        model.rowBodyRuns += 1
        return Text(box.value)
            .frame(height: 20, alignment: .leading)
    }
}

private struct StressListHarnessView: View {
    @ObservedObject var model: StressListModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(model.rows) { row in
                    StressRowView(box: row.box, model: model)
                }
            }
        }
        .frame(width: 360, height: 300)
    }
}

@MainActor
private func pumpStressSwiftUI<V: View>(_ hostingView: NSHostingView<V>) {
    hostingView.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    hostingView.layoutSubtreeIfNeeded()
}

/// Mounts a 2,000-row `LazyVStack` in a real `NSHostingView`, mutates `mutatedRowCount`
/// visible rows, unmounts the entire list, and measures engine time separately from SwiftUI time.
@MainActor
public func runRealSwiftUIStressList(
    rowCount: Int = 2_000,
    mutatedRowCount: Int = 5
) -> RealSwiftUIStressReport {
    NSApplication.shared.setActivationPolicy(.accessory)
    let clock = ContinuousClock()
    let model = StressListModel()

    let size = NSSize(width: 360, height: 300)
    let hostingView = NSHostingView(rootView: StressListHarnessView(model: model))
    hostingView.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentView = hostingView
    defer { window.close() }

    let engineMountElapsed = clock.measure {
        model.mountRows(rowCount)
    }
    let swiftUIMountElapsed = clock.measure {
        pumpStressSwiftUI(hostingView)
    }
    let initialRowBodyRuns = model.rowBodyRuns

    model.rowBodyRuns = 0
    let engineMutationElapsed = clock.measure {
        model.mutateFirstRows(mutatedRowCount)
    }
    let swiftUIMutationElapsed = clock.measure {
        pumpStressSwiftUI(hostingView)
    }
    let afterMutationRowBodyRuns = model.rowBodyRuns

    let engineUnmountElapsed = clock.measure {
        model.unmountAllRows()
    }
    let swiftUIUnmountElapsed = clock.measure {
        pumpStressSwiftUI(hostingView)
    }

    return RealSwiftUIStressReport(
        rowCount: rowCount,
        mutatedRowCount: mutatedRowCount,
        initialRowBodyRuns: initialRowBodyRuns,
        afterMutationRowBodyRuns: afterMutationRowBodyRuns,
        afterUnmountNodes: model.graph.nodeCount,
        afterUnmountEdges: model.graph.edgeCount,
        afterUnmountSubgraphs: model.graph.liveSubgraphCount,
        engineMountMs: elapsedMs(engineMountElapsed),
        swiftUIMountMs: elapsedMs(swiftUIMountElapsed),
        engineMutationMs: elapsedMs(engineMutationElapsed),
        swiftUIMutationMs: elapsedMs(swiftUIMutationElapsed),
        engineUnmountMs: elapsedMs(engineUnmountElapsed),
        swiftUIUnmountMs: elapsedMs(swiftUIUnmountElapsed)
    )
}
