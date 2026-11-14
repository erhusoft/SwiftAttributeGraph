import Testing
@testable import SwiftAttributeGraph

/// Differential tests against a reference model.
///
/// Two things are checked on random graphs with conditional reads (so dependencies change while the graph runs):
/// 1. **Values:** reading any rule gives what a full recalculation gives.
/// 2. **Executions** (parity, `docs/DISENO-M0.md` §8): a rule runs if and only if it never ran or one of the inputs it
///    read in its last run has a different version than the one it saw. The model re-implements that rule in the
///    simplest recursive way and counts runs; the engine must match it exactly, run by run.
@Suite struct OracleTests {
    private struct Generator {
        var state: UInt64
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 32) % UInt64(bound))
        }
    }

    private final class ChangeLog { var log: [[Bool]]; init(_ n: Int) { log = Array(repeating: [], count: n) } }
    private final class Calls { var counts: [Int]; init(_ n: Int) { counts = Array(repeating: 0, count: n) } }

    /// A rule reads `selector`; if its value is even it reads `left`, otherwise `right`; the result adds a bias.
    private struct Spec { let selector: Int, left: Int, right: Int, bias: Int }

    /// The reference model: versions, last reads and run counts, recursive and simple.
    private struct Model {
        let inputCount: Int
        let specs: [Spec]
        var values: [Int]
        var versions: [Int]
        var hasRun: [Bool]
        var reads: [[(node: Int, seen: Int)]]
        var runs: [Int]
        /// Rules with state verify all their inputs before running (no early exit) and log whether the selector changed.
        let stateful: (Int) -> Bool
        var changedLog: [[Bool]]

        init(inputs: [Int], specs: [Spec], stateful: @escaping (Int) -> Bool) {
            inputCount = inputs.count
            self.specs = specs
            self.stateful = stateful
            changedLog = Array(repeating: [], count: inputs.count + specs.count)
            values = inputs + Array(repeating: 0, count: specs.count)
            versions = Array(repeating: 1, count: inputs.count + specs.count)
            hasRun = Array(repeating: false, count: inputs.count + specs.count)
            reads = Array(repeating: [], count: inputs.count + specs.count)
            runs = Array(repeating: 0, count: inputs.count + specs.count)
        }

        mutating func write(_ node: Int, _ value: Int) {
            guard values[node] != value else { return }
            values[node] = value
            versions[node] += 1
        }

        mutating func update(_ node: Int) {
            guard node >= inputCount else { return }
            var mustRun = !hasRun[node]
            if !mustRun {
                for (source, seen) in reads[node] {
                    update(source)
                    if versions[source] != seen { mustRun = true; if !stateful(node) { break } }
                }
            }
            if mustRun { run(node) }
        }

        private mutating func read(_ source: Int, into list: inout [(node: Int, seen: Int)]) -> Int {
            update(source)
            list.append((source, versions[source]))
            return values[source]
        }

        private mutating func run(_ node: Int) {
            runs[node] += 1
            let spec = specs[node - inputCount]
            if stateful(node) {
                // `hasChanged(selector)` before reading: the first read of the previous run against what it saw.
                changedLog[node].append(reads[node].first.map { versions[$0.node] != $0.seen } ?? false)
            }
            var list: [(node: Int, seen: Int)] = []
            let selector = read(spec.selector, into: &list)
            let picked = read(selector % 2 == 0 ? spec.left : spec.right, into: &list)
            let result = selector &+ picked &+ spec.bias
            reads[node] = list
            if !hasRun[node] || values[node] != result {
                values[node] = result
                versions[node] += 1
            }
            hasRun[node] = true
        }
    }

    @Test func randomGraphsMatchTheValueOracleAndTheExecutionModel() {
        let inputCount = 8, ruleCount = 40
        for seed in 1...12 {
            var random = Generator(state: UInt64(seed) &* 104729)
            let graph = Graph()
            let calls = Calls(inputCount + ruleCount)
            let changes = ChangeLog(inputCount + ruleCount)

            var inputValues: [Int] = []
            var nodes: [Attribute<Int>] = []
            for _ in 0..<inputCount {
                let v = random.next(101) - 50
                inputValues.append(v)
                nodes.append(graph.makeInput(v))
            }
            var specs: [Spec] = []
            for k in 0..<ruleCount {
                let index = inputCount + k
                let spec = Spec(selector: random.next(index), left: random.next(index), right: random.next(index),
                                bias: random.next(11) - 5)
                specs.append(spec)
                if index % 3 == 0 {
                    nodes.append(graph.makeStatefulRule { (c: inout RuleContext<Int>) in
                        calls.counts[index] += 1
                        changes.log[index].append(c.hasChanged(nodes[spec.selector]))
                        let selector = nodes[spec.selector].value
                        let picked = selector % 2 == 0 ? nodes[spec.left].value : nodes[spec.right].value
                        c.value = selector &+ picked &+ spec.bias
                    })
                } else {
                    nodes.append(graph.makeRule {
                        calls.counts[index] += 1
                        let selector = nodes[spec.selector].value
                        let picked = selector % 2 == 0 ? nodes[spec.left].value : nodes[spec.right].value
                        return selector &+ picked &+ spec.bias
                    })
                }
            }
            var model = Model(inputs: inputValues, specs: specs, stateful: { $0 % 3 == 0 })

            func fullRecalculation() -> [Int] {
                var all = inputValues
                for spec in specs {
                    let selector = all[spec.selector]
                    all.append(selector &+ (selector % 2 == 0 ? all[spec.left] : all[spec.right]) &+ spec.bias)
                }
                return all
            }

            for step in 0..<80 {
                if random.next(4) != 0 {
                    let input = random.next(inputCount)
                    let value = random.next(21) - 10     // small range: equal writes and equal results happen often
                    inputValues[input] = value
                    let before = calls.counts
                    graph.setValue(value, for: nodes[input])
                    model.write(input, value)
                    #expect(calls.counts == before, "seed \(seed) step \(step): a write must not run rules")
                }
                let target = inputCount + random.next(ruleCount)
                let expected = fullRecalculation()
                model.update(target)
                #expect(graph.value(of: nodes[target]) == expected[target], "seed \(seed) step \(step) node \(target)")
                #expect(calls.counts == model.runs, "seed \(seed) step \(step): executions differ from the model")
                #expect(changes.log == model.changedLog, "seed \(seed) step \(step): `hasChanged` differs from the model")

                let after = calls.counts
                #expect(graph.value(of: nodes[target]) == expected[target])
                #expect(calls.counts == after, "a clean second read must do no work")
            }
        }
    }

    @Test func laziestPossibleReadAfterManyWritesRunsOnlyWhatIsNeeded() {
        let graph = Graph()
        let input = graph.makeInput(0)
        let calls = Calls(1)
        let rule = graph.makeRule { calls.counts[0] += 1; return input.value }
        _ = graph.value(of: rule)
        for v in 1...1_000 { graph.setValue(v, for: input) }
        #expect(calls.counts[0] == 1)
        #expect(graph.value(of: rule) == 1_000)
        #expect(calls.counts[0] == 2, "a thousand writes, one run")
    }
}
