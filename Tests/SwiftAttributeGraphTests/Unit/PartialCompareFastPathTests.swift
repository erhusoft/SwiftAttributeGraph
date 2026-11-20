import Testing
@testable import SwiftAttributeGraph

/// Writes and dirty propagation skip the partial-compare bookkeeping while the graph has no typed edge comparator and
/// no offset attribute. These tests pin down that the skip turns off as soon as one appears.
@Suite struct PartialCompareFastPathTests {
    private struct Pair: Equatable {
        var a: Int
        var b: Int
    }

    @Test func aComparatorRegisteredAfterPlainWritesIsHonoredByTheNextWrite() {
        let graph = Graph()
        let source = graph.makeInput(Pair(a: 1, b: 1))
        var plainRuns = 0
        let plain = graph.makeRule { () -> Int in plainRuns += 1; return graph.value(of: source).a }
        #expect(graph.value(of: plain) == 1)
        #expect(!graph.hasPartialEdgeComparison)

        graph.setValue(Pair(a: 2, b: 1), for: source)
        #expect(graph.value(of: plain) == 2)
        #expect(plainRuns == 2)

        var partialRuns = 0
        let partial = graph.makeRule { () -> Int in
            partialRuns += 1
            return graph.read(source, project: { $0.a })
        }
        #expect(graph.value(of: partial) == 2)
        #expect(graph.hasPartialEdgeComparison)

        // Only `b` changes: the partial reader is cut, the plain reader still runs.
        graph.setValue(Pair(a: 2, b: 5), for: source)
        #expect(graph.value(of: partial) == 2)
        #expect(graph.value(of: plain) == 2)
        #expect(partialRuns == 1)
        #expect(plainRuns == 3)

        // `a` changes: both run.
        graph.setValue(Pair(a: 7, b: 5), for: source)
        #expect(graph.value(of: partial) == 7)
        #expect(partialRuns == 2)
    }

    @Test func plainPropagationMarksEveryReaderDirtyAndNotifiesInOrder() {
        let graph = Graph()
        let source = graph.makeInput(0)
        let readers = (0..<4).map { i in graph.makeRule { graph.value(of: source) + i } }
        for reader in readers { _ = graph.value(of: reader) }
        var seen: [Int] = []
        var tokens: [Any] = []
        for (i, reader) in readers.enumerated() {
            tokens.append(graph.observe(reader.erased) { seen.append(i) })
        }

        graph.setValue(1, for: source)

        #expect(readers.allSatisfy { graph.isDirty($0.id) })
        // The dirty stack is last in, first out over the output list, as before the fast path.
        #expect(seen == [3, 2, 1, 0])
        _ = tokens
    }
}
