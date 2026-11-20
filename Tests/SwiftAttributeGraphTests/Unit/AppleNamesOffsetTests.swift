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
}
