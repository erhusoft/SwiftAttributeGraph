import AppKit
import Foundation
import Observation
import SwiftAttributeGraph
import SwiftUI

/// Tracks how many times each SwiftUI subview `body` executed during a scenario.
public struct BodyRunCounts: Equatable, Sendable {
    public var counterBodyRuns = 0
    public var altBodyRuns = 0
    public var parityBodyRuns = 0
    public var indirectBodyRuns = 0
    public var detailBodyRuns = 0

    public init() {}

    public var totalBodyRuns: Int {
        counterBodyRuns + altBodyRuns + parityBodyRuns + indirectBodyRuns + detailBodyRuns
    }
}

/// Side-by-side comparison of SwiftUI `body` executions between native `@Observable`
/// and `SwiftAttributeGraph` fine-grained attribute boxes.
public struct ParityComparisonReport: Equatable, Sendable {
    public let native: BodyRunCounts
    public let engine: BodyRunCounts
    public let engineParityNodeRuns: Int
    public let engineDetailNodeRuns: Int
}

/// Pure SwiftUI `@Observable` model implementing the same state and derived properties as `EngineBridge`.
@Observable
@MainActor
public final class NativeObservableModel {
    public var counter = 0
    public var altValue = 100
    public var useAlt = false
    public var showDetail = false

    public init() {}

    public var parityText: String {
        counter.isMultiple(of: 2) ? "Par (even)" : "Impar (odd)"
    }

    public var activeIndirectValue: Int {
        useAlt ? altValue : counter
    }

    public var detailText: String? {
        guard showDetail else { return nil }
        return "Detalle vivo: counter=\(counter), indirect=\(activeIndirectValue)"
    }

    public func incrementCounter(by delta: Int) {
        counter += delta
    }

    public func incrementAlt(by delta: Int) {
        altValue += delta
    }

    public func toggleIndirectSource() {
        useAlt.toggle()
    }

    public func setShowDetail(_ show: Bool) {
        showDetail = show
    }
}

/// Observable box that bridges a single `Attribute<Value>` to SwiftUI, publishing only
/// when the attribute's value in `SwiftAttributeGraph` actually changes.
@MainActor
public final class AttributeBox<Value: Equatable>: ObservableObject {
    @Published public private(set) var value: Value
    private let graph: Graph
    private let attribute: Attribute<Value>
    private var observerToken: ObservationToken?

    public init(graph: Graph, attribute: Attribute<Value>) {
        self.graph = graph
        self.attribute = attribute
        self.value = graph.value(of: attribute)
        self.observerToken = graph.observe(attribute.erased) { [weak self] in
            self?.syncIfChanged()
        }
    }

    /// Re-evaluates the attribute if needed and notifies SwiftUI only if its value changed.
    public func syncIfChanged() {
        let nextValue = graph.value(of: attribute)
        if nextValue != value {
            value = nextValue
        }
    }
}

/// Fine-grained `SwiftAttributeGraph` model where each SwiftUI subview observes its own `AttributeBox`.
@MainActor
public final class EngineFineGrainedModel: ObservableObject {
    public let graph = Graph()
    public let counterAttr: Attribute<Int>
    public let altAttr: Attribute<Int>
    public let useAltAttr: Attribute<Bool>
    public let indirectAttr: Attribute<Int>
    public let parityAttr: Attribute<String>

    public let counterBox: AttributeBox<Int>
    public let altBox: AttributeBox<Int>
    public let parityBox: AttributeBox<String>
    public let indirectBox: AttributeBox<Int>

    @Published public var showDetail = false
    @Published public private(set) var detailText: String?

    private final class RunCounter {
        var count = 0
    }

    private var detailSubgraph: Subgraph?
    private var detailAttr: Attribute<String>?
    private var detailObserver: ObservationToken?
    private let parityCounter = RunCounter()

    public var parityNodeRuns: Int { parityCounter.count }
    public private(set) var detailNodeRuns = 0

    public init() {
        let c = graph.makeInput(0)
        let a = graph.makeInput(100)
        let u = graph.makeInput(false)
        let ind = graph.makeIndirect(c)

        self.counterAttr = c
        self.altAttr = a
        self.useAltAttr = u
        self.indirectAttr = ind

        let parityBool = graph.makeMap(c) { $0 % 2 == 0 }
        let pCounter = parityCounter
        self.parityAttr = graph.makeRule { () -> String in
            pCounter.count += 1
            return parityBool.value ? "Par (even)" : "Impar (odd)"
        }

        self.counterBox = AttributeBox(graph: graph, attribute: c)
        self.altBox = AttributeBox(graph: graph, attribute: a)
        self.parityBox = AttributeBox(graph: graph, attribute: parityAttr)
        self.indirectBox = AttributeBox(graph: graph, attribute: ind)
    }

