import Testing
@testable import SwiftAttributeGraph

@Suite("AppleNamesOffsetTests")
struct AppleNamesOffsetTests {
    struct Pair: BitwiseCopyable, Equatable { var a: Int; var b: Int }

    /// Apple's `AGAttribute.create(self:offset:size:)`: an offset edge that only sees bytes in its range
    /// [O, AGAttribute.h; offset-range-inside-outside oracle scenario].
    @Test func createOffsetSeesOnlyItsByteRange() {
        let graph = Graph()
        let source = graph.makeInput(Pair(a: 1, b: 2))
        let fieldA = source.create(offset: 0, size: 8)
        var runs = 0
        let rule = graph.makeRule { runs += 1; return graph.value(of: fieldA).a * 10 }

        #expect(graph.value(of: rule) == 10)
        #expect(runs == 1)

        graph.setValue(Pair(a: 1, b: 99), for: source)
        #expect(graph.value(of: rule) == 10)
        #expect(runs == 1)

        graph.setValue(Pair(a: 5, b: 99), for: source)
        #expect(graph.value(of: rule) == 50)
        #expect(runs == 2)
    }

    /// Apple's `AGAttribute.create(self:offset:)`: offset without explicit size defaults to remaining bytes
    /// [O, AGAttribute.h, AGGraphCreateOffsetAttribute].
    @Test func createOffsetWithoutSizeDefaultsToRemainingBytes() {
        let graph = Graph()
        struct Quad: BitwiseCopyable, Equatable { var a: Int; var b: Int; var c: Int; var d: Int }
        let source = graph.makeInput(Quad(a: 1, b: 2, c: 3, d: 4))
        let off16 = source.create(offset: 16)
        var runs = 0
        let rule = graph.makeRule {
            runs += 1
            return graph.value(of: off16).c
        }

        #expect(graph.value(of: rule) == 3)
        #expect(runs == 1)

        // Mutating 'a' or 'b' (offsets 0..<16) should NOT trigger rule re-evaluation
        graph.setValue(Quad(a: 99, b: 99, c: 3, d: 4), for: source)
        #expect(graph.value(of: rule) == 3)
        #expect(runs == 1)

        // Mutating 'c' or 'd' (offsets 16..<32) SHOULD trigger rule re-evaluation
        graph.setValue(Quad(a: 99, b: 99, c: 42, d: 4), for: source)
        #expect(graph.value(of: rule) == 42)
        #expect(runs == 2)
    }
}

