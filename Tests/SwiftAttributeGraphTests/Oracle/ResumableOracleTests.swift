import Testing
@testable import SwiftAttributeGraph

@Suite struct ResumableOracleTests {
    struct Generator {
        var state: UInt64
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 32) % UInt64(bound))
        }
    }
    struct Spec { let selector: Int; let left: Int; let right: Int; let bias: Int }
    final class Counts {
        var starts: [Int]
        init(_ count: Int) { starts = Array(repeating: 0, count: count) }
    }

    struct Select: ResumableRule {
        let selector: Attribute<Int>
        let left: Attribute<Int>
        let right: Attribute<Int>
        let bias: Int
        let index: Int
        let counts: Counts
        var selectorValue: Int?
        var selected: Attribute<Int>?
        mutating func resume(_ context: inout ResumableRuleContext<Int>) -> RuleStep {
            if context.isFirstStep {
                counts.starts[index] += 1
                selectorValue = nil
                selected = nil
            }
            if selected == nil {
                switch context.poll(selector) {
                case .pending: return .needsInput(selector.erased)
                case .ready(let value):
                    selectorValue = value
                    selected = value % 2 == 0 ? left : right
                }
            }
            let source = selected!
            switch context.poll(source) {
            case .pending: return .needsInput(source.erased)
            case .ready(let value): context.value = selectorValue! &+ value &+ bias; return .finished
            }
        }
    }

    struct SynchronousSelect: StatefulRule {
        typealias Value = Int
        let selector: Attribute<Int>
        let left: Attribute<Int>
        let right: Attribute<Int>
        let bias: Int
        let index: Int
        let counts: Counts
        mutating func updateValue() {
            counts.starts[index] += 1
            let selector = selector.value
            context.value = selector &+ (selector % 2 == 0 ? left.value : right.value) &+ bias
        }
    }

    // A demand evaluator for small DAGs: repeatedly inspect the whole node until every required source is ready.
    // It has no incremental frame cursor, suspended rule, dirty propagation, or production tracking code.
    struct Model {
        let inputCount: Int
        let specs: [Spec]
        var values: [Int]
        var versions: [Int]
        var reads: [[(source: Int, version: Int)]]
        var starts: [Int]

        init(inputs: [Int], specs: [Spec]) {
            inputCount = inputs.count
            self.specs = specs
            values = inputs + Array(repeating: 0, count: specs.count)
            versions = Array(repeating: 1, count: values.count)
            reads = Array(repeating: [], count: values.count)
            starts = Array(repeating: 0, count: values.count)
        }

        mutating func write(_ index: Int, _ value: Int) {
            if values[index] != value { values[index] = value; versions[index] += 1 }
        }

        mutating func update(_ target: Int) {
            var done = Set(0..<inputCount)
            var stack = [target]
            while let node = stack.last {
                if done.contains(node) { stack.removeLast(); continue }
                if let missing = reads[node].first(where: { !done.contains($0.source) }) {
                    stack.append(missing.source)
                    continue
                }
                let mustRun = starts[node] == 0 || reads[node].contains { versions[$0.source] != $0.version }
                if !mustRun { done.insert(node); stack.removeLast(); continue }
                let spec = specs[node - inputCount]
                if !done.contains(spec.selector) { stack.append(spec.selector); continue }
                let source = values[spec.selector] % 2 == 0 ? spec.left : spec.right
                if !done.contains(source) { stack.append(source); continue }
                let result = values[spec.selector] &+ values[source] &+ spec.bias
                if starts[node] == 0 || result != values[node] { versions[node] += 1; values[node] = result }
                starts[node] += 1
                reads[node] = [(spec.selector, versions[spec.selector])]
                if source != spec.selector {
                    reads[node].append((source, versions[source]))
                    reads[node].sort { $0.source < $1.source }
                }
                done.insert(node)
                stack.removeLast()
            }
        }

        func fullValue(of target: Int) -> Int {
            var all = Array(values.prefix(inputCount))
            for spec in specs {
                let selector = all[spec.selector]
                all.append(selector &+ (selector % 2 == 0 ? all[spec.left] : all[spec.right]) &+ spec.bias)
            }
            return all[target]
        }
    }

    @Test func conditionalDAGsMatchFullValuesExecutionsVersionsAndDependencies() {
        let inputCount = 8, ruleCount = 64
        for seed in 1...12 {
            var random = Generator(state: UInt64(seed) * 104729)
            let graph = Graph()
            let counts = Counts(inputCount + ruleCount)
            let inputValues = (0..<inputCount).map { _ in random.next(21) - 10 }
            var attributes = inputValues.map { graph.makeInput($0) }
            var specs: [Spec] = []
            for index in inputCount..<(inputCount + ruleCount) {
                let spec = Spec(selector: random.next(index), left: random.next(index),
                                right: random.next(index), bias: random.next(7) - 3)
                specs.append(spec)
                if index % 3 == 0 {
                    attributes.append(graph.makeStatefulRule(SynchronousSelect(selector: attributes[spec.selector],
                        left: attributes[spec.left], right: attributes[spec.right], bias: spec.bias,
                        index: index, counts: counts)))
                } else {
                    attributes.append(graph.makeResumableRule(Select(selector: attributes[spec.selector],
                        left: attributes[spec.left], right: attributes[spec.right], bias: spec.bias,
                        index: index, counts: counts)))
                }
            }
            var model = Model(inputs: inputValues, specs: specs)
            for step in 0..<100 {
                if random.next(4) != 0 {
                    let index = random.next(inputCount), value = random.next(11) - 5
                    let before = counts.starts
                    graph.setValue(value, for: attributes[index])
                    model.write(index, value)
                    #expect(counts.starts == before)
                }
                let target = inputCount + random.next(ruleCount)
                model.update(target)
                #expect(graph.value(of: attributes[target]) == model.fullValue(of: target), "seed \(seed), step \(step)")
                #expect(counts.starts == model.starts, "seed \(seed), step \(step): execution counts")
                for index in inputCount..<(inputCount + ruleCount) where counts.starts[index] > 0 {
                    #expect(graph.version(of: attributes[index].id) == UInt32(model.versions[index]))
                    #expect(graph.inputs(of: attributes[index].id)
                            == model.reads[index].map { attributes[$0.source].id })
                }
                #expect(graph.frames.isEmpty)
            }
        }
    }
}