    public func incrementCounter(by delta: Int) {
        let next = graph.value(of: counterAttr) + delta
        graph.setValue(next, for: counterAttr)
        syncAll()
    }

    public func incrementAlt(by delta: Int) {
        let next = graph.value(of: altAttr) + delta
        graph.setValue(next, for: altAttr)
        syncAll()
    }

    public func toggleIndirectSource() {
        let nextUseAlt = !graph.value(of: useAltAttr)
        graph.setValue(nextUseAlt, for: useAltAttr)
        graph.setSource(nextUseAlt ? altAttr : counterAttr, for: indirectAttr)
        syncAll()
    }

    public func setShowDetail(_ show: Bool) {
        showDetail = show
        if show {
            guard detailSubgraph == nil else { return }
            let sub = graph.makeSubgraph()
            let detail = graph.withCurrent(sub) {
                graph.makeRule { [unowned self] () -> String in
                    self.detailNodeRuns += 1
                    return "Detalle vivo: counter=\(self.counterAttr.value), indirect=\(self.indirectAttr.value)"
                }
            }
            detailSubgraph = sub
            detailAttr = detail
            detailText = graph.value(of: detail)
            detailObserver = graph.observe(detail.erased) { [weak self] in
                guard let self, let detail = self.detailAttr else { return }
                let next = self.graph.value(of: detail)
                if next != self.detailText {
                    self.detailText = next
                }
            }
        } else {
            guard let sub = detailSubgraph else { return }
            detailObserver = nil
            detailAttr = nil
            graph.invalidate(sub)
            detailSubgraph = nil
            detailText = nil
        }
    }

    private func syncAll() {
        counterBox.syncIfChanged()
        altBox.syncIfChanged()
        parityBox.syncIfChanged()
        indirectBox.syncIfChanged()
        if let detail = detailAttr {
            let next = graph.value(of: detail)
            if next != detailText {
                detailText = next
            }
        }
    }
}

@MainActor
private final class BodyRunRecorder {
    var counts = BodyRunCounts()
}

private struct NativeCounterSubview: View {
    let model: NativeObservableModel
    let recorder: BodyRunRecorder

    var body: some View {
        recorder.counts.counterBodyRuns += 1
        return Text("counter = \(model.counter)")
    }
}

private struct NativeAltSubview: View {
    let model: NativeObservableModel
    let recorder: BodyRunRecorder

    var body: some View {
        recorder.counts.altBodyRuns += 1
        return Text("alt = \(model.altValue)")
    }
}

private struct NativeParitySubview: View {
    let model: NativeObservableModel
    let recorder: BodyRunRecorder

    var body: some View {
        recorder.counts.parityBodyRuns += 1
        return Text("parity = \(model.parityText)")
    }
}

private struct NativeIndirectSubview: View {
    let model: NativeObservableModel
    let recorder: BodyRunRecorder

    var body: some View {
        recorder.counts.indirectBodyRuns += 1
        return Text("indirect = \(model.activeIndirectValue)")
    }
}

private struct NativeDetailSubview: View {
    let model: NativeObservableModel
    let recorder: BodyRunRecorder

    var body: some View {
        recorder.counts.detailBodyRuns += 1
        return Text(model.detailText ?? "")
    }
}

private struct NativeParityHarnessView: View {
    let model: NativeObservableModel
    let recorder: BodyRunRecorder

    var body: some View {
        VStack {
            NativeCounterSubview(model: model, recorder: recorder)
            NativeAltSubview(model: model, recorder: recorder)
            NativeParitySubview(model: model, recorder: recorder)
            NativeIndirectSubview(model: model, recorder: recorder)
            if model.showDetail {
                NativeDetailSubview(model: model, recorder: recorder)
            }
        }
    }
}

private struct EngineCounterSubview: View {
    @ObservedObject var box: AttributeBox<Int>
    let recorder: BodyRunRecorder

    var body: some View {
        recorder.counts.counterBodyRuns += 1
        return Text("counter = \(box.value)")
    }
}

private struct EngineAltSubview: View {
    @ObservedObject var box: AttributeBox<Int>
    let recorder: BodyRunRecorder

