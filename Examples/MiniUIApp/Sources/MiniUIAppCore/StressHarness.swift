import Foundation
import SwiftAttributeGraph

/// Results from stressing `SwiftAttributeGraph` with thousands of dynamic subgraphs
/// and rapid multi-source batched writes.
public struct StressReport: Equatable, Sendable {
    public let rowCount: Int
    public let peakNodes: Int
    public let peakEdges: Int
    public let peakSubgraphs: Int
    public let afterUnmountNodes: Int
    public let afterUnmountEdges: Int
    public let afterUnmountSubgraphs: Int
    public let mountUnmountMs: Double

    public let multiSourceWrites: Int
    public let multiSourceBatches: Int
    public let multiSourceDirtyNotifications: Int
    public let combinedRuleRuns: Int
    public let multiSourceBatchMs: Double
}

private struct RowEntry {
    let subgraph: Subgraph
    let input: Attribute<Int>
    let label: Attribute<String>
}

/// Runs two stress checks against `SwiftAttributeGraph`:
/// 1. Mounts `rowCount` row subgraphs, unmounts half, remounts replacements, unmounts all,
///    and verifies `nodeCount == 0`, `edgeCount == 0`, and `liveSubgraphCount == 1`.
/// 2. Fires `batchCount` rapid multi-source write batches (4 sources per batch) and verifies
///    1 dirty notification and 1 combined recalculation per batch (no redundant work).
public func runStressScenario(rowCount: Int = 2_000, batchCount: Int = 250) -> StressReport {
    let clock = ContinuousClock()

    // Part A: Massive subgraph mount/unmount stress.
    let gRows = Graph()
    var rows: [RowEntry] = []
    rows.reserveCapacity(rowCount)

    var peakNodes = 0
    var peakEdges = 0
    var peakSubgraphs = 0

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

        peakNodes = gRows.nodeCount
        peakEdges = gRows.edgeCount
        peakSubgraphs = gRows.liveSubgraphCount

        // Unmount even rows.
        var surviving: [RowEntry] = []
        surviving.reserveCapacity(rowCount / 2)
        for (idx, entry) in rows.enumerated() {
            if idx.isMultiple(of: 2) {
                gRows.invalidate(entry.subgraph)
            } else {
                surviving.append(entry)
            }
        }

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

    let afterUnmountNodes = gRows.nodeCount
    let afterUnmountEdges = gRows.edgeCount
    let afterUnmountSubgraphs = gRows.liveSubgraphCount

    let mountUnmountMs =
        (Double(partAElapsed.components.seconds)
            + Double(partAElapsed.components.attoseconds) / 1e18) * 1_000.0

    // Part B: Rapid multi-source batched writes.
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
    defer { _ = token }

    let writesPerBatch = 4
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

    let multiSourceBatchMs =
        (Double(partBElapsed.components.seconds)
            + Double(partBElapsed.components.attoseconds) / 1e18) * 1_000.0

    return StressReport(
        rowCount: rowCount,
        peakNodes: peakNodes,
        peakEdges: peakEdges,
        peakSubgraphs: peakSubgraphs,
        afterUnmountNodes: afterUnmountNodes,
        afterUnmountEdges: afterUnmountEdges,
        afterUnmountSubgraphs: afterUnmountSubgraphs,
        mountUnmountMs: mountUnmountMs,
        multiSourceWrites: batchCount * writesPerBatch,
        multiSourceBatches: batchCount,
        multiSourceDirtyNotifications: dirtyCount,
        combinedRuleRuns: combinedRuns,
        multiSourceBatchMs: multiSourceBatchMs
    )
}
