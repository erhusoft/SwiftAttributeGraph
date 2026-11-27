import Testing
@testable import SwiftAttributeGraph

/// `Graph.withMainThreadHandler(_:do:)` and `Graph.mainUpdates`. Native lines measured on macOS 15.8.3 (oracle scenarios `h0` to
/// `h9`, `f0` to `f7`, `c1` to `c7`): every rule made with the Swift API is a main-thread rule, so a top-level update of a dirty rule
/// goes through the handler once, whatever the thread; the handler is off while its closure runs, so rules read inside do not call
/// it again. The counter rises by 1 per update of such a rule and by 1 more per pass through the handler.
@Suite struct MainThreadHandlerTests {
    final class Calls { var handler = 0; var runs = 0 }

    /// A handler that counts its calls and runs the closure it is given.
    private func countingHandler(_ calls: Calls) -> (() -> Void) -> Void {
        { run in calls.handler += 1; run() }
    }

    @Test func aRuleWithoutAHandlerCountsOneMainUpdate() { // h0 [42, 1, [true], 0, 1]
        let graph = Graph(); let sg = graph.makeSubgraph(); let calls = Calls()
        let rule = graph.withCurrent(sg) { graph.makeRule { calls.runs += 1; return 42 } }
        let before = graph.mainUpdates
        #expect(graph.value(of: rule) == 42)
        #expect(calls.runs == 1)
        #expect(graph.mainUpdates - before == 1)
    }

    @Test func aRuleReadInsideAHandlerGoesThroughItOnce() { // f0 [42, 1, 1, [true], 2]
        let graph = Graph(); let sg = graph.makeSubgraph(); let calls = Calls()
        let rule = graph.withCurrent(sg) { graph.makeRule { calls.runs += 1; return 42 } }
        let before = graph.mainUpdates
        var value = 0
        graph.withMainThreadHandler(countingHandler(calls), do: { value = graph.value(of: rule) })
        #expect(value == 42)
        #expect(calls.runs == 1)
        #expect(calls.handler == 1)
        #expect(graph.mainUpdates - before == 2)
    }

    @Test func aChainOfThreeRulesCallsTheHandlerOnce() { // c1 [60, 3, 1, [...], 4]
        let graph = Graph(); let sg = graph.makeSubgraph(); let calls = Calls()
        let (r1, r2, r3) = graph.withCurrent(sg) { () -> (Attribute<Int>, Attribute<Int>, Attribute<Int>) in
            let r1 = graph.makeRule { calls.runs += 1; return 10 }
            let r2 = graph.makeRule { calls.runs += 1; return r1.value + 20 }
            let r3 = graph.makeRule { calls.runs += 1; return r2.value + 30 }
            return (r1, r2, r3)
        }
        _ = (r1, r2)
        let before = graph.mainUpdates
        var value = 0
        graph.withMainThreadHandler(countingHandler(calls), do: { value = graph.value(of: r3) })
        #expect(value == 60)
        #expect(calls.runs == 3)
        #expect(calls.handler == 1)
        #expect(graph.mainUpdates - before == 4)
    }

    @Test func aCleanRuleDoesNotCallTheHandlerAgain() { // c4 [42, 42, 1, [1, 0], [2, 0]]
        let graph = Graph(); let sg = graph.makeSubgraph(); let calls = Calls()
        let rule = graph.withCurrent(sg) { graph.makeRule { calls.runs += 1; return 42 } }
        var deltas: [Int] = [], handlerCalls: [Int] = []
        graph.withMainThreadHandler(countingHandler(calls), do: {
            for _ in 0..<2 {
                let before = graph.mainUpdates, calledBefore = calls.handler
                _ = graph.value(of: rule)
                deltas.append(graph.mainUpdates - before)
                handlerCalls.append(calls.handler - calledBefore)
            }
        })
        #expect(handlerCalls == [1, 0])
        #expect(deltas == [2, 0])
        #expect(calls.runs == 1)
    }

    @Test func writingTheInputAndReadingAgainCallsTheHandlerAgain() { // c7 [11, 21, 2, [1, 1], [2, 2]]
        let graph = Graph(); let sg = graph.makeSubgraph(); let calls = Calls()
        let input = graph.withCurrent(sg) { graph.makeInput(10) }
        let rule = graph.withCurrent(sg) { graph.makeRule { calls.runs += 1; return input.value + 1 } }
        var values: [Int] = [], deltas: [Int] = [], handlerCalls: [Int] = []
        graph.withMainThreadHandler(countingHandler(calls), do: {
            for next in [10, 20] {
                graph.setValue(next, for: input)
                let before = graph.mainUpdates, calledBefore = calls.handler
                values.append(graph.value(of: rule))
                deltas.append(graph.mainUpdates - before)
                handlerCalls.append(calls.handler - calledBefore)
            }
        })
        #expect(values == [11, 21])
        #expect(handlerCalls == [1, 1])
        #expect(deltas == [2, 2])
        #expect(calls.runs == 2)
    }

    @Test func nestedHandlersUseTheInnerOneAndRestoreTheOuter() { // h7 [[0, 1], [1, 1], [1, 1]]
        let graph = Graph(); let sg = graph.makeSubgraph()
        var outer = 0, inner = 0
        let rules = graph.withCurrent(sg) { (0..<3).map { i in graph.makeRule { i } } }
        var steps: [[Int]] = []
        graph.withMainThreadHandler({ run in outer += 1; run() }, do: {
            graph.withMainThreadHandler({ run in inner += 1; run() }, do: {
                _ = graph.value(of: rules[0])
                steps.append([outer, inner])
            })
            _ = graph.value(of: rules[1])
            steps.append([outer, inner])
        })
        _ = graph.value(of: rules[2])
        steps.append([outer, inner])
        #expect(steps == [[0, 1], [1, 1], [1, 1]])
    }

    @Test func theBodyRunsOnce() { // h9 [1, true]
        let graph = Graph()
        var runs = 0
        graph.withMainThreadHandler({ run in run() }, do: { runs += 1 })
        #expect(runs == 1)
    }

    @Test func aHandlerThatDoesNotRunTheClosureStopsTheProgram() async { // c5 SIGABRT: the attribute has no value
        await #expect(processExitsWith: .failure) {
            let graph = Graph(); let sg = graph.makeSubgraph()
            let rule = graph.withCurrent(sg) { graph.makeRule { 1 } }
            graph.withMainThreadHandler({ _ in }, do: { _ = graph.value(of: rule) })
        }
    }
}
