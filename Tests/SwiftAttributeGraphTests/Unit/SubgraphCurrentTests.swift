// Foundation and Dispatch are test-only, to run a second thread.
import Foundation
import Dispatch
import Testing
@testable import SwiftAttributeGraph

/// `Subgraph.current` (`AGSubgraphGetCurrent` and `AGSubgraphSetCurrent` in native AttributeGraph). Measured on
/// macOS 15.8.3 in an isolated probe [O]: it is `nil` outside any subgraph, the subgraph inside `apply`, restored after
/// a nested `apply`, `nil` once the current subgraph is invalidated, and unchanged inside a rule: the rule sees the
/// subgraph that was current where the read came from, which is `nil` for a read outside any `apply`.
@Suite struct SubgraphCurrentTests {
    @Test func isNilOutsideAnySubgraph() {
        _ = Graph()
        #expect(Subgraph.current == nil)
    }

    @Test func isTheSubgraphInsideWithCurrentAndRestoredAfterNesting() {
        let graph = Graph()
        let outer = graph.makeSubgraph()
        let inner = graph.makeSubgraph()
        graph.withCurrent(outer) {
            #expect(Subgraph.current == outer)
            graph.withCurrent(inner) { #expect(Subgraph.current == inner) }
            #expect(Subgraph.current == outer)
        }
        #expect(Subgraph.current == nil)
    }

    @Test func followsTheSubgraphAcrossTwoGraphs() throws {
        let g1 = Graph()
        let g2 = Graph()
        let s1 = g1.makeSubgraph()
        let s2 = g2.makeSubgraph()
        g2.withCurrent(s2) {
            #expect(Subgraph.current == s2 && Subgraph.current?.graph === g2)
            g1.withCurrent(s1) {
                #expect(Subgraph.current == s1 && Subgraph.current?.graph === g1)
                #expect(Subgraph.current != s2)
            }
            #expect(Subgraph.current == s2)
        }
        #expect(Subgraph.current == nil)
    }

    @Test func aRuleSeesTheSubgraphOfTheReadAndDoesNotChangeIt() {
        let graph = Graph()
        let sub = graph.makeSubgraph()
        let other = graph.makeSubgraph()
        var seen: [Subgraph?] = []
        let rule = graph.withCurrent(sub) {
            graph.makeRule { () -> Int in seen.append(Subgraph.current); return 1 }
        }
        let rule2 = graph.withCurrent(sub) {
            graph.makeRule { () -> Int in seen.append(Subgraph.current); return 2 }
        }
        _ = graph.value(of: rule)
        graph.withCurrent(other) {
            _ = graph.value(of: rule2)
            #expect(Subgraph.current == other)
        }
        #expect(seen.count == 2 && seen[0] == nil && seen[1] == other, "the rule's own subgraph is not made current")
        #expect(Subgraph.current == nil)
    }

    private final class Sink { var seen: [Subgraph?] = [] }

    private struct Recorder: ResumableRule {
        let source: Attribute<Int>
        let sink: Sink
        mutating func resume(_ context: inout ResumableRuleContext<Int>) -> RuleStep {
            switch context.poll(source) {
            case .pending: return .needsInput(source.erased)
            case .ready:
                sink.seen.append(Subgraph.current)
                context.value = 1
                return .finished
            }
        }
    }

    @Test func aResumableRuleSeesTheSubgraphOfTheReadToo() {
        let graph = Graph()
        let sub = graph.makeSubgraph()
        let sink = Sink()
        let rule = graph.withCurrent(sub) {
            graph.makeResumableRule(Recorder(source: graph.makeRule { 1 }, sink: sink))
        }
        _ = graph.value(of: rule)
        graph.withCurrent(sub) { graph.invalidateValue(of: rule) }
        graph.withCurrent(sub) { _ = graph.value(of: rule) }
        #expect(sink.seen.first == .some(nil) && sink.seen.last == .some(sub))
    }

    @Test func aWithCurrentInsideARuleSeesItsSubgraph() {
        let graph = Graph()
        let sub = graph.makeSubgraph()
        let inside = graph.makeSubgraph()
        var seen: [Subgraph?] = []
        let rule = graph.withCurrent(sub) {
            graph.makeRule { () -> Int in
                graph.withCurrent(inside) { seen.append(Subgraph.current) }
                seen.append(Subgraph.current)
                return 1
            }
        }
        _ = graph.value(of: rule)
        #expect(seen.count == 2 && seen[0] == inside && seen[1] == nil, "restored to what the read came from")
    }

    @Test func becomesNilWhenTheCurrentSubgraphIsInvalidated() {
        let graph = Graph()
        let outer = graph.makeSubgraph()
        let inner = graph.makeSubgraph()
        graph.withCurrent(outer) {
            graph.withCurrent(inner) {
                inner.invalidate()
                #expect(Subgraph.current == nil)
            }
            #expect(Subgraph.current == outer, "the outer one is restored after the inner one")
        }
        #expect(Subgraph.current == nil)
    }

    @Test func setCurrentStaysUntilChangedAndWithCurrentRestoresIt() {
        let graph = Graph()
        let g2 = Graph()
        let first = graph.makeSubgraph()
        let other = g2.makeSubgraph()
        Subgraph.current = first
        #expect(Subgraph.current == first)
        let created = graph.makeInput(1)
        #expect(graph.subgraph(of: created.id) == first, "attributes are created in the subgraph made current")
        g2.withCurrent(other) { #expect(Subgraph.current == other) }
        #expect(Subgraph.current == first)
        Subgraph.current = nil
        #expect(Subgraph.current == nil)
    }

    @Test func creatingAnAttributeAfterSettingCurrentToNilInsideWithCurrentStopsTheProgram() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            let sub = graph.makeSubgraph()
            graph.withCurrent(sub) {
                Subgraph.current = nil
                _ = graph.makeInput(1)
            }
        }
    }

    @Test func creatingAnAttributeAfterSettingCurrentToNilOutsideWithCurrentStopsTheProgram() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            Subgraph.current = nil
            _ = graph.makeInput(1)
        }
    }

    @Test func isPerThread() {
        final class Box: @unchecked Sendable { var seen: [Bool] = []; let done = DispatchSemaphore(value: 0) }
        let graph = Graph()
        let sub = graph.makeSubgraph()
        let box = Box()
        graph.withCurrent(sub) {
            let worker = Thread { box.seen.append(Subgraph.current == nil); box.done.signal() }
            worker.start()
            #expect(box.done.wait(timeout: .now() + 10) == .success)
            #expect(Subgraph.current == sub)
        }
        #expect(box.seen == [true])
    }
}
