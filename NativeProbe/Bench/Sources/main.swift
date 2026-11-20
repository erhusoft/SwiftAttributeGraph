import Foundation

#if NATIVE_ATTRIBUTE_GRAPH
import AttributeGraph

private struct NativeClosureRule<T>: Rule, @unchecked Sendable {
    let fn: () -> T
    var value: T { fn() }
}

private final class BenchDriver {
    private let graph = Graph()
    private let rootSubgraph: Subgraph

    init() {
        rootSubgraph = Subgraph(graph: graph)
    }

    func input<V>(_ value: V) -> Attribute<V> {
        rootSubgraph.apply { Attribute(value: value) }
    }

    func rule<V>(_ body: @escaping () -> V) -> Attribute<V> {
        rootSubgraph.apply { Attribute(NativeClosureRule(fn: body)) }
    }

    func read<V>(_ attr: Attribute<V>) -> V { attr.value }
    func write<V>(_ value: V, to attr: Attribute<V>) { attr.value = value }

    func offset<V: BitwiseCopyable, F: BitwiseCopyable>(_ source: Attribute<V>, keyPath: KeyPath<V, F>) -> Attribute<F> {
        source.unsafeOffset(at: MemoryLayout<V>.offset(of: keyPath)!, as: F.self)
    }

    func weak<V>(_ attr: Attribute<V>) -> WeakAttribute<V> { WeakAttribute(attr) }
    func readWeak<V>(_ w: WeakAttribute<V>) -> V? { w.wrappedValue }

    func anyInputsChanged(excluding: [AnyAttribute]) -> Bool {
        Graph.anyInputsChanged(excluding: excluding)
    }
    func erased<V>(_ attr: Attribute<V>) -> AnyAttribute { attr.identifier }

    func makeSubgraph() -> Subgraph { Subgraph(graph: graph) }
    func withSubgraph<T>(_ sg: Subgraph, _ body: () -> T) -> T { sg.apply(body) }
    func invalidate(_ sg: Subgraph) { sg.invalidate() }
    func liveNodes() -> UInt64 { graph.counter(for: .nodes) }
}
#else
import SwiftAttributeGraph

private struct NativeClosureRule<T>: Rule, @unchecked Sendable {
    let fn: () -> T
    var value: T { fn() }
}

private final class BenchDriver {
    private let graph = Graph()

    func input<V>(_ value: V) -> Attribute<V> { graph.makeInput(value) }
    func rule<V>(_ body: @escaping () -> V) -> Attribute<V> { graph.makeRule(body) }
    func read<V>(_ attr: Attribute<V>) -> V { graph.value(of: attr) }
    func write<V>(_ value: V, to attr: Attribute<V>) { graph.setValue(value, for: attr) }

    func offset<V: BitwiseCopyable, F: BitwiseCopyable>(_ source: Attribute<V>, keyPath: KeyPath<V, F>) -> Attribute<F> {
        graph.makeOffsetFieldAttribute(of: source, keyPath: keyPath)
    }

    func weak<V>(_ attr: Attribute<V>) -> WeakAttribute<V> { WeakAttribute(attr) }
    func readWeak<V>(_ w: WeakAttribute<V>) -> V? { w.wrappedValue }

    func anyInputsChanged(excluding: [AnyAttribute]) -> Bool {
        graph.anyInputsChanged(excluding: excluding)
    }
    func erased<V>(_ attr: Attribute<V>) -> AnyAttribute { attr.erased }

    func makeSubgraph() -> Subgraph { graph.makeSubgraph() }
    func withSubgraph<T>(_ sg: Subgraph, _ body: () -> T) -> T { graph.withCurrent(sg, body) }
    func invalidate(_ sg: Subgraph) { graph.invalidate(sg) }
    func liveNodes() -> UInt64 { UInt64(graph.nodeCount) }
}
#endif

private struct Pair2: BitwiseCopyable, Equatable {
    var x: Int64
    var y: Int64
}