    var body: some View {
        recorder.counts.altBodyRuns += 1
        return Text("alt = \(box.value)")
    }
}

private struct EngineParitySubview: View {
    @ObservedObject var box: AttributeBox<String>
    let recorder: BodyRunRecorder

    var body: some View {
        recorder.counts.parityBodyRuns += 1
        return Text("parity = \(box.value)")
    }
}

private struct EngineIndirectSubview: View {
    @ObservedObject var box: AttributeBox<Int>
    let recorder: BodyRunRecorder

    var body: some View {
        recorder.counts.indirectBodyRuns += 1
        return Text("indirect = \(box.value)")
    }
}

private struct EngineDetailSubview: View {
    @ObservedObject var model: EngineFineGrainedModel
    let recorder: BodyRunRecorder

    var body: some View {
        recorder.counts.detailBodyRuns += 1
        return Text(model.detailText ?? "")
    }
}

private struct EngineParityHarnessView: View {
    @ObservedObject var model: EngineFineGrainedModel
    let recorder: BodyRunRecorder

    var body: some View {
        VStack {
            EngineCounterSubview(box: model.counterBox, recorder: recorder)
            EngineAltSubview(box: model.altBox, recorder: recorder)
            EngineParitySubview(box: model.parityBox, recorder: recorder)
            EngineIndirectSubview(box: model.indirectBox, recorder: recorder)
            if model.showDetail {
                EngineDetailSubview(model: model, recorder: recorder)
            }
        }
    }
}

@MainActor
private func pumpSwiftUI<V: View>(_ hostingView: NSHostingView<V>) {
    hostingView.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.015))
    hostingView.layoutSubtreeIfNeeded()
}

@MainActor
private func makeOffscreenWindow<V: View>(for view: V) -> (NSWindow, NSHostingView<V>) {
    let size = NSSize(width: 400, height: 300)
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentView = hostingView
    pumpSwiftUI(hostingView)
    return (window, hostingView)
}

/// Runs the exact 7-step MiniUIApp interaction sequence on both a native `@Observable` SwiftUI
/// hierarchy and a fine-grained `SwiftAttributeGraph` SwiftUI hierarchy hosted in real `NSHostingView`s.
@MainActor
public func runRealSwiftUIParityComparison() -> ParityComparisonReport {
    NSApplication.shared.setActivationPolicy(.accessory)

    let nativeModel = NativeObservableModel()
    let nativeRecorder = BodyRunRecorder()
    let (nativeWindow, nativeHosting) = makeOffscreenWindow(
        for: NativeParityHarnessView(model: nativeModel, recorder: nativeRecorder)
    )
    defer { nativeWindow.close() }

    nativeModel.incrementCounter(by: 2)
    pumpSwiftUI(nativeHosting)
    nativeModel.incrementCounter(by: 1)
    pumpSwiftUI(nativeHosting)
    nativeModel.incrementAlt(by: 10)
    pumpSwiftUI(nativeHosting)
    nativeModel.toggleIndirectSource()
    pumpSwiftUI(nativeHosting)
    nativeModel.setShowDetail(true)
    pumpSwiftUI(nativeHosting)
    nativeModel.incrementCounter(by: 2)
    pumpSwiftUI(nativeHosting)
    nativeModel.setShowDetail(false)
    pumpSwiftUI(nativeHosting)

    let engineModel = EngineFineGrainedModel()
    let engineRecorder = BodyRunRecorder()
    let (engineWindow, engineHosting) = makeOffscreenWindow(
        for: EngineParityHarnessView(model: engineModel, recorder: engineRecorder)
    )
    defer { engineWindow.close() }

    engineModel.incrementCounter(by: 2)
    pumpSwiftUI(engineHosting)
    engineModel.incrementCounter(by: 1)
    pumpSwiftUI(engineHosting)
    engineModel.incrementAlt(by: 10)
    pumpSwiftUI(engineHosting)
    engineModel.toggleIndirectSource()
    pumpSwiftUI(engineHosting)
    engineModel.setShowDetail(true)
    pumpSwiftUI(engineHosting)
    engineModel.incrementCounter(by: 2)
    pumpSwiftUI(engineHosting)
    engineModel.setShowDetail(false)
    pumpSwiftUI(engineHosting)

    return ParityComparisonReport(
        native: nativeRecorder.counts,
        engine: engineRecorder.counts,
        engineParityNodeRuns: engineModel.parityNodeRuns,
        engineDetailNodeRuns: engineModel.detailNodeRuns
    )
}
