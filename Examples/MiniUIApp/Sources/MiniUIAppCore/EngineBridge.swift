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
    public var statefulText: String
    public var parityRuns: Int
    public var detailRuns: Int
    public var statefulRuns: Int
    public var summaryRuns: Int
    public var nodeCount: Int
    public var edgeCount: Int
    public var subgraphCount: Int
    public var recalculationCount: Int
    public var graphDump: String

    public init(
        counter: Int,
        altValue: Int,
        parityText: String,
        activeIndirectValue: Int,
        detailText: String?,
        statefulText: String,
        parityRuns: Int,
        detailRuns: Int,
        statefulRuns: Int,
        summaryRuns: Int,
        nodeCount: Int,
        edgeCount: Int,
        subgraphCount: Int,
        recalculationCount: Int,
        graphDump: String
    ) {
        self.counter = counter
        self.altValue = altValue
        self.parityText = parityText
        self.activeIndirectValue = activeIndirectValue
        self.detailText = detailText
        self.statefulText = statefulText
        self.parityRuns = parityRuns
        self.detailRuns = detailRuns
        self.statefulRuns = statefulRuns
        self.summaryRuns = summaryRuns
        self.nodeCount = nodeCount
        self.edgeCount = edgeCount
        self.subgraphCount = subgraphCount
        self.recalculationCount = recalculationCount
        self.graphDump = graphDump
    }
}

/// Stateful rule accumulating `counter` updates while reading `alt` inside `graph.withoutUpdate`
/// so changes to `alt` alone do not re-trigger this rule.
private struct AccumulatorStatefulRule: StatefulRule {
    typealias Value = String
    let graph: Graph
    let counter: Attribute<Int>
    let alt: Attribute<Int>
    let runs: EngineBridge.RunCounter
    private var steps = 0
    private var maxCounter = 0

    init(
        graph: Graph,
        counter: Attribute<Int>,
        alt: Attribute<Int>,
        runs: EngineBridge.RunCounter
    ) {
        self.graph = graph
        self.counter = counter
        self.alt = alt
        self.runs = runs
    }

    mutating func updateValue(_ context: inout RuleContext<String>) {
        runs.count += 1
        steps += 1
        let c = counter.value
        if c > maxCounter {
            maxCounter = c
        }
        let silentAlt = graph.withoutUpdate { alt.value }
        context.value = "Stateful #\(steps) (maxCounter=\(maxCounter), altSinArista=\(silentAlt))"
    }
}

/// Bridges a single-threaded `Graph` to a macOS SwiftUI window via `graph.observe(_:onDirty:)`.
@MainActor
public final class EngineBridge: ObservableObject {
    fileprivate final class RunCounter { var count = 0 }

    public let graph = Graph()
    public let counterAttr: Attribute<Int>
    public let altAttr: Attribute<Int>
    public let useAltAttr: Attribute<Bool>
    public let indirectAttr: Attribute<Int>

    private var detailSubgraph: Subgraph?
    private var detailWeak = WeakAttribute<String>()

    private let parityLabelAttr: Attribute<String>
    private let statefulAttr: Attribute<String>
    private let parityCounter = RunCounter()
    private let detailCounter = RunCounter()
    private let statefulCounter = RunCounter()
    private let summaryCounter = RunCounter()
    private var rootRuleHandle: Attribute<UISnapshot>?
    private var observationToken: ObservationToken?
    private var refreshScheduled = false

    @Published public private(set) var snapshot: UISnapshot
    @Published public private(set) var events: [String] = []
    @Published public var showDetail = false
    @Published public var showGraphDump = true

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
        self.statefulAttr = graph.makeStatefulRule(
            AccumulatorStatefulRule(
                graph: graph,
                counter: counter,
                alt: alt,
                runs: statefulCounter
            )
        )

