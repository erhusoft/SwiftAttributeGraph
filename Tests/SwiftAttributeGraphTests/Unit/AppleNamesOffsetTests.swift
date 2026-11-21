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

    /// Apple's `AGAttribute.create(self:offset:)`: without an explicit size, any change to the source value reaches
    /// the reader, including bytes before `offset`. Measured natively on 16- and 24-byte values at offsets 0, 8 and 16
    /// (`offset-tree` probe in NativeProbe): changing bytes outside [offset, end) still re-runs the reader, so the
    /// default size is the whole value, not the bytes that remain after `offset`.
    @Test func createOffsetWithoutSizeReachesTheReaderOnAnyChange() {
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

        // Mutating 'a' (before offset 16) also re-runs the reader, as measured natively.
        graph.setValue(Quad(a: 99, b: 2, c: 3, d: 4), for: source)
        #expect(graph.value(of: rule) == 3)
        #expect(runs == 2)

        graph.setValue(Quad(a: 99, b: 2, c: 42, d: 4), for: source)
        #expect(graph.value(of: rule) == 42)
        #expect(runs == 3)
    }
}
