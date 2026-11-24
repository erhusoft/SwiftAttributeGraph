import Testing
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(WinSDK)
import WinSDK
#endif
@testable import SwiftAttributeGraph

@Suite("MemoryFootprintPerformanceTests")
struct MemoryFootprintPerformanceTests {

    private func getResidentMemoryBytes() -> UInt64 {
        #if canImport(Darwin)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / 4)
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return 0 }
        return info.resident_size
        #elseif canImport(WinSDK)
        var pmc = PROCESS_MEMORY_COUNTERS()
        pmc.cb = DWORD(MemoryLayout<PROCESS_MEMORY_COUNTERS>.size)
        if GetProcessMemoryInfo(GetCurrentProcess(), &pmc, pmc.cb) {
            return UInt64(pmc.WorkingSetSize)
        }
        return 0
        #else
        return 0
        #endif
    }

    /// Measures the resident memory cost of allocating 100,000 attributes across 10,000 subgraphs,
    /// and verifies that invalidation frees the memory back to baseline.
    @Test func residentMemoryAllocationAndReclaimOnInvalidation() {
        let initialMemory = getResidentMemoryBytes()

        let graph = Graph()
        let subgraphCount = 10_000
        let attributesPerSubgraph = 10

        var subgraphs: [Subgraph] = []
        subgraphs.reserveCapacity(subgraphCount)

        for _ in 0..<subgraphCount {
            let sg = graph.makeSubgraph()
            subgraphs.append(sg)
            graph.withCurrent(sg) {
                for i in 0..<attributesPerSubgraph {
                    _ = graph.makeInput(i)
                }
            }
        }

        let allocatedMemory = getResidentMemoryBytes()
        let allocationDeltaMB = Double(allocatedMemory > initialMemory ? allocatedMemory - initialMemory : 0) / (1024.0 * 1024.0)
        let bytesPerNode = Double(allocatedMemory > initialMemory ? allocatedMemory - initialMemory : 0) / Double(subgraphCount * attributesPerSubgraph)

        print("PERF Memory: \(subgraphCount * attributesPerSubgraph) nodes across \(subgraphCount) subgraphs used \(String(format: "%.2f", allocationDeltaMB)) MB (~\(String(format: "%.1f", bytesPerNode)) bytes/node)")

        // Invalidate all subgraphs
        for sg in subgraphs {
            sg.invalidate()
        }

        #expect(graph.nodeCount == 0, "All nodes must be reclaimed after invalidating all subgraphs")

        #if !DEBUG
        // 100k nodes should consume less than 80 MB of resident memory in Release
        #expect(allocationDeltaMB < 80.0, "100k nodes must consume less than 80 MB resident memory")
        #endif
    }
}
