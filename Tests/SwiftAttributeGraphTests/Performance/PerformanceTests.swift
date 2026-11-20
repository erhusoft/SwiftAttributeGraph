import Testing
@testable import SwiftAttributeGraph

/// Measurements for `docs/PLAN-MOTOR.md`. Run in release, several times:
///
///     swift test -c release -Xswiftc -enable-testing --filter Performance
///
/// Each case reports the median of several runs. The assertions are generous ceilings that only catch a disaster;
/// the numbers that matter are printed and copied into the plan.
@Suite(.serialized) struct PerformanceTests {
    private static func median(runs: Int = 7, _ body: () -> Void) -> Double {
        var samples: [Double] = []
        let clock = ContinuousClock()
        for _ in 0..<runs {
            let elapsed = clock.measure(body)
            samples.append(Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15)
        }
        samples.sort()
        return samples[samples.count / 2]
    }

    private static func report(_ name: String, _ milliseconds: Double, _ detail: String = "") {
        let rounded = (milliseconds * 100).rounded() / 100
        print("PERF \(name): \(rounded) ms\(detail.isEmpty ? "" : " (\(detail))")")
    }

    @Test func createAndReadOneHundredThousandInputs() {
        var checksum = 0
        let ms = Self.median {
            let graph = Graph()
            let inputs = (0..<100_000).map { graph.makeInput($0) }
            for _ in 0..<10 { for input in inputs { checksum &+= graph.value(of: input) } }
        }
        Self.report("P4 create 100k inputs + 10 reads each", ms, "checksum \(checksum & 1)")
        #expect(ms < 5_000)
    }

    @Test func createOneHundredThousandRulesAsClosuresAndAsTypes() {
        struct Plus: Rule { let source: Attribute<Int>; var value: Int { source.value + 1 } }
        let closures = Self.median {
            let graph = Graph()
            let root = graph.makeInput(1)
            for _ in 0..<100_000 { _ = graph.makeRule { root.value + 1 } }
        }
        let types = Self.median {
            let graph = Graph()
            let root = graph.makeInput(1)
            for _ in 0..<100_000 { _ = graph.makeRule(Plus(source: root)) }
        }
        Self.report("P3 create 100k rules, closure form", closures)
        Self.report("P3 create 100k rules, Rule-type form", types)
        #expect(closures < 5_000 && types < 5_000)
    }

    @Test func firstRunOfTwentyThousandRules() {
        let ms = Self.median {
            let graph = Graph()
            let input = graph.makeInput(1)
            let rules = (0..<20_000).map { _ in graph.makeRule { input.value + 1 } }
            for rule in rules { _ = graph.value(of: rule) }
        }
        Self.report("create + first run of 20k rules reading one input", ms)
        #expect(ms < 5_000)
    }

    @Test func fiveHundredDistinctWritesWithOneThousandDependents() {
        let graph = Graph()
        let input = graph.makeInput(0)
        let rules = (0..<1_000).map { _ in graph.makeRule { input.value + 1 } }
        for rule in rules { _ = graph.value(of: rule) }
        var next = 0
        // The dependents are already dirty after the first write, so this measures the cost of a write when the
        // propagation has nothing new to mark, plus one full re-mark after a read of every dependent each 50 writes.
        let writesOnly = Self.median {
            for _ in 0..<500 { next += 1; graph.setValue(next, for: input) }
        }
        let withUpdates = Self.median {
            for _ in 0..<500 {
                next += 1
                graph.setValue(next, for: input)
                _ = graph.value(of: rules[next % rules.count])
            }
        }
        let fullCycle = Self.median(runs: 5) {
            for _ in 0..<50 {
                next += 1
                graph.setValue(next, for: input)
                for rule in rules { _ = graph.value(of: rule) }
            }
        }
        Self.report("500 writes, dependents stay dirty", writesOnly)
        Self.report("500 writes + read one dependent each", withUpdates)
        Self.report("50 cycles: write + update all 1,000 dependents", fullCycle, "= 50,000 rule runs")
        #expect(writesOnly < 2_000 && withUpdates < 2_000 && fullCycle < 5_000)
    }

    @Test func aBatchOfThirtyTwoWritesWithSharedDependents() {
        let graph = Graph()
        let inputs = (0..<32).map { graph.makeInput($0) }
        let rules = (0..<1_000).map { _ in graph.makeRule { inputs.reduce(0) { $0 + $1.value } } }
        for rule in rules { _ = graph.value(of: rule) }
        var next = 100
        let ms = Self.median {
            for _ in 0..<100 {
                graph.withBatch { for input in inputs { next += 1; graph.setValue(next, for: input) } }
                for rule in rules { _ = graph.value(of: rule) }
            }
        }
        Self.report("100 batches of 32 writes + update 1,000 shared dependents", ms)
        #expect(ms < 20_000)
    }

