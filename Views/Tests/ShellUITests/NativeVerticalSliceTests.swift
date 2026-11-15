#if os(macOS)
import AppKit
import SwiftUI
import Testing

@MainActor private final class NativeTrace {
    var selected = 0
    var independent = 0
    var value = ""
    var increment: (() -> Void)?
    var flip: (() -> Void)?
    var setFirst: ((Int) -> Void)?
    var setSecond: ((Int) -> Void)?
}

@MainActor private struct NativeSelectedLabel: SwiftUI.View {
    @SwiftUI.Binding var first: Int
    @SwiftUI.Binding var second: Int
    @SwiftUI.Binding var alternate: Bool
    let trace: NativeTrace
    var body: some SwiftUI.View {
        let value = "\(alternate ? second : first)"
        trace.selected += 1
        trace.value = value
        return SwiftUI.Text(value)
    }
}

@MainActor private struct NativeIndependentLabel: SwiftUI.View {
    let trace: NativeTrace
    var body: some SwiftUI.View {
        trace.independent += 1
        return SwiftUI.Text("fixed")
    }
}

@MainActor private struct NativeSliceScreen: SwiftUI.View {
    @SwiftUI.State private var first = 0
    @SwiftUI.State private var second = 100
    @SwiftUI.State private var alternate = false
    let trace: NativeTrace
    var body: some SwiftUI.View {
        SwiftUI.VStack {
            NativeSelectedLabel(first: $first, second: $second, alternate: $alternate, trace: trace)
            NativeIndependentLabel(trace: trace)
            SwiftUI.Button("Increment") { first += 1 }
            SwiftUI.Button("Switch") { alternate.toggle() }
        }.onAppear {
            trace.increment = { first += 1 }
            trace.flip = { alternate.toggle() }
            trace.setFirst = { first = $0 }
            trace.setSecond = { second = $0 }
        }
    }
}

extension SliceTests {
    /// A synchronous main-thread probe keeps AppKit and its run loop on the same thread.
    @Test @MainActor func nativeBodyTraceRecordsTheBindingInvalidationDifference() throws {
        let trace = NativeTrace()
        let host = NSHostingView(rootView: NativeSliceScreen(trace: trace))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 160),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        defer {
            window.contentView = nil
            window.orderOut(nil)
            trace.increment = nil; trace.flip = nil; trace.setFirst = nil; trace.setSecond = nil
        }
        func settle() {
            let end = Date(timeIntervalSinceNow: 0.10)
            while Date() < end { _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005)) }
        }
        settle()
        let increment = try #require(trace.increment)
        let flip = try #require(trace.flip)
        let setFirst = try #require(trace.setFirst)
        let setSecond = try #require(trace.setSecond)
        #expect(trace.value == "0")
        let fixedBefore = trace.independent
        var deltas: [Int] = []
        var values: [String] = []
        let actions: [() -> Void] = [increment, { setFirst(1) }, flip, increment, { setSecond(101) }, flip]
        for action in actions {
            let before = trace.selected
            action()
            settle()
            deltas.append(trace.selected - before)
            values.append(trace.value)
        }
        #expect(deltas == [1, 0, 1, 1, 1, 1])
        withKnownIssue("SwiftUI reevaluates the previously read inactive Binding; the exact graph dependencies prune it") {
            #expect(deltas == [1, 0, 1, 0, 1, 1])
        }
        #expect(values == ["1", "1", "100", "100", "101", "2"])
        #expect(trace.independent == fixedBefore)
        print("NativeVerticalSlice: body deltas=\(deltas), values=\(values), independent delta=\(trace.independent - fixedBefore)")
    }
}
#endif
