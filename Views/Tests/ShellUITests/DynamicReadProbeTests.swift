#if os(macOS)
import AppKit
import SwiftUI
import Testing
import SwiftAttributeGraph

private enum ReadMode: String, CaseIterable {
    case direct, projected, closure, structural, unread, both
}

@MainActor private final class ReadTrace {
    var counts: [String: Int] = [:]
    var value = ""
    var first: ((Int) -> Void)?
    var second: ((Int) -> Void)?
    var flip: (() -> Void)?
    var remount: (() -> Void)?
    func hit(_ name: String) { counts[name, default: 0] += 1 }
    func record(_ value: Int) -> String {
        hit("selected")
        self.value = String(value)
        return self.value
    }
    func clearActions() { first = nil; second = nil; flip = nil; remount = nil }
}

@MainActor private struct ReadLeaf: SwiftUI.View {
    @SwiftUI.Binding var first: Int
    @SwiftUI.Binding var second: Int
    @SwiftUI.Binding var alternate: Bool
    let mode: ReadMode
    let trace: ReadTrace
    var body: some SwiftUI.View {
        if mode == .both { let _ = first; let _ = second }
        return SwiftUI.Text(trace.record(mode == .unread ? second : (alternate ? second : first)))
    }
}

@MainActor private struct FirstReadBranch: SwiftUI.View {
    @SwiftUI.Binding var value: Int
    let trace: ReadTrace
    var body: some SwiftUI.View {
        trace.hit("firstBranch")
        return SwiftUI.Text(trace.record(value))
    }
}

@MainActor private struct SecondReadBranch: SwiftUI.View {
    @SwiftUI.Binding var value: Int
    let trace: ReadTrace
    var body: some SwiftUI.View {
        trace.hit("secondBranch")
        return SwiftUI.Text(trace.record(value))
    }
}

@MainActor private struct ReadRoot: SwiftUI.View {
    @SwiftUI.State private var first = 0
    @SwiftUI.State private var second = 100
    @SwiftUI.State private var alternate = false
    @SwiftUI.State private var generation = 0
    let mode: ReadMode
    let trace: ReadTrace
    init(mode: ReadMode, trace: ReadTrace, startAlternate: Bool) {
        self.mode = mode
        self.trace = trace
        _alternate = SwiftUI.State(wrappedValue: startAlternate)
    }
    var body: some SwiftUI.View {
        trace.hit("root")
        return SwiftUI.Group {
            switch mode {
            case .direct:
                SwiftUI.Text(trace.record(alternate ? second : first))
            case .closure:
                ReadLeaf(first: SwiftUI.Binding(get: { first }, set: { first = $0 }),
                         second: SwiftUI.Binding(get: { second }, set: { second = $0 }),
                         alternate: SwiftUI.Binding(get: { alternate }, set: { alternate = $0 }), mode: mode, trace: trace)
            case .structural:
                if alternate { SecondReadBranch(value: $second, trace: trace) }
                else { FirstReadBranch(value: $first, trace: trace) }
            default:
                ReadLeaf(first: $first, second: $second, alternate: $alternate, mode: mode, trace: trace)
            }
        }.id(generation).onAppear {
            trace.first = { first = $0 }
            trace.second = { second = $0 }
            trace.flip = { alternate.toggle() }
            trace.remount = { generation += 1 }
        }
    }
}

extension SliceTests {
    @Test @MainActor func dynamicReadNativeMatrix() throws { try runNativeReadMatrix(reverse: false) }

    /// Held-out sequence: initially select the other source, reverse all data writes, then repeat the same lifecycle.
    @Test @MainActor func dynamicReadReversedNativePredictions() throws { try runNativeReadMatrix(reverse: true) }

