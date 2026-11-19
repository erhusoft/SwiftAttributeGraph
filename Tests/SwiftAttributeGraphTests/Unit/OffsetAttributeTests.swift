import Testing
@testable import SwiftAttributeGraph

@Suite("OffsetAttributeTests")
struct OffsetAttributeTests {
    struct PaddedStruct: Equatable {
        var flag: Bool
        var count: Int64
        var tag: UInt8
    }

    enum Mode: Equatable {
        case idle
        case active(Int)
    }

    @Test func projectedSliceCutsOffChangesOutsideProjectedField() {
        let graph = Graph()
        let source = graph.makeInput(PaddedStruct(flag: true, count: 10, tag: 1))
        let projected = graph.makeProjectedAttribute(of: source) { $0.count }

        var consumerRuns = 0
        let consumer = graph.makeRule {
            consumerRuns += 1
            return projected.value * 2
        }

        #expect(graph.value(of: consumer) == 20)
        #expect(consumerRuns == 1)

        // Changes to `flag` / `tag` (and any padding) do not re-run `consumer`.
        graph.setValue(PaddedStruct(flag: false, count: 10, tag: 9), for: source)
        #expect(graph.value(of: consumer) == 20)
        #expect(consumerRuns == 1)

        // Change to `count` propagates.
        graph.setValue(PaddedStruct(flag: false, count: 15, tag: 9), for: source)
        #expect(graph.value(of: consumer) == 30)
        #expect(consumerRuns == 2)
    }

    @Test func projectedEnumAndBoolWithCustomComparator() {
        let graph = Graph()
        let source = graph.makeInput((flag: true, mode: Mode.active(1)))
        let projected = graph.makeProjectedAttribute(
            of: source,
            project: { $0.mode },
            isEqual: { lhs, rhs in
                switch (lhs, rhs) {
                case (.idle, .idle): true
                case (.active, .active): true
                default: false
                }
            }
        )

        var runs = 0
        let consumer = graph.makeRule {
            runs += 1
            return projected.value
        }

        #expect(graph.value(of: consumer) == .active(1))
        #expect(runs == 1)

        // Same case `.active(2)` treated as equal by custom comparator -> cuts off.
        graph.setValue((flag: false, mode: .active(2)), for: source)
        #expect(graph.value(of: consumer) == .active(1))
        #expect(runs == 1)

        // Different case `.idle` -> propagates.
        graph.setValue((flag: false, mode: .idle), for: source)
        #expect(graph.value(of: consumer) == .idle)
        #expect(runs == 2)
    }

    @Test func focusHandlesNonTrivialTypesSafely() {
        struct NonTrivial: Equatable {
            var title: String
            var count: Int
        }
        let graph = Graph()
        let source = graph.makeInput(NonTrivial(title: "a", count: 1))
        let titleAttr = graph.makeFocus(source, keyPath: \.title)
        #expect(graph.value(of: titleAttr) == "a")
        graph.setValue(NonTrivial(title: "a", count: 2), for: source)
        #expect(graph.value(of: titleAttr) == "a")
    }
}
