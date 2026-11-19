// Shared contexts: a second context over the same graph (`AGGraphCreateShared`). In native AttributeGraph the
// `AGGraphRef` is the context, so `Graph(shared: g)` is a new object over the same graph; in the engine it is a
// `GraphContext` obtained from `Graph.makeSharedContext()`.
import Foundation

#if NATIVE_ATTRIBUTE_GRAPH
import AttributeGraph

final class ContextHandle {
    let graph: AttributeGraph.Graph
    init(_ graph: AttributeGraph.Graph) { self.graph = graph }
    /// graphID, contextID, threadUpdating, contextThreadUpdating, needsUpdate, contextNeedsUpdate, mainThreadUpdates.
    func stateCounters() -> [UInt64] {
        [graph.counter(for: .graphID), graph.counter(for: .contextID), graph.counter(for: .threadUpdating),
         graph.counter(for: .contextThreadUpdating), graph.counter(for: .needsUpdate),
         graph.counter(for: .contextNeedsUpdate), graph.counter(for: .mainThreadUpdates)]
    }
    func counter(nodes: Void = ()) -> UInt64 { graph.counter(for: .nodes) }
    func counter(subgraphs: Void = ()) -> UInt64 { graph.counter(for: .subgraphs) }
    func setUpdateCallback(_ body: @escaping () -> Void) { graph.onUpdate(body) }
    func setNeedsUpdate() { graph.setNeedsUpdate() }
    func makeSubgraph() -> SubgraphHandle { AttributeGraph.Subgraph(graph: graph) }
    func owns(_ subgraph: SubgraphHandle) -> Bool { subgraph.graph === graph }
    func owns<V>(_ attribute: Handle<V>) -> Bool { attribute.identifier.graph === graph }
}

extension Driver {
    var defaultContext: ContextHandle { ContextHandle(graph) }
    func makeSharedContext() -> ContextHandle { ContextHandle(AttributeGraph.Graph(shared: graph)) }
}
#else
import SwiftAttributeGraph

final class ContextHandle {
    let graph: Graph
    let context: GraphContext
    init(_ graph: Graph, _ context: GraphContext) { self.graph = graph; self.context = context }
    func stateCounters() -> [UInt64] {
        [context.counter(for: .graphID), context.counter(for: .contextID), context.counter(for: .threadUpdating),
         context.counter(for: .contextThreadUpdating), context.counter(for: .needsUpdate),
         context.counter(for: .contextNeedsUpdate), context.counter(for: .mainThreadUpdates)]
    }
    func counter(nodes: Void = ()) -> UInt64 { context.counter(for: .nodes) }
    func counter(subgraphs: Void = ()) -> UInt64 { context.counter(for: .subgraphs) }
    func setUpdateCallback(_ body: @escaping () -> Void) { context.setUpdateCallback(body) }
    func setNeedsUpdate() { context.setNeedsUpdate() }
    func makeSubgraph() -> SubgraphHandle { context.makeSubgraph() }
    func owns(_ subgraph: SubgraphHandle) -> Bool { graph.graphContext(of: subgraph) === context }
    func owns<V>(_ attribute: Handle<V>) -> Bool { graph.graphContext(of: attribute) === context }
}

extension Driver {
    var defaultContext: ContextHandle { ContextHandle(graph, graph.defaultContext) }
    func makeSharedContext() -> ContextHandle { ContextHandle(graph, graph.makeSharedContext()) }
}
#endif

/// The identifiers of shared contexts, relative to the first graph of the scenario: the graph takes `n` and its
/// context `n + 1`; a shared context keeps the graphID and takes the next number; nothing gives numbers back.
func sharedContextIds() {
    let first = Driver()
    let base = first.stateCounters()[0]
    func rel(_ context: ContextHandle) -> String {
        let s = context.stateCounters()
        return "\(Int(s[0]) - Int(base)),\(Int(s[1]) - Int(base))"
    }
    var ids = [rel(first.defaultContext)]
    let s1 = first.makeSharedContext(); ids.append(rel(s1))
    let second = Driver(); ids.append(rel(second.defaultContext))
    let s2 = second.makeSharedContext(); ids.append(rel(s2))
    let s3 = first.makeSharedContext(); ids.append(rel(s3))
    do { _ = first.makeSharedContext() }
    let third = Driver(); ids.append(rel(third.defaultContext))
    ids.append(rel(first.defaultContext))
    print("shared-context-ids|ids=\(ids)")
}

/// `needsUpdate` and `contextNeedsUpdate` of both contexts around `setNeedsUpdate` and reads of rules of each context.
func sharedContextNeedsUpdate() {
    let d = Driver()
    let c1 = d.defaultContext
    let c2 = d.makeSharedContext()
    let sg1 = c1.makeSubgraph(), sg2 = c2.makeSubgraph()
    let a = d.withSubgraph(sg1) { d.input(Int64(1)) }
    let r1: Handle<Int64> = d.withSubgraph(sg1) { d.rule { d.read(a) + 1 } }
    let r2: Handle<Int64> = d.withSubgraph(sg2) { d.rule { d.read(a) + 2 } }
    var log: [String] = []
    func flags(_ label: String) {
        let s1 = c1.stateCounters(), s2 = c2.stateCounters()
        log.append("\(label)=\(s1[4])\(s1[5])\(s2[4])\(s2[5])")
    }
    flags("start")
    c1.setNeedsUpdate(); flags("setC1")
    _ = d.read(r2); flags("readR2")
    c2.setNeedsUpdate(); flags("setC2")
    _ = d.read(r1); flags("readR1")
    c1.setNeedsUpdate(); c2.setNeedsUpdate(); flags("setBoth")
    _ = d.read(a); flags("readInput")
    _ = d.read(r2); flags("readR2again")
    print("shared-context-needs-update|\(log)")
}