    @Test func updateAWarmChainOfTwentyThousandRules() {
        let graph = Graph()
        let root = graph.makeInput(0)
        var last = graph.makeRule { root.value + 1 }
        _ = graph.value(of: last)
        for _ in 1..<20_000 {
            let previous = last
            last = graph.makeRule { previous.value + 1 }
            _ = graph.value(of: last)
        }
        var next = 0
        let ms = Self.median {
            next += 1
            graph.setValue(next, for: root)
            _ = graph.value(of: last)
        }
        Self.report("write at the root + update a 20,000-rule chain", ms)
        #expect(ms < 2_000)
    }

    @Test func aWriteThatTheCutStopsAtTheFirstRule() {
        let graph = Graph()
        let root = graph.makeInput(0)
        let parity = graph.makeRule { root.value % 2 }
        var last = parity
        for _ in 0..<20_000 {
            let previous = last
            last = graph.makeRule { previous.value + 1 }
            _ = graph.value(of: last)
        }
        var next = 0
        let ms = Self.median {
            next += 2                                  // stays even: only the first rule runs
            graph.setValue(next, for: root)
            _ = graph.value(of: last)
        }
        Self.report("write + update when the cut stops at rule 1 of 20,000", ms)
        #expect(ms < 2_000)
    }

    @Test func invalidateThousandsOfSmallSubgraphs() {
        let ms = Self.median {
            let graph = Graph()
            let base = graph.makeInput(0)
            let subgraphs = (0..<2_000).map { _ in graph.makeSubgraph() }
            for subgraph in subgraphs {
                graph.withCurrent(subgraph) {
                    let state = graph.makeInput(1)
                    let body = graph.makeRule { state.value + base.value }
                    _ = graph.value(of: body)
                    for _ in 0..<3 { _ = graph.makeInput(2) }
                }
            }
            for subgraph in subgraphs { graph.invalidate(subgraph) }
        }
        Self.report("2,000 subgraphs x 5 attributes: create + invalidate", ms)
        #expect(ms < 10_000)
    }

    @Test func aRuleThatReadsManyInputsAndLosesHalfOfThem() {
        let graph = Graph()
        let inputs = (0..<20_000).map { graph.makeInput($0) }
        let limit = graph.makeInput(20_000)
        let sum = graph.makeRule {
            var total = 0
            for i in 0..<limit.value { total &+= inputs[i].value }
            return total
        }
        let ms = Self.median(runs: 3) {
            graph.setValue(20_000, for: limit)
            _ = graph.value(of: sum)
            graph.setValue(10_000, for: limit)         // half of the edges are pruned
            _ = graph.value(of: sum)
        }
        Self.report("20,000-input rule loses half of its edges (M7 target)", ms)
        #expect(ms < 60_000)
    }

    // MARK: M2: cost of a write under each policy

    /// One million writes of a value that alternates between two values (so each write is a change), per policy. A
    /// policy costs a function call and, for the plan, a walk over its operations.
    private static func writes<V>(_ name: String, _ a: V, _ b: V, policies: [(String, Comparison)]) {
        for (label, policy) in policies {
            let ms = median(runs: 5) {
                let graph = Graph()
                let input = graph.makeInput(a, comparison: policy)
                for i in 0..<500_000 { graph.setValue(i & 1 == 0 ? b : a, for: input) }
            }
            report("M2 \(name) x 500k alternating writes, \(label)", ms)
            #expect(ms < 10_000)
        }
    }

    @Test func writesUnderEachPolicy() {
        let all: [(String, Comparison)] = [("bits", .bits), ("viewValue", .viewValue), ("environment", .environment), ("stateWrite", .stateWrite)]
        Self.writes("Int", 1, 2, policies: all)
        Self.writes("Double", 1.0, 2.0, policies: all)
        Self.writes("String short", "abc", "abd", policies: all)
        Self.writes("String long", String(repeating: "abcdefghij", count: 5), String(repeating: "x", count: 50), policies: all)
        struct Mixed { var d: Double; var s: String; var n: Int }
        Self.writes("struct{Double,String,Int}", Mixed(d: 1, s: "a", n: 1), Mixed(d: 2, s: "b", n: 2), policies: all)
        Self.writes("Any holding Int", 1 as Any, 2 as Any, policies: all)
    }

    /// The same writes where the value does not change (the common case: nothing to do).
    @Test func unchangedWritesUnderEachPolicy() {
        for (label, policy) in [("bits", Comparison.bits), ("viewValue", .viewValue), ("stateWrite", .stateWrite)] {
            let long = String(repeating: "abcdefghij", count: 5)
            let ms = Self.median(runs: 5) {
                let graph = Graph()
                let input = graph.makeInput(long, comparison: policy)
                for _ in 0..<500_000 { graph.setValue(long, for: input) }
            }
            Self.report("M2 String long x 500k identical writes, \(label)", ms)
            #expect(ms < 10_000)
        }
    }

    // MARK: M3: rules with state

