import Testing
@testable import SwiftAttributeGraph

/// `Graph.value(of:options:)` (`AGGraphGetValue` with options). Expected values are the ones measured natively on
/// macOS 15.8.3 (probe_opts_b.swift, sections B, C, D, E).
@Suite struct ReadOptionsTests {
    private final class Runs: @unchecked Sendable { var count = 0 }

    private func insideRule(_ options: Graph.ReadOptions) -> (values: [Int], runs: Int) {
        let graph = Graph()
        let src = graph.makeInput(10)
        let runs = Runs()
        let rule = graph.makeRule { runs.count += 1; return graph.value(of: src, options: options) }
        let first = graph.value(of: rule)
        graph.setValue(20, for: src)
        return ([first, graph.value(of: rule)], runs.count)
    }

    @Test func defaultAndEdgeOptionsCreateTheDependency() {
        let none = insideRule([])
        #expect(none.values == [10, 20] && none.runs == 2)
        let edge = insideRule(.dependency)
        #expect(edge.values == [10, 20] && edge.runs == 2)
    }

    @Test func noDependencyOptionReadsWithoutAnEdgeAndWinsOverDependency() {
        let no = insideRule(.noDependency)
        #expect(no.values == [10, 10] && no.runs == 1)
        let both = insideRule([.dependency, .noDependency])
        #expect(both.values == [10, 10] && both.runs == 1)
    }

    @Test func outsideARuleEveryOptionReturnsTheCurrentValue() {
        let graph = Graph()
        let src = graph.makeInput(10)
        for options: Graph.ReadOptions in [[], .dependency, .noDependency, [.dependency, .noDependency]] {
            #expect(graph.value(of: src, options: options) == 10)
        }
        graph.setValue(11, for: src)
        #expect(graph.value(of: src, options: .noDependency) == 11)
        #expect(graph.nodeCount == 1)
    }

    @Test func aNormalReadInTheSameRunKeepsTheEdgeEvenWithNoDependency() {
        for options: Graph.ReadOptions in [.dependency, .noDependency, [.dependency, .noDependency]] {
            let graph = Graph()
            let src = graph.makeInput(10)
            let rule = graph.makeRule { src.value + graph.value(of: src, options: options) }
            #expect(graph.value(of: rule) == 20)
            graph.setValue(20, for: src)
            #expect(graph.value(of: rule) == 40)
        }
    }

    @Test func anEdgeFromAnEarlierRunIsKeptOnlyIfTheLaterRunReadsWithTheDependencyOption() {
        func run(_ options: Graph.ReadOptions) -> (values: [Int], afterTrigger: Int, afterWrite: Int) {
            let graph = Graph()
            let src = graph.makeInput(10)
            let trigger = graph.makeInput(0)
            let runs = Runs()
            let rule = graph.makeRule {
                runs.count += 1
                let t = trigger.value
                return t == 0 ? src.value : graph.value(of: src, options: options) + t
            }
            let v1 = graph.value(of: rule)
            graph.setValue(100, for: trigger)
            let v2 = graph.value(of: rule)
            let afterTrigger = runs.count
            graph.setValue(20, for: src)
            return ([v1, v2, graph.value(of: rule)], afterTrigger, runs.count)
        }
        let edge = run(.dependency)
        #expect(edge.values == [10, 110, 120] && edge.afterTrigger == 2 && edge.afterWrite == 3)
        for options: Graph.ReadOptions in [.noDependency, [.dependency, .noDependency]] {
            let result = run(options)
            #expect(result.values == [10, 110, 110] && result.afterTrigger == 2 && result.afterWrite == 2)
        }
    }

    @Test func aDirtyRuleInputIsBroughtUpToDateWithEitherOption() {
        for options: Graph.ReadOptions in [.dependency, .noDependency] {
            let graph = Graph()
            let src = graph.makeInput(1)
            let mid = graph.makeRule { src.value * 2 }
            let runs = Runs()
            let rule = graph.makeRule { runs.count += 1; return graph.value(of: mid, options: options) }
            let first = graph.value(of: rule)
            graph.setValue(5, for: src)
            let second = graph.value(of: rule)
            #expect(first == 2)
            #expect(second == (options == .dependency ? 10 : 2) && runs.count == (options == .dependency ? 2 : 1))
            #expect(graph.value(of: mid, options: options) == 10)
        }
    }
}
