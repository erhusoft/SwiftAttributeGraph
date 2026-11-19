import Foundation
import Testing
@testable import SwiftAttributeGraph

/// The per-thread context of the running rule (thread-local storage) and the one-graph-per-thread rule.
@Suite struct TrackingTests {
    private final class Flag: @unchecked Sendable { var seen: [Bool] = [] }

    @Test func thereIsNoCurrentGraphOutsideARule() {
        let graph = Graph()
        let a = graph.makeInput(1)
        #expect(ThreadLocalGraph.current() == nil)
        _ = graph.value(of: a)
        #expect(ThreadLocalGraph.current() == nil)
    }

    @Test func insideARuleTheCurrentGraphIsTheRunningOneAndIsRestoredAfterwards() {
        let graph = Graph()
        let flag = Flag()
        let rule = graph.makeRule { flag.seen.append(ThreadLocalGraph.current() === graph); return 1 }
        _ = graph.value(of: rule)
        #expect(flag.seen == [true])
        #expect(ThreadLocalGraph.current() == nil)
    }

    @Test func aNestedRuleRestoresTheContextOfTheOneThatReadIt() {
        let graph = Graph()
        let flag = Flag()
        let inner = graph.makeRule { flag.seen.append(ThreadLocalGraph.current() === graph); return 1 }
        let outer = graph.makeRule {
            let v = inner.value                          // runs `inner` nested inside `outer`
            flag.seen.append(ThreadLocalGraph.current() === graph)   // still the same graph after the nested run
            return v
        }
        _ = graph.value(of: outer)
        #expect(flag.seen == [true, true])
        #expect(ThreadLocalGraph.current() == nil)
    }

    @Test func eachThreadSeesOnlyItsOwnContext() {
        final class Failures: @unchecked Sendable { var counts = [0, 0] }
        let failures = Failures()
        let lock = NSLock()
        let group = DispatchGroup()
        for index in 0..<2 {
            group.enter()
            let thread = Thread {
                let graph = Graph()
                let input = graph.makeInput(index)
                let rule = graph.makeRule { input.value + 1 }
                var local = 0
                for step in 0..<2_000 {
                    graph.setValue(step, for: input)
                    if graph.value(of: rule) != step + 1 { local += 1 }
                    if ThreadLocalGraph.current() != nil { local += 1 }
                }
                lock.lock(); failures.counts[index] = local; lock.unlock()
                group.leave()
            }
            thread.start()
        }
        #expect(group.wait(timeout: .now() + 30) == .success)
        #expect(failures.counts == [0, 0])
    }

    @Test func aRuleThatReadsAnAttributeOfAnotherGraphStopsTheProgram() async {
        await #expect(processExitsWith: .failure) {
            let other = Graph()
            let foreign = other.makeInput(1)
            let graph = Graph()
            let rule = graph.makeRule { graph.value(of: foreign) }   // reads from the wrong graph
            _ = graph.value(of: rule)
        }
    }

    #if DEBUG && !SAG_UNCHECKED
    /// Debug builds stop the program when a graph is used from another thread (`assertOwnThread`). The check is
    /// tested through the predicate it uses: crashing a secondary thread makes the Windows crash handler take 30 s.
    @Test func aGraphKnowsWhichThreadOwnsIt() {
        final class Handoff: @unchecked Sendable { let graph = Graph(); var fromOtherThread: Bool? }   // shared on purpose
        let handoff = Handoff()
        #expect(handoff.graph.isOnOwningThread)
        let done = DispatchSemaphore(value: 0)
        let thread = Thread { handoff.fromOtherThread = handoff.graph.isOnOwningThread; done.signal() }
        thread.start()
        done.wait()
        #expect(handoff.fromOtherThread == false)
    }
    #endif

    @Test func anyInputsChangedMatchesNativeExcludingAndInvalidateValue() {
        let graph = Graph()
        let a = graph.makeInput(Int64(1))
        let b = graph.makeInput(Int64(10))
        var results: [Bool] = []
        var checkBeforeReads = false

        let r = graph.makeRule {
            if checkBeforeReads {
                results.append(graph.anyInputsChanged())
                results.append(graph.anyInputsChanged())
            }
            let va = a.value
            let vb = b.value
            if !checkBeforeReads {
                results.append(graph.anyInputsChanged())
                results.append(graph.anyInputsChanged(excluding: [AnyAttribute(id: a.id)]))
            }
            return va + vb
        }

        _ = graph.value(of: r)
        graph.setValue(2, for: a)
        _ = graph.value(of: r)

        checkBeforeReads = true
        graph.setValue(3, for: a)
        _ = graph.value(of: r)

        checkBeforeReads = false
        graph.invalidateValue(of: r)
        _ = graph.value(of: r)

        #expect(results == [true, true, true, false, true, true, false, false])
    }

    @Test func anyInputsChangedBeforeReadOnFirstEvaluationIsFalse() {
        let graph = Graph()
        let a = graph.makeInput(1)
        var firstBefore = true
        var firstAfter = false
        let r = graph.makeRule {
            firstBefore = graph.anyInputsChanged()
            let va = a.value
            firstAfter = graph.anyInputsChanged()
            return va
        }
        _ = graph.value(of: r)
        #expect(firstBefore == false)
        #expect(firstAfter == true)
    }

    @Test func clearAndSetUpdateMatchesNative() {
        let graph = Graph()
        let a = graph.makeInput(1)
        let b = graph.makeInput(10)
        var token1NonNil = false
        var token2NonNil = false
        var runs = 0

        let r = graph.makeRule {
            runs += 1
            let t1 = Graph.clearUpdate()
            token1NonNil = (t1 != nil)
            let t2 = Graph.clearUpdate()
            token2NonNil = (t2 != nil)
            let vb = b.value
            Graph.setUpdate(t2)
            Graph.setUpdate(t1)
            let va = a.value
            return va + vb
        }

        let v1 = graph.value(of: r)
        graph.setValue(20, for: b)
        let v2 = graph.value(of: r)
        graph.setValue(2, for: a)
        let v3 = graph.value(of: r)

        #expect(token1NonNil == true)
        #expect(token2NonNil == true)
        #expect(v1 == 11 && v2 == 11 && v3 == 22)
        #expect(runs == 2)
    }
}