private func runWorkload(_ name: String, _ n: Int) -> (Int64, Int) {
    let d = BenchDriver()
    var runs = 0

    switch name {
    case "create-inputs-rules":
        for i in 0..<n {
            let inp = d.input(Int64(i))
            _ = d.rule { runs += 1; return d.read(inp) + 1 }
        }
        return (Int64(n), runs)

    case "hot-chain":
        let root = d.input(Int64(1))
        var cur = root
        var checkpoints: [Attribute<Int64>] = []
        for i in 0..<n {
            let prev = cur
            let next = d.rule { runs += 1; return d.read(prev) + 1 }
            if (i + 1) % 1000 == 0 { checkpoints.append(next) }
            cur = next
        }
        for cp in checkpoints { _ = d.read(cp) }
        _ = d.read(cur)
        runs = 0
        d.write(Int64(2), to: root)
        let v = d.read(cur)
        return (v, runs)

    case "fan-out":
        let root = d.input(Int64(1))
        var rules: [Attribute<Int64>] = []
        rules.reserveCapacity(n)
        for _ in 0..<n {
            rules.append(d.rule { runs += 1; return d.read(root) + 1 })
        }
        for r in rules { _ = d.read(r) }
        runs = 0
        d.write(Int64(2), to: root)
        var sum: Int64 = 0
        for r in rules { sum &+= d.read(r) }
        return (sum, runs)

    case "fan-in":
        var inputs: [Attribute<Int64>] = []
        inputs.reserveCapacity(n)
        for i in 0..<n { inputs.append(d.input(Int64(i))) }
        let r = d.rule {
            runs += 1
            var s: Int64 = 0
            for inp in inputs { s &+= d.read(inp) }
            return s
        }
        _ = d.read(r)
        runs = 0
        d.write(Int64(999), to: inputs[0])
        return (d.read(r), runs)

    case "diamond-layers":
        let width = max(1, n / 10)
        let root = d.input(Int64(1))
        var layer: [Attribute<Int64>] = (0..<width).map { _ in
            d.rule { runs += 1; return d.read(root) + 1 }
        }
        for _ in 1..<10 {
            let prev = layer
            layer = (0..<width).map { i in
                let a = prev[i]
                let b = prev[(i + 1) % width]
                return d.rule { runs += 1; return d.read(a) &+ d.read(b) }
            }
        }
        for r in layer { _ = d.read(r) }
        runs = 0
        d.write(Int64(2), to: root)
        var sum: Int64 = 0
        for r in layer { sum &+= d.read(r) }
        return (sum, runs)

    case "batch-writes":
        let inputs = (0..<32).map { d.input(Int64($0)) }
        let dependents = (0..<n).map { idx in
            d.rule {
                runs += 1
                var s = Int64(idx)
                for inp in inputs { s &+= d.read(inp) }
                return s
            }
        }
        for dep in dependents { _ = d.read(dep) }
        runs = 0
        var sum: Int64 = 0
        for round in 0..<100 {
            for i in 0..<32 { d.write(Int64(round + i), to: inputs[i]) }
            for dep in dependents { sum &+= d.read(dep) }
        }
        return (sum, runs)

    case "equal-write-cut":
        let root = d.input(Int64(42))
        let readers = (0..<n).map { _ in d.rule { runs += 1; return d.read(root) } }
        for r in readers { _ = d.read(r) }
        runs = 0
        for _ in 0..<n { d.write(Int64(42), to: root) }
        var sum: Int64 = 0
        for r in readers { sum &+= d.read(r) }
        return (sum, runs)

    case "subgraph-churn":
        let base = d.liveNodes()
        for _ in 0..<n {
            let sg = d.makeSubgraph()
            d.withSubgraph(sg) {
                let a = d.input(Int64(1))
                let b = d.input(Int64(2))
                let r = d.rule { runs += 1; return d.read(a) + d.read(b) }
                _ = d.read(r)
            }
            d.invalidate(sg)
        }
        let end = d.liveNodes()
        return (Int64(end &- base), runs)

    case "display-list-shape":
        var positions: [Attribute<Pair2>] = []
        var items: [Attribute<Int64>] = []
        let containerPos = d.input(Pair2(x: 0, y: 0))
        let viewFlag = d.input(Int64(1))
        for i in 0..<n {
            let pos = d.input(Pair2(x: Int64(i), y: 0))
            positions.append(pos)
            let offX = d.offset(pos, keyPath: \Pair2.x)
            let offY = d.offset(pos, keyPath: \Pair2.y)
            let w1 = d.weak(d.input(Int64(1)))
            let w2 = d.weak(d.input(Int64(2)))
            let w3 = d.weak(d.input(Int64(3)))
            let w4 = d.weak(d.input(Int64(4)))
            let w5 = d.weak(d.input(Int64(5)))
            let w6 = d.weak(d.input(Int64(6)))
            let item = d.rule {
                let _ = (d.read(offX), d.read(offY), d.read(containerPos), d.read(viewFlag))
                let _ = (d.readWeak(w1), d.readWeak(w2), d.readWeak(w3), d.readWeak(w4), d.readWeak(w5), d.readWeak(w6))
                if d.anyInputsChanged(excluding: [d.erased(pos), d.erased(containerPos), d.erased(viewFlag)]) {
                    runs += 1
                }
                return Int64(i)
            }
            items.append(item)
        }
        for it in items { _ = d.read(it) }
        runs = 0
        for i in stride(from: 0, to: n, by: 100) {
            d.write(Pair2(x: Int64(i + 1), y: 1), to: positions[i])
        }
        var sum: Int64 = 0
        for it in items { sum &+= d.read(it) }
        return (sum, runs)

    case "cold-read-moderate":
        let root = d.input(Int64(1))
        var cur = root
        for _ in 0..<n {
            let prev = cur
            cur = d.rule { runs += 1; return d.read(prev) + 1 }
        }
        let v = d.read(cur)
        return (v, runs)

    default:
        fatalError("Unknown workload \(name)")
    }
}

let args = CommandLine.arguments
let workload = args[1]
let n = Int(args[2])!
let clock = ContinuousClock()
var val: Int64 = 0
var runs = 0
let elapsed = clock.measure {
    (val, runs) = runWorkload(workload, n)
}
let ms = Double(elapsed.components.seconds) * 1_000.0 + Double(elapsed.components.attoseconds) / 1e15
print(String(format: "BENCH|%@|%d|%.4f|%lld|%d", workload, n, ms, val, runs))
