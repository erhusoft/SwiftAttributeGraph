import Testing
import SwiftAttributeGraph
@testable import ShellUI

extension SliceTests {
    @Test func bindingContractSeparatesEagerClosuresFromStateProjection() {
        let graph = Graph()
        let scope = ViewGraphScope(graph: graph)
        let state = State(wrappedValue: 0)
        state.install(in: scope)
        var closureRuns = 0, projectionRuns = 0
        let explicit = graph.withCurrent(scope.owner) {
            graph.makeRule {
                closureRuns += 1
                _ = Binding(get: { state.wrappedValue }, set: { state.wrappedValue = $0 })
                return 0
            }
        }
        let projected = graph.withCurrent(scope.owner) {
            graph.makeRule {
                projectionRuns += 1
                _ = state.projectedValue
                return 0
            }
        }
        _ = graph.value(of: explicit)
        _ = graph.value(of: projected)
        #expect(graph.inputCount(of: explicit.id) == 1)
        #expect(graph.inputCount(of: projected.id) == 0)
        state.projectedValue.wrappedValue = 1
        #expect(closureRuns == 1 && projectionRuns == 1) // writes stay lazy
        _ = graph.value(of: explicit)
        _ = graph.value(of: projected)
        #expect(closureRuns == 2 && projectionRuns == 1)
        scope.unmount()
        #expect(graph.nodeCount == 0 && graph.edgeCount == 0)
    }

    @Test func bindingContractCopiesAndWritesDoNotAddGetterCalls() {
        var value = 7, gets = 0
        let binding = Binding(get: { gets += 1; return value }, set: { value = $0 })
        #expect(gets == 1)
        let copy = binding.projectedValue
        #expect(gets == 1)
        copy.wrappedValue = 9
        #expect(value == 9 && gets == 1)
        #expect(binding.wrappedValue == 9)
        #expect(gets == 2)
    }

    @Test func PerformanceBindingConstructionPaths() {
        let graph = Graph()
        let scope = ViewGraphScope(graph: graph)
        let state = State(wrappedValue: 7)
        state.install(in: scope)
        let clock = ContinuousClock()
        var sum = 0
        let explicit = clock.measure {
            for _ in 0..<10_000 {
                let binding = Binding(get: { state.wrappedValue }, set: { state.wrappedValue = $0 })
                sum += binding.wrappedValue
            }
        }
        let projection = clock.measure {
            for _ in 0..<10_000 { sum += state.projectedValue.wrappedValue }
        }
        #expect(sum == 140_000)
        scope.unmount()
        #expect(graph.nodeCount == 0)
        print("BindingContract 10000 constructions + reads: explicit=\(explicit) projection=\(projection)")
    }
}
