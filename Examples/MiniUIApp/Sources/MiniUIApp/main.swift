import AppKit
import SwiftAttributeGraph
import SwiftUI

/// Snapshot produced lazily by the `SwiftAttributeGraph` engine and rendered by the window.
struct UISnapshot: Equatable {
    var counter: Int
    var altValue: Int
    var parityText: String
    var activeIndirectValue: Int
    var detailText: String?
    var parityRuns: Int
    var detailRuns: Int
    var summaryRuns: Int
    var nodeCount: Int
    var edgeCount: Int
    var subgraphCount: Int
    var recalculationCount: Int
}

/// Bridges a single-threaded `Graph` to a macOS SwiftUI window via `graph.observe(_:onDirty:)`.
@MainActor
final class EngineBridge: ObservableObject {
    let graph = Graph()
    let counterAttr: Attribute<Int>
    let altAttr: Attribute<Int>
    let useAltAttr: Attribute<Bool>
    let indirectAttr: Attribute<Int>

    private var detailSubgraph: Subgraph?
    private var detailWeak = WeakAttribute<String>()
    private var parityRuns = 0
    private var detailRuns = 0
    private var summaryRuns = 0

    private final class RunCounter { var count = 0 }

    private let parityLabelAttr: Attribute<String>
    private let parityCounter = RunCounter()
    private let detailCounter = RunCounter()
    private let summaryCounter = RunCounter()
    private var rootRuleHandle: Attribute<UISnapshot>?
    private var observationToken: ObservationToken?
    private var refreshScheduled = false

    @Published private(set) var snapshot: UISnapshot
    @Published private(set) var events: [String] = []
    @Published var showDetail = false

    init() {
        let counter = graph.makeInput(0)
        let alt = graph.makeInput(100)
        let useAlt = graph.makeInput(false)
        let indirect = graph.makeIndirect(counter)

        self.counterAttr = counter
        self.altAttr = alt
        self.useAltAttr = useAlt
        self.indirectAttr = indirect

        let parity = graph.makeMap(counter) { $0 % 2 == 0 }
        let pCounter = parityCounter
        let parityLabel = graph.makeRule { () -> String in
            pCounter.count += 1
            return parity.value ? "Par (even)" : "Impar (odd)"
        }
        self.parityLabelAttr = parityLabel

        self.snapshot = UISnapshot(
            counter: 0, altValue: 100, parityText: "", activeIndirectValue: 0,
            detailText: nil, parityRuns: 0, detailRuns: 0, summaryRuns: 0,
            nodeCount: 0, edgeCount: 0, subgraphCount: 0, recalculationCount: 0
        )

        let rootRule = makeRootRule()
        self.rootRuleHandle = rootRule
        self.pullSnapshot(rootRule)
        self.observationToken = graph.observe(rootRule.erased) { [weak self] in
            self?.scheduleRefresh(for: rootRule)
        }
        log("Motor iniciado (nodeCount=\(graph.nodeCount), subgraphs=\(graph.liveSubgraphCount))")
    }

    private func makeRootRule() -> Attribute<UISnapshot> {
        let counter = counterAttr
        let alt = altAttr
        let parityLabel = parityLabelAttr
        let indirect = indirectAttr
        return graph.makeRule { [unowned self] () -> UISnapshot in
            summaryCounter.count += 1
            let c = counter.value
            let a = alt.value
            let p = parityLabel.value
            let indVal = indirect.value
            let detail = graph.value(of: detailWeak)
            return UISnapshot(
                counter: c,
                altValue: a,
                parityText: p,
                activeIndirectValue: indVal,
                detailText: detail,
                parityRuns: parityCounter.count,
                detailRuns: detailCounter.count,
                summaryRuns: summaryCounter.count,
                nodeCount: graph.nodeCount,
                edgeCount: graph.edgeCount,
                subgraphCount: graph.liveSubgraphCount,
                recalculationCount: graph.recalculationCount
            )
        }
    }

