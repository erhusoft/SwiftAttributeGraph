import Testing
@testable import SwiftAttributeGraph

/// What SwiftUI does when a branch or a row goes away (E7, E8, E19 and round 7 of `parity/Compare`), written as the
/// view layer will drive the engine: one subgraph per branch and per row.
@Suite struct BranchParityTests {
    private final class Log { var events: [String] = [] }

    /// A piece of state that says when it is released.
    private final class Held {
        let name: String, log: Log
        init(_ name: String, _ log: Log) { self.name = name; self.log = log }
        deinit { log.events.append("\(name) state deinit") }
    }

    /// A branch made of an outer subgraph with two children, each with some state.
    private func makeBranch(_ graph: Graph, _ log: Log, prefix: String) -> Subgraph {
        let outer = graph.makeSubgraph()
        graph.observe(outer) { log.events.append("\(prefix) outer disappear") }
        for name in ["\(prefix)1", "\(prefix)2"] {
            let child = graph.makeSubgraph(parent: outer)
            graph.observe(child) { log.events.append("\(name) disappear") }
            graph.withCurrent(child) { _ = graph.makeInput(Held(name, log)) }
        }
        return outer
    }

    /// E7 / round 7: the new branch is built first; then the old one says it disappears, **parents before children
    /// (children in reverse creation order, matching native AttributeGraph) and all of it before any state is
    /// released**; then the states are released.
    @Test func switchingBranchBuildsTheNewOneFirstThenNoticesParentsFirstThenReleasesState() {
        let graph = Graph()
        let log = Log()
        let old = makeBranch(graph, log, prefix: "A")
        log.events = []
        let new = graph.makeSubgraph()
        log.events.append("B built")
        graph.invalidate(old)
        let events = log.events
        #expect(events.first == "B built")
        let disappear = events.indices.filter { events[$0].hasSuffix("disappear") }
        let released = events.indices.filter { events[$0].hasSuffix("state deinit") }
        #expect(disappear.count == 3 && released.count == 2)
        #expect(disappear.max()! < released.min()!, "every notice comes before any state is released")
        #expect(events.firstIndex(of: "A outer disappear")! < events.firstIndex(of: "A1 disappear")!)
        #expect(events.firstIndex(of: "A outer disappear")! < events.firstIndex(of: "A2 disappear")!)
        #expect(graph.isLive(new) && graph.nodeCount == 0)
    }

    /// E7: coming back to a branch builds new state with the initial value; the old state is gone.
    @Test func comingBackToABranchStartsFromTheInitialState() {
        let graph = Graph()
        var branch = graph.makeSubgraph()
        var state = graph.withCurrent(branch) { graph.makeInput(0) }
        graph.setValue(5, for: state)
        graph.invalidate(branch)
        branch = graph.makeSubgraph()
        state = graph.withCurrent(branch) { graph.makeInput(0) }
        #expect(graph.value(of: state) == 0)
    }

    /// The row layer of a `ForEach`: ids to subgraphs kept by the view layer. E8 and E19: the state follows the id;
    /// reordering creates and frees nothing and runs nothing; removing frees only that row; adding creates one.
    private struct Rows {
        let graph: Graph
        var subgraphs: [Int: Subgraph] = [:]
        var states: [Int: Attribute<Int>] = [:]
        var bodies: [Int: Attribute<String>] = [:]
        var runs = RunCounter()
        final class RunCounter { var perRow: [Int: Int] = [:] }

        init(_ graph: Graph) { self.graph = graph }

        mutating func show(_ ids: [Int]) {
            for id in subgraphs.keys where !ids.contains(id) {                 // rows that left
                graph.invalidate(subgraphs[id]!)
                subgraphs[id] = nil; states[id] = nil; bodies[id] = nil
            }
            for id in ids where subgraphs[id] == nil {                         // rows that arrived
                let sub = graph.makeSubgraph()
                subgraphs[id] = sub
                graph.withCurrent(sub) {
                    let state = graph.makeInput(id * 100)
                    states[id] = state
                    let counter = runs
                    bodies[id] = graph.makeRule { counter.perRow[id, default: 0] += 1; return "row \(id): \(state.value)" }
                }
            }
            for id in ids { _ = graph.value(of: bodies[id]!) }                 // the "layout" reads every row's body
        }
    }

    @Test func rowsKeepTheirStateWhenReorderedAndOnlyTheRemovedRowIsFreed() {
        let graph = Graph()
        var rows = Rows(graph)
        rows.show([1, 2, 3])
        graph.setValue(777, for: rows.states[2]!)
        _ = graph.value(of: rows.bodies[2]!)
        let base = graph.nodeCount
        let runsBefore = rows.runs.perRow

        rows.show([3, 1, 2])                                                   // reorder (E19: nothing runs)
        #expect(graph.nodeCount == base && rows.runs.perRow == runsBefore)
        #expect(graph.value(of: rows.states[2]!) == 777)                       // the state followed the id (E8)

        rows.show([3, 1])                                                      // remove row 2
        #expect(graph.nodeCount == base - 2 && rows.runs.perRow == runsBefore)

        rows.show([3, 1, 4])                                                   // add row 4
        #expect(graph.nodeCount == base)
        #expect(rows.runs.perRow[4] == 1 && rows.runs.perRow[1] == runsBefore[1] && rows.runs.perRow[3] == runsBefore[3])
    }
}
