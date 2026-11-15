#if os(macOS)
import AppKit
import SwiftUI
import Testing

private enum RefreshMode: String, CaseIterable { case fresh, stable, projected }

@MainActor private final class RefreshTrace {
    var source = 0
    var stable: SwiftUI.Binding<Int>?
    var gets = 0
    var parent = 0
    var child = 0
    var text = ""
    var rebuild: (() -> Void)?
    var write: ((Int) -> Void)?
}

@MainActor private struct RefreshChild: SwiftUI.View {
    @SwiftUI.Binding var value: Int
    let read: Bool
    let trace: RefreshTrace
    var body: some SwiftUI.View {
        trace.child += 1
        trace.text = read ? String(value) : "fixed"
        return SwiftUI.Text(trace.text)
    }
}

@MainActor private struct RefreshParent: SwiftUI.View {
    @SwiftUI.State private var tick = 0
    @SwiftUI.State private var source = 0
    let mode: RefreshMode
    let read: Bool
    let trace: RefreshTrace
    var body: some SwiftUI.View {
        trace.parent += 1
        let binding: SwiftUI.Binding<Int>
        switch mode {
        case .fresh: binding = SwiftUI.Binding(get: { trace.gets += 1; return trace.source }, set: { trace.source = $0 })
        case .stable: binding = trace.stable!
        case .projected: binding = $source
        }
        let parentTick = $tick, projectedSource = $source
        return SwiftUI.VStack {
            SwiftUI.Text("tick \(tick)")
            RefreshChild(value: binding, read: read, trace: trace)
        }.onAppear {
            trace.rebuild = { parentTick.wrappedValue += 1 }
            trace.write = { value in
                if mode == .projected { projectedSource.wrappedValue = value }
                else { trace.source = value }
            }
        }
    }
}

extension SliceTests {
    @Test @MainActor func bindingRefreshSeparatesReconstructionFromSourceWrites() throws {
        for mode in RefreshMode.allCases {
            for read in [false, true] {
                let trace = RefreshTrace()
                if mode == .stable {
                    trace.stable = SwiftUI.Binding(get: { trace.gets += 1; return trace.source }, set: { trace.source = $0 })
                }
                let host = NSHostingView(rootView: RefreshParent(mode: mode, read: read, trace: trace))
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
                                      styleMask: [.titled], backing: .buffered, defer: false)
                window.contentView = host
                window.orderFrontRegardless()
                defer { window.contentView = nil; window.orderOut(nil); trace.rebuild = nil; trace.write = nil; trace.stable = nil }
                func settle() {
                    let end = Date(timeIntervalSinceNow: 0.10)
                    while Date() < end { _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005)) }
                }
                settle()
                let rebuild = try #require(trace.rebuild), write = try #require(trace.write)
                var parents: [Int] = [], children: [Int] = [], getters: [Int] = [], values: [String] = []
                let actions: [() -> Void] = [rebuild, { write(1) }, rebuild, rebuild, { write(1) }, { write(2) }, rebuild]
                for action in actions {
                    let before = (trace.parent, trace.child, trace.gets)
                    action()
                    settle()
                    parents.append(trace.parent - before.0)
                    children.append(trace.child - before.1)
                    getters.append(trace.gets - before.2)
                    values.append(trace.text)
                }
                #expect(parents == [1, 0, 1, 1, 0, 0, 1])
                #expect(children[4] == 0)
                if mode != .projected { #expect(children[1] == 0 && children[5] == 0) }
                if mode == .projected { #expect(children[1] == (read ? 1 : 0) && children[5] == (read ? 1 : 0)) }
                // Frozen after discovery with the stable binding held outside the view's stored properties.
                let expectedChildren: [Int]
                let expectedGetters: [Int]
                let expectedValues: [String]
                switch mode {
                case .fresh:
                    expectedChildren = [1, 0, 1, 1, 0, 0, 1]
                    expectedGetters = [2, 0, 2, 2, 0, 0, 2]
                    expectedValues = ["0", "0", "1", "1", "1", "1", "2"]
                case .stable:
                    expectedChildren = [0, 0, 0, 0, 0, 0, 0]
                    expectedGetters = [0, 0, 0, 0, 0, 0, 0]
                    expectedValues = Array(repeating: "0", count: 7)
                case .projected:
                    expectedChildren = read ? [0, 1, 1, 0, 0, 1, 1] : [0, 0, 1, 0, 0, 0, 1]
                    expectedGetters = [0, 0, 0, 0, 0, 0, 0]
                    expectedValues = ["0", "1", "1", "1", "1", "2", "2"]
                }
                #expect(children == expectedChildren)
                #expect(getters == expectedGetters)
                #expect(values == (read ? expectedValues : Array(repeating: "fixed", count: 7)))
                print("BindingRefresh \(mode.rawValue) read=\(read): parent=\(parents) child=\(children) get=\(getters) values=\(values)")
            }
        }
    }
}
#endif
