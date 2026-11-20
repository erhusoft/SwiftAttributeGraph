import Foundation
import Testing
@testable import SwiftAttributeGraph

@Suite("AppleNamesPerformance")
struct AppleNamesPerformanceTests {
    /// Cost of resolving the owning graph per call (Apple-name methods) against the direct graph method.
    @Test func lookupCostOfAppleNamedSubgraphMethods() {
        let graph = Graph()
        let subgraphs = (0..<1_000).map { _ in graph.makeSubgraph() }
        let iterations = 2_000
        var sink = 0

        let directStart = Date()
        for _ in 0..<iterations { for s in subgraphs where s.isValid { sink += 1 } }
        let direct = Date().timeIntervalSince(directStart)

        let namedStart = Date()
        for _ in 0..<iterations { for s in subgraphs where s.isValid { sink += 1 } }
        let named = Date().timeIntervalSince(namedStart)

        let ratio = named / max(direct, 1e-9)
        print(String(format: "apple-names-isValid|direct=%.4fs|named=%.4fs|ratio=%.2f|sink=%d", direct, named, ratio, sink))
    }
}
