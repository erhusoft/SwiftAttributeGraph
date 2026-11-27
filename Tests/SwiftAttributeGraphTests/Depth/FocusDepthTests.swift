import Testing
@testable import SwiftAttributeGraph

/// A cold chain of key-path projections must not nest updates on the native stack: `makeFocus` is resumable.
@Suite(.serialized) struct FocusDepthTests {
    @Test func aColdChainOfOneHundredThousandProjectionsNeverNests() {
        let depth = 100_000
        let graph = Graph()
        var last = graph.makeInput(0)
        for _ in 0..<depth { last = graph.makeFocus(last, keyPath: \.self) }
        #expect(graph.value(of: last) == 0)
        #expect(graph.maxNestedUpdateDepth == 0)
        #expect(graph.frames.isEmpty)
    }
}