    private func scheduleRefresh(for rule: Attribute<UISnapshot>) {
        rootRuleHandle = rule
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            self.pullSnapshot(rule)
        }
    }

    private func pullSnapshot(_ rule: Attribute<UISnapshot>) {
        var next = graph.value(of: rule)
        // Refresh counters after rule finishes so `nodeCount` / `recalculationCount` are exact.
        next.nodeCount = graph.nodeCount
        next.edgeCount = graph.edgeCount
        next.subgraphCount = graph.liveSubgraphCount
        next.recalculationCount = graph.recalculationCount
        snapshot = next
    }

    func incrementCounter(by delta: Int) {
        let next = graph.value(of: counterAttr) + delta
        graph.setValue(next, for: counterAttr)
        log("setValue(\(next), for: counter)")
    }

    func incrementAlt(by delta: Int) {
        let next = graph.value(of: altAttr) + delta
        graph.setValue(next, for: altAttr)
        log("setValue(\(next), for: alt)")
    }

    func toggleIndirectSource() {
        let nextUseAlt = !graph.value(of: useAltAttr)
        graph.setValue(nextUseAlt, for: useAltAttr)
        let target = nextUseAlt ? altAttr : counterAttr
        graph.setSource(target, for: indirectAttr)
        log("setSource(\(nextUseAlt ? "alt" : "counter"), for: indirect)")
    }

    func setShowDetail(_ show: Bool) {
        showDetail = show
        if show {
            guard detailSubgraph == nil else { return }
            let sub = graph.makeSubgraph()
            let detail = graph.withCurrent(sub) {
                graph.makeRule { [unowned self] () -> String in
                    detailCounter.count += 1
                    return "Detalle vivo: counter=\(counterAttr.value), indirect=\(indirectAttr.value)"
                }
            }
            detailSubgraph = sub
            detailWeak = WeakAttribute(detail)
            // Trigger root refresh cleanly by bumping a batch/read.
            if let rule = rootRuleHandle {
                graph.invalidateValue(of: rule)
            }
            log("makeSubgraph() + detail rule (nodeCount=\(graph.nodeCount), subgraphs=\(graph.liveSubgraphCount))")
        } else {
            guard let sub = detailSubgraph else { return }
            graph.invalidate(sub)
            detailSubgraph = nil
            detailWeak = WeakAttribute()
            if let rule = rootRuleHandle {
                graph.invalidateValue(of: rule)
            }
            log("invalidate(detailSubgraph) (nodeCount=\(graph.nodeCount), subgraphs=\(graph.liveSubgraphCount))")
        }
    }

    private func log(_ message: String) {
        events.insert(message, at: 0)
        if events.count > 12 { events.removeLast() }
    }
}

struct ContentView: View {
    @ObservedObject var bridge: EngineBridge

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SwiftAttributeGraph — Mini UI Demo")
                .font(.title2.bold())