    /// 1,000 rules that read one input (and, the stateful ones, ask what changed) over 50 cycles of write + update.
    @Test func statefulRulesAgainstPlainRules() {
        func cycles(stateful: Bool) -> Double {
            Self.median(runs: 5) {
                let graph = Graph()
                let input = graph.makeInput(0)
                let other = graph.makeInput(0)
                let rules: [Attribute<Int>] = (0..<1_000).map { _ in
                    if stateful {
                        return graph.makeStatefulRule(initialValue: 0) { (c: inout RuleContext<Int>) in
                            let v = input.value
                            _ = other.value
                            if c.hasChanged(input) { c.value = v &+ 1 }
                        }
                    }
                    return graph.makeRule { _ = other.value; return input.value &+ 1 }
                }
                for rule in rules { _ = graph.value(of: rule) }
                for step in 1...50 {
                    graph.setValue(step, for: input)
                    for rule in rules { _ = graph.value(of: rule) }
                }
            }
        }
        let plain = cycles(stateful: false), stateful = cycles(stateful: true)
        Self.report("M3 50 cycles x 1,000 plain rules (2 inputs)", plain)
        Self.report("M3 50 cycles x 1,000 stateful rules (2 inputs, hasChanged)", stateful, "x\(((stateful / plain) * 100).rounded() / 100) of plain")
        #expect(stateful < 5_000)
    }

    // MARK: M5: subgraph trees

    @Test func invalidatingATreeOfOneHundredThousandSubgraphs() {
        let ms = Self.median(runs: 5) {
            let graph = Graph()
            let root = graph.makeSubgraph()
            var level = [root]
            for _ in 0..<5 {                                                    // 10 children each: 11,110 per... see below
                var next: [Subgraph] = []
                for parent in level { for _ in 0..<10 { next.append(graph.makeSubgraph(parent: parent)) } }
                level = next
            }
            for sub in level { graph.withCurrent(sub) { _ = graph.makeInput(1) } }
            graph.invalidate(root)
        }
        Self.report("M5 build + invalidate a tree of 111,111 subgraphs (100,000 attributes)", ms)
        #expect(ms < 5_000)
    }

    @Test func churnOfOneThousandRows() {
        let ms = Self.median(runs: 5) {
            let graph = Graph()
            var rows: [Subgraph] = []
            for round in 0..<20 {
                for sub in rows { graph.invalidate(sub) }
                rows = (0..<1_000).map { _ in
                    let sub = graph.makeSubgraph()
                    graph.withCurrent(sub) {
                        let state = graph.makeInput(round)
                        _ = graph.value(of: graph.makeRule { state.value + 1 })
                    }
                    return sub
                }
            }
        }
        Self.report("M5 20 rounds of replacing 1,000 rows (2 attributes each)", ms)
        #expect(ms < 5_000)
    }

    // MARK: M7: efficient edge removal

    /// A node with 100,000 dependents (outputs) that loses half of them.
    /// Each removal searches the dependent in the source's output list; without O(1) removal
    /// this is quadratic in the degree (100,000 × 50,000). With O(1) removal it is linear.
    @Test func removingHalfOfOneHundredThousandOutputsIsLinear() {
        let ms = Self.median(runs: 3) {
            let graph = Graph()
            let root = graph.makeInput(0)
            let middle = graph.makeRule { root.value + 1 }
            _ = graph.value(of: middle)

            // 100,000 children that read `middle` conditionally (based on a flag).
            // Reading `flag` first then `middle` means: when the flag is false, `middle` is
            // not read and its edge is pruned on the next run.
            var flags: [Attribute<Bool>] = []
            var children: [Attribute<Int>] = []
            for _ in 0..<100_000 {
                let flag = graph.makeInput(true)
                flags.append(flag)
                children.append(graph.makeRule {
                    _ = flag.value
                    return flag.value ? middle.value + 1 : 0
                })
            }
            // Run all children: each reads `middle`, so outputs[middle] gains 100,000 entries.
            for child in children { _ = graph.value(of: child) }

            // Flip half the flags to false and re-run those children: each prunes its edge to
            // `middle`, calling removeOutput(child, from: middle) while outputs[middle] still
            // has ~100,000 entries. Without O(1) removal each search is O(degree).
            for i in 0..<50_000 { graph.setValue(false, for: flags[i]) }
            for i in 0..<50_000 { _ = graph.value(of: children[i]) }
        }
        Self.report("M7 remove half of 100k outputs (edge removal O(1))", ms)
        #expect(ms < 5_000)
    }

    @Test
    func oneThousandRulesWithTenInputsOneHundredWrites() {
        let graph = Graph()
        let inputs = (0..<10).map { graph.makeInput($0) }
        let rules = (0..<1_000).map { idx in
            graph.makeRule {
                var sum = idx
                for input in inputs {
                    sum &+= input.value
                }
                return sum
            }
        }
        for rule in rules { _ = graph.value(of: rule) }

        let ms = Self.median(runs: 5) {
            for w in 0..<100 {
                graph.setValue(w, for: inputs[w % inputs.count])
                for rule in rules {
                    _ = graph.value(of: rule)
                }
            }
        }
        Self.report("1,000 rules x 10 inputs x 100 writes", ms)
        #expect(ms < 5_000)
    }
}
