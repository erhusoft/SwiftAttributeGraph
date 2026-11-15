import AppKit
import SwiftAttributeGraph
import SwiftUI

/// Snapshot produced lazily by the `SwiftAttributeGraph` engine and rendered by the window.
public struct UISnapshot: Equatable, Sendable {
    public var counter: Int
    public var altValue: Int
    public var parityText: String
    public var activeIndirectValue: Int
    public var detailText: String?
    public var parityRuns: Int
    public var detailRuns: Int
    public var summaryRuns: Int
    public var nodeCount: Int
    public var edgeCount: Int
    public var subgraphCount: Int
    public var recalculationCount: Int

    public init(
        counter: Int,
        altValue: Int,
        parityText: String,
        activeIndirectValue: Int,
        detailText: String?,
        parityRuns: Int,
        detailRuns: Int,
        summaryRuns: Int,
        nodeCount: Int,
        edgeCount: Int,
        subgraphCount: Int,
        recalculationCount: Int
    ) {
        self.counter = counter
        self.altValue = altValue
        self.parityText = parityText
        self.activeIndirectValue = activeIndirectValue
        self.detailText = detailText
        self.parityRuns = parityRuns
        self.detailRuns = detailRuns
        self.summaryRuns = summaryRuns
        self.nodeCount = nodeCount
        self.edgeCount = edgeCount
        self.subgraphCount = subgraphCount
        self.recalculationCount = recalculationCount
    }
}

/// Bridges a single-threaded `Graph` to a macOS SwiftUI window via `graph.observe(_:onDirty:)`.
@MainActor
public final class EngineBridge: ObservableObject {
    private final class RunCounter { var count = 0 }

    public let graph = Graph()
    public let counterAttr: Attribute<Int>
    public let altAttr: Attribute<Int>
    public let useAltAttr: Attribute<Bool>
    public let indirectAttr: Attribute<Int>

    private var detailSubgraph: Subgraph?
    private var detailWeak = WeakAttribute<String>()

    private let parityLabelAttr: Attribute<String>
    private let parityCounter = RunCounter()
    private let detailCounter = RunCounter()
    private let summaryCounter = RunCounter()
    private var rootRuleHandle: Attribute<UISnapshot>?
    private var observationToken: ObservationToken?
    private var refreshScheduled = false

    @Published public private(set) var snapshot: UISnapshot
    @Published public private(set) var events: [String] = []
    @Published public var showDetail = false

    /// Number of times `snapshot` was published to SwiftUI after initialization (1 per coalesced graph update).
    public private(set) var snapshotPublishCount = 0

    /// Number of times `graph.observe` fired `scheduleRefresh`.
    public private(set) var dirtyNotificationCount = 0

    public init() {
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
        self.pullSnapshot(rootRule, countAsPublish: false)
        self.observationToken = graph.observe(rootRule.erased) { [weak self] in
            self?.dirtyNotificationCount += 1
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
            guard let self, self.refreshScheduled else { return }
            self.refreshScheduled = false
            self.pullSnapshot(rule, countAsPublish: true)
        }
    }

    private func pullSnapshot(_ rule: Attribute<UISnapshot>, countAsPublish: Bool) {
        var next = graph.value(of: rule)
        // Refresh counters after rule finishes so `nodeCount` / `recalculationCount` are exact.
        next.nodeCount = graph.nodeCount
        next.edgeCount = graph.edgeCount
        next.subgraphCount = graph.liveSubgraphCount
        next.recalculationCount = graph.recalculationCount
        snapshot = next
        if countAsPublish {
            snapshotPublishCount += 1
        }
    }

    public func incrementCounter(by delta: Int) {
        let next = graph.value(of: counterAttr) + delta
        graph.setValue(next, for: counterAttr)
        log("setValue(\(next), for: counter)")
    }

    public func incrementAlt(by delta: Int) {
        let next = graph.value(of: altAttr) + delta
        graph.setValue(next, for: altAttr)
        log("setValue(\(next), for: alt)")
    }

    public func toggleIndirectSource() {
        let nextUseAlt = !graph.value(of: useAltAttr)
        graph.setValue(nextUseAlt, for: useAltAttr)
        let target = nextUseAlt ? altAttr : counterAttr
        graph.setSource(target, for: indirectAttr)
        log("setSource(\(nextUseAlt ? "alt" : "counter"), for: indirect)")
    }

    public func setShowDetail(_ show: Bool) {
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

    /// Runs a batch of engine mutations inside `graph.withBatch` so SwiftUI refreshes once at the end.
    public func performBatch(_ body: () -> Void) {
        graph.withBatch(body)
    }

    /// Forces any pending main-queue refresh to flush synchronously (used by tests, `--verify`, and `--bench`).
    public func flushUI() {
        guard refreshScheduled, let rule = rootRuleHandle else { return }
        refreshScheduled = false
        pullSnapshot(rule, countAsPublish: true)
    }

    private func log(_ message: String) {
        events.insert(message, at: 0)
        if events.count > 12 { events.removeLast() }
    }
}

public struct ContentView: View {
    @ObservedObject var bridge: EngineBridge

    public init(bridge: EngineBridge) {
        self.bridge = bridge
    }

    public var body: some View {
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
