import Testing
import class SwiftAttributeGraph.Graph
@testable import ResumableGraphPrototype

@Suite(.serialized) struct PerformanceTests {
    private func milliseconds(_ body: () -> Void) -> Double {
        let duration = ContinuousClock().measure(body)
        return Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    private func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
    private func report(_ label: String, _ samples: [Double]) {
        let rounded = (median(samples) * 100).rounded() / 100
        print("PERF \(label): \(rounded) ms (median of \(samples.count))")
    }

    @Test func coldChains() {
        for depth in [20_000, 100_000] {
            var samples: [Double] = []
            var storageBytes = 0
            for _ in 0..<5 {
                let graph = PrototypeGraph()
                let owner = graph.makeOwner()
                let counter = PrototypeTests.Counter()
                var last = graph.withOwner(owner) { graph.makeInput(0) }
                graph.withOwner(owner) {
                    for _ in 0..<depth { last = graph.makeRule(PrototypeTests.PlusOne(source: last, counter: counter)) }
                }
                var value = 0
                samples.append(milliseconds { value = graph.value(of: last) })
                #expect(value == depth && counter.starts == depth)
                storageBytes = graph.frameStorageBytes
                graph.invalidate(owner)
                #expect(graph.nodeCount == 0)
            }
            report("cold \(depth) rules, evaluation only", samples)
            print("MEMORY \(depth) rules: \(storageBytes) bytes reserved for frame elements (excludes nodes and allocator overhead)")
        }
    }

    struct Sum: ResumableRule {
        let first: ResumableGraphPrototype.Attribute<Int>
        let second: ResumableGraphPrototype.Attribute<Int>
        var left: Int?
        static var initialValue: Int? { 0 }
        mutating func resume(_ context: inout ResumableGraphPrototype.RuleContext<Int>) -> RuleStep {
            if context.isFirstStep { left = nil }
            if left == nil {
                switch context.poll(first) {
                case .pending: return .needsInput(first.erased)
                case .ready(let value): left = value
                }
            }
            switch context.poll(second) {
            case .pending: return .needsInput(second.erased)
            case .ready(let value):
                if context.hasChanged(first) { context.value = left! + value }
                return .finished
            }
        }
    }

    @Test func warmUpdatesAgainstTheProductionStatefulRule() {
        var prototype: [Double] = [], production: [Double] = []
        for _ in 0..<7 {
            let graph = PrototypeGraph()
            let input = graph.makeInput(0), other = graph.makeInput(1)
            let rules = (0..<1_000).map { _ in graph.makeRule(Sum(first: input, second: other)) }
            for rule in rules { _ = graph.value(of: rule) }
            prototype.append(milliseconds {
                for value in 1...50 {
                    graph.setValue(value, for: input)
                    for rule in rules { _ = graph.value(of: rule) }
                }
            })
            #expect(graph.value(of: rules[0]) == 51)

            let native = Graph()
            let a = native.makeInput(0), b = native.makeInput(1)
            let nativeRules = (0..<1_000).map { _ in
                native.makeStatefulRule(initialValue: 0) { context in
                    let first = a.value, second = b.value
                    if context.hasChanged(a) { context.value = first + second }
                }
            }
            for rule in nativeRules { _ = native.value(of: rule) }
            production.append(milliseconds {
                for value in 1...50 {
                    native.setValue(value, for: a)
                    for rule in nativeRules { _ = native.value(of: rule) }
                }
            })
            #expect(native.value(of: nativeRules[0]) == 51)
        }
        report("prototype 50 cycles x 1,000 stateful rules, 2 inputs, excludes creation", prototype)
        report("production 50 cycles x 1,000 stateful rules, 2 inputs, excludes creation", production)
    }

    @Test func cleanReads() {
        let graph = PrototypeGraph()
        let input = graph.makeInput(1)
        let rule = graph.makeRule(PrototypeTests.PlusOne(source: input, counter: .init()))
        #expect(graph.value(of: rule) == 2)
        var samples: [Double] = [], checksum = 0
        for _ in 0..<5 {
            samples.append(milliseconds { for _ in 0..<1_000_000 { checksum &+= graph.value(of: rule) } })
        }
        #expect(checksum == 10_000_000)
        report("prototype 1,000,000 clean reads", samples)
    }
}