        self.snapshot = UISnapshot(
            counter: 0, altValue: 100, parityText: "", activeIndirectValue: 0,
            detailText: nil, statefulText: "", parityRuns: 0, detailRuns: 0,
            statefulRuns: 0, summaryRuns: 0, nodeCount: 0, edgeCount: 0,
            subgraphCount: 0, recalculationCount: 0, graphDump: ""
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
        let stateful = statefulAttr
        return graph.makeRule { [unowned self] () -> UISnapshot in
            summaryCounter.count += 1
            let c = counter.value
            let a = alt.value
            let p = parityLabel.value
            let indVal = indirect.value
            let detail = graph.value(of: detailWeak)
            let statefulText = stateful.value
            return UISnapshot(
                counter: c,
                altValue: a,
                parityText: p,
                activeIndirectValue: indVal,
                detailText: detail,
                statefulText: statefulText,
                parityRuns: parityCounter.count,
                detailRuns: detailCounter.count,
                statefulRuns: statefulCounter.count,
                summaryRuns: summaryCounter.count,
                nodeCount: graph.nodeCount,
                edgeCount: graph.edgeCount,
                subgraphCount: graph.liveSubgraphCount,
                recalculationCount: graph.recalculationCount,
                graphDump: ""
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
        // Refresh counters and M8 graph dump after rule finishes so counts are exact.
        next.nodeCount = graph.nodeCount
        next.edgeCount = graph.edgeCount
        next.subgraphCount = graph.liveSubgraphCount
        next.recalculationCount = graph.recalculationCount
        next.graphDump = graph.dump()
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

    /// Applies both `+2` on `counter` and `+10` on `alt` inside a single `graph.withBatch`.
    public func applyDemoBatch() {
        performBatch {
            let nextC = graph.value(of: counterAttr) + 2
            let nextA = graph.value(of: altAttr) + 10
            graph.setValue(nextC, for: counterAttr)
            graph.setValue(nextA, for: altAttr)
        }
        log("withBatch(counter +2, alt +10) -> 1 notificación")
    }

    /// Reads `alt` inside `graph.withoutUpdate` without creating dependency edges or notifying UI.
    @discardableResult
    public func peekAltWithoutUpdate() -> Int {
        let value = graph.withoutUpdate { graph.value(of: altAttr) }
        log("withoutUpdate { alt } = \(value) (sin suscripción)")
        return value
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
                        HStack {
                            Button("Lote: +2 counter y +10 alt (withBatch)") {
                                bridge.applyDemoBatch()
                            }
                            Button("Leer alt sin arista (withoutUpdate)") {
                                _ = bridge.peekAltWithoutUpdate()
                            }
                            Spacer()
                            Toggle("Volcado M8", isOn: $bridge.showGraphDump)
                        }
                    }
                    .padding(6)
                }
            }

            GroupBox("Salidas calculadas por el grafo") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Paridad (Map + corte): \(bridge.snapshot.parityText)  [runs: \(bridge.snapshot.parityRuns)]")
                    Text("IndirectAttribute.value: \(bridge.snapshot.activeIndirectValue)")
                    Text("StatefulRule + withoutUpdate: \(bridge.snapshot.statefulText)  [runs: \(bridge.snapshot.statefulRuns)]")
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
                HStack(spacing: 18) {
                    Label("nodeCount: \(bridge.snapshot.nodeCount)", systemImage: "circle.grid.3x3")
                    Label("edgeCount: \(bridge.snapshot.edgeCount)", systemImage: "arrow.triangle.branch")
                    Label("subgraphs: \(bridge.snapshot.subgraphCount)", systemImage: "square.stack.3d.up")
                    Label("recalcs: \(bridge.snapshot.recalculationCount)", systemImage: "bolt")
                    Label("refreshes: \(bridge.snapshotPublishCount)", systemImage: "arrow.clockwise")
                }
                .monospacedDigit()
                .padding(6)
            }

            if bridge.showGraphDump {
                GroupBox("Volcado del grafo en vivo (M8: graph.dump())") {
                    ScrollView {
                        Text(bridge.snapshot.graphDump)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 120)
                }
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
                .frame(height: 95)
            }
        }
        .padding(16)
        .frame(minWidth: 700, minHeight: 580)
    }
}