            HStack(spacing: 12) {
                GroupBox("Entradas") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("counter = \(bridge.snapshot.counter)")
                                .monospacedDigit()
                            Spacer()
                            Button("+2 (misma paridad)") { bridge.incrementCounter(by: 2) }
                            Button("+1 (cambia paridad)") { bridge.incrementCounter(by: 1) }
                        }
                        HStack {
                            Text("alt = \(bridge.snapshot.altValue)")
                                .monospacedDigit()
                            Spacer()
                            Button("alt +10") { bridge.incrementAlt(by: 10) }
                        }
                        HStack {
                            Button("Redirigir IndirectAttribute (setSource)") {
                                bridge.toggleIndirectSource()
                            }
                            Toggle("Montar Subgraph detalle", isOn: Binding(
                                get: { bridge.showDetail },
                                set: { bridge.setShowDetail($0) }
                            ))
                        }
                    }
                    .padding(6)
                }
            }

            GroupBox("Salidas calculadas por el grafo") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Paridad (Map + corte): \(bridge.snapshot.parityText)  [runs: \(bridge.snapshot.parityRuns)]")
                    Text("IndirectAttribute.value: \(bridge.snapshot.activeIndirectValue)")
                    if let detail = bridge.snapshot.detailText {
                        Text(detail)
                            .foregroundColor(.green)
                    } else {
                        Text("WeakAttribute detalle: nil (Subgraph desmontado)")
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            GroupBox("Métricas del motor en vivo") {
                HStack(spacing: 20) {
                    Label("nodeCount: \(bridge.snapshot.nodeCount)", systemImage: "circle.grid.3x3")
                    Label("edgeCount: \(bridge.snapshot.edgeCount)", systemImage: "arrow.triangle.branch")
                    Label("subgraphs: \(bridge.snapshot.subgraphCount)", systemImage: "square.stack.3d.up")
                    Label("recalculations: \(bridge.snapshot.recalculationCount)", systemImage: "bolt")
                }
                .monospacedDigit()
                .padding(6)
            }

            GroupBox("Últimos eventos") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(bridge.events.enumerated()), id: \.offset) { _, line in
                            Text("• \(line)")
                                .font(.caption.monospaced())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 110)
            }
        }
        .padding(16)
        .frame(minWidth: 640, minHeight: 460)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    let bridge = EngineBridge()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hosting = NSHostingView(rootView: ContentView(bridge: bridge))
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.center()
        win.title = "SwiftAttributeGraph — Mini UI"
        win.contentView = hosting
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let app = NSApplication.shared
if let snapIdx = CommandLine.arguments.firstIndex(of: "--snapshot"),
   snapIdx + 1 < CommandLine.arguments.count {
    let outputPath = CommandLine.arguments[snapIdx + 1]
    @MainActor
    func renderSnapshot() {
        let bridge = EngineBridge()
        func advance(_ action: () -> Void) {
            action()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        advance { bridge.incrementCounter(by: 2) }
        advance { bridge.incrementAlt(by: 10) }
        advance { bridge.toggleIndirectSource() }
        advance { bridge.setShowDetail(true) }
        advance { bridge.incrementCounter(by: 2) }

        let view = ContentView(bridge: bridge)
            .background(Color(nsColor: .windowBackgroundColor))
        let hosting = NSHostingView(rootView: view)
        let size = NSSize(width: 700, height: 500)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            fputs("Failed to allocate bitmap rep\n", stderr)
            exit(1)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            fputs("Failed to encode PNG\n", stderr)
            exit(1)
        }
        try! png.write(to: URL(fileURLWithPath: outputPath))
        print("Saved snapshot to \(outputPath)")
    }
    MainActor.assumeIsolated {
        renderSnapshot()
    }
    exit(0)
}

if CommandLine.arguments.contains("--verify") {
    @MainActor
    func runVerification() {
        let bridge = EngineBridge()
        func step(_ label: String, _ action: () -> Void) {
            action()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            let s = bridge.snapshot
            print("[\(label)] counter=\(s.counter) parity=\(s.parityText) parityRuns=\(s.parityRuns) indirect=\(s.activeIndirectValue) detail=\(s.detailText ?? "nil") detailRuns=\(s.detailRuns) nodes=\(s.nodeCount) edges=\(s.edgeCount) subgraphs=\(s.subgraphCount) recalcs=\(s.recalculationCount)")
        }

        step("initial") {}
        step("+2 (misma paridad)") { bridge.incrementCounter(by: 2) }
        step("+1 (cambia paridad)") { bridge.incrementCounter(by: 1) }
        step("alt +10") { bridge.incrementAlt(by: 10) }
        step("setSource -> alt") { bridge.toggleIndirectSource() }
        step("mount detailSubgraph") { bridge.setShowDetail(true) }
        step("+2 con detail vivo") { bridge.incrementCounter(by: 2) }
        step("unmount detailSubgraph") { bridge.setShowDetail(false) }
    }
    MainActor.assumeIsolated {
        runVerification()
    }
    exit(0)
}

app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