    @MainActor private func runNativeReadMatrix(reverse: Bool) throws {
        for mode in ReadMode.allCases {
            let trace = ReadTrace()
            let host = NSHostingView(rootView: ReadRoot(mode: mode, trace: trace, startAlternate: reverse))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            window.orderFrontRegardless()
            defer { window.contentView = nil; window.orderOut(nil); trace.clearActions() }
            func settle() {
                let end = Date(timeIntervalSinceNow: 0.10)
                while Date() < end { _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005)) }
            }
            settle()
            let first = try #require(trace.first), second = try #require(trace.second)
            let flip = try #require(trace.flip), remount = try #require(trace.remount)
            #expect(trace.value == (mode == .unread || reverse ? "100" : "0"))
            let actions: [() -> Void] = reverse
                ? [{ second(101) }, { second(101) }, flip, { second(102) }, remount,
                   { second(103) }, { first(1) }, flip, { first(2) }, { second(104) }]
                : [{ first(1) }, { first(1) }, flip, { first(2) }, remount,
                   { first(3) }, { second(101) }, flip, { second(102) }, { first(4) }]
            var selected: [Int] = [], roots: [Int] = [], values: [String] = []
            for action in actions {
                let previous = trace.counts
                action()
                settle()
                selected.append(trace.counts["selected", default: 0] - previous["selected", default: 0])
                roots.append(trace.counts["root", default: 0] - previous["root", default: 0])
                values.append(trace.value)
            }
            let expected: [String]
            if mode == .unread {
                expected = reverse
                    ? ["101", "101", "101", "102", "102", "103", "103", "103", "103", "104"]
                    : ["100", "100", "100", "100", "100", "100", "101", "101", "102", "102"]
            } else {
                expected = reverse
                    ? ["101", "101", "0", "0", "0", "0", "1", "103", "103", "104"]
                    : ["1", "1", "100", "100", "100", "100", "101", "3", "3", "4"]
            }
            // Frozen after discovery, before running the reversed sequence or independent verification processes.
            let expectedSelected: [Int]
            let expectedRoots: [Int]
            switch mode {
            case .direct, .closure:
                expectedSelected = [1, 0, 1, 1, 1, 1, 1, 1, 1, 1]
                expectedRoots = expectedSelected
            case .both:
                expectedSelected = [1, 0, 1, 1, 1, 1, 1, 1, 1, 1]
                expectedRoots = [0, 0, 0, 0, 1, 0, 0, 0, 0, 0]
            case .projected:
                expectedSelected = [1, 0, 1, 1, 1, 0, 1, 1, 1, 1]
                expectedRoots = [0, 0, 0, 0, 1, 0, 0, 0, 0, 0]
            case .structural:
                expectedSelected = [1, 0, 1, 0, 1, 0, 1, 1, 0, 1]
                expectedRoots = [0, 0, 1, 0, 1, 0, 0, 1, 0, 0]
            case .unread:
                expectedSelected = reverse ? [1, 0, 0, 1, 1, 1, 0, 0, 0, 1] : [0, 0, 0, 0, 1, 0, 1, 0, 1, 0]
                expectedRoots = [0, 0, 0, 0, 1, 0, 0, 0, 0, 0]
            }
            #expect(values == expected)
            #expect(selected == expectedSelected)
            #expect(roots == expectedRoots)
            print("DynamicReads \(mode.rawValue) reverse=\(reverse): selected=\(selected) root=\(roots) values=\(values)")
        }
    }

    @Test func dynamicReadGraphKeepsExactDependenciesAcrossSelectionAndIdentity() {
        for readBoth in [false, true] {
            let graph = Graph()
            let screen = graph.makeSubgraph()
            let first = graph.withCurrent(screen) { graph.makeInput(0) }
            let second = graph.withCurrent(screen) { graph.makeInput(100) }
            let alternate = graph.withCurrent(screen) { graph.makeInput(false) }
            var calls = 0
            func mount() -> (Subgraph, Attribute<Int>) {
                let scope = graph.makeSubgraph(parent: screen)
                let body = graph.withCurrent(scope) {
                    graph.makeRule {
                        calls += 1
                        if readBoth { _ = first.value; _ = second.value }
                        return alternate.value ? second.value : first.value
                    }
                }
                return (scope, body)
            }
            var (scope, body) = mount()
            #expect(graph.value(of: body) == 0)
            var deltas: [Int] = [], values: [Int] = []
            for step in 0..<10 {
                let before = calls
                switch step {
                case 0, 1: graph.setValue(1, for: first)
                case 2, 7: graph.setValue(!graph.value(of: alternate), for: alternate)
                case 3: graph.setValue(2, for: first)
                case 4:
                    let old = scope
                    (scope, body) = mount()
                    graph.invalidate(old)
                case 5: graph.setValue(3, for: first)
                case 6: graph.setValue(101, for: second)
                case 8: graph.setValue(102, for: second)
                default: graph.setValue(4, for: first)
                }
                values.append(graph.value(of: body))
                deltas.append(calls - before)
                #expect(graph.inputCount(of: body.id) == (readBoth ? 3 : 2))
                #expect(graph.nodeCount == 4)
            }
            #expect(values == [1, 1, 100, 100, 100, 100, 101, 3, 3, 4])
            #expect(deltas == (readBoth ? [1, 0, 1, 1, 1, 1, 1, 1, 1, 1] : [1, 0, 1, 0, 1, 0, 1, 1, 0, 1]))
            graph.invalidate(screen)
            #expect(graph.nodeCount == 0 && graph.edgeCount == 0 && graph.liveSubgraphCount == 1)
            print("DynamicReads graph readBoth=\(readBoth): selected=\(deltas) values=\(values)")
        }
    }
}
#endif