/// Which update callback runs when a rule of each context is read after `setNeedsUpdate` on one or both contexts.
func sharedContextUpdateCallback() {
    let d = Driver()
    let c1 = d.defaultContext
    let c2 = d.makeSharedContext()
    var calls1 = 0, calls2 = 0
    c1.setUpdateCallback { calls1 += 1 }
    c2.setUpdateCallback { calls2 += 1 }
    let sg1 = c1.makeSubgraph(), sg2 = c2.makeSubgraph()
    let a = d.withSubgraph(sg1) { d.input(Int64(1)) }
    let r1: Handle<Int64> = d.withSubgraph(sg1) { d.rule { d.read(a) + 1 } }
    let r2: Handle<Int64> = d.withSubgraph(sg2) { d.rule { d.read(a) + 2 } }
    var log: [String] = []
    func calls(_ label: String) { log.append("\(label)=\(calls1),\(calls2)") }
    _ = d.read(r1); _ = d.read(r2); calls("readNoFlag")
    c1.setNeedsUpdate(); _ = d.read(r2); calls("setC1readR2")
    c2.setNeedsUpdate(); _ = d.read(r1); calls("setC2readR1")
    c1.setNeedsUpdate(); c2.setNeedsUpdate(); _ = d.read(r1); calls("setBothReadR1")
    _ = d.read(r2); calls("readR2noFlag")
    print("shared-context-update-callback|\(log)")
}

/// Same as ``sharedContextUpdateCallback`` but reading an input while both flags are up: native runs no callback on an
/// input read and waits for the next rule read [O].
func sharedContextUpdateCallbackInputRead() {
    let d = Driver()
    let c1 = d.defaultContext
    let c2 = d.makeSharedContext()
    var calls1 = 0, calls2 = 0
    c1.setUpdateCallback { calls1 += 1 }
    c2.setUpdateCallback { calls2 += 1 }
    let sg1 = c1.makeSubgraph()
    let a = d.withSubgraph(sg1) { d.input(Int64(1)) }
    let r1: Handle<Int64> = d.withSubgraph(sg1) { d.rule { d.read(a) + 1 } }
    c1.setNeedsUpdate(); c2.setNeedsUpdate()
    _ = d.read(a)
    let afterInput = "\(calls1),\(calls2)"
    _ = d.read(r1)
    print("shared-context-input-read|afterInput=\(afterInput)|afterRule=\(calls1),\(calls2)")
}

/// Ownership of subgraphs and attributes, `contextThreadUpdating` per context, and invalidation of one context's
/// subgraph with the other alive.
func sharedContextSubgraphs() {
    let d = Driver()
    let c1 = d.defaultContext
    let c2 = d.makeSharedContext()
    let sg1 = c1.makeSubgraph(), sg2 = c2.makeSubgraph()
    let a1 = d.withSubgraph(sg1) { d.input(Int64(1)) }
    let a2 = d.withSubgraph(sg2) { d.input(Int64(2)) }
    let owners = [c1.owns(sg1), c2.owns(sg1), c1.owns(sg2), c2.owns(sg2),
                  c1.owns(a1), c2.owns(a1), c1.owns(a2), c2.owns(a2)]
    var seen: [String] = []
    func probe(_ label: String) {
        let s1 = c1.stateCounters(), s2 = c2.stateCounters()
        seen.append("\(label)=\(s1[2])\(s1[3])\(s2[2])\(s2[3])")
    }
    let t1: Handle<Int64> = d.withSubgraph(sg1) { d.rule { probe("r1"); return 1 } }
    let t2: Handle<Int64> = d.withSubgraph(sg2) { d.rule { probe("r2"); return 2 } }
    _ = d.read(t1); _ = d.read(t2)
    let before = "\(c1.counter(nodes: ()))/\(c2.counter(nodes: ())),\(c1.counter(subgraphs: ()))/\(c2.counter(subgraphs: ()))"
    d.invalidate(sg2)
    let afterSecond = "\(d.isValid(sg1)),\(d.isValid(sg2)),\(d.read(a1)),\(c1.counter(nodes: ()))/\(c2.counter(nodes: ())),\(c1.counter(subgraphs: ()))/\(c2.counter(subgraphs: ()))"
    d.invalidate(sg1)
    let afterFirst = "\(d.isValid(sg1)),\(c1.counter(nodes: ())),\(c1.counter(subgraphs: ()))"
    print("shared-context-subgraphs|owners=\(owners)|updating=\(seen)|before=\(before)|afterSecond=\(afterSecond)|afterFirst=\(afterFirst)")
}
