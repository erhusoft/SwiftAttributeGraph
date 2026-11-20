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
    func setInvalidationCallback(_ body: @escaping (AnyAttribute) -> Void) { graph.onInvalidation(body) }
    func matches<V>(_ raw: AnyAttribute, _ handle: Handle<V>) -> Bool { raw == handle.identifier }
    var userContext: UnsafeRawPointer? {
        get { graph.context }
        set { graph.context = newValue }
    }
    func invalidateContext() { graph.invalidate() }
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
    func setInvalidationCallback(_ body: @escaping (AnyAttribute) -> Void) { context.setInvalidationCallback(body) }
    func matches<V>(_ raw: AnyAttribute, _ handle: Handle<V>) -> Bool { raw == handle.erased }
    var userContext: UnsafeRawPointer? {
        get { context.context }
        set { context.context = newValue }
    }
    func invalidateContext() { context.invalidate() }
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

/// Cross-context invalidation callback (`AGGraphSetInvalidationCallback`) and per-context user pointer
/// (`AGGraphSetContext` / `AGGraphGetContext`).
func sharedContextInvalidationCallback() {
    // (a) AGGraphSetContext / AGGraphGetContext
    var ctxLog: [Bool] = []
    do {
        let d = Driver()
        let c1 = d.defaultContext
        let c2 = d.makeSharedContext()
        ctxLog.append(c1.userContext == nil && c2.userContext == nil)
        var t1: Int64 = 111
        var t2: Int64 = 222
        withUnsafePointer(to: &t1) { p1 in
            withUnsafePointer(to: &t2) { p2 in
                let r1 = UnsafeRawPointer(p1)
                let r2 = UnsafeRawPointer(p2)
                c1.userContext = r1
                ctxLog.append(c1.userContext == r1 && c2.userContext == nil)
                c2.userContext = r2
                ctxLog.append(c1.userContext == r1 && c2.userContext == r2)
                c1.userContext = nil
                ctxLog.append(c1.userContext == nil && c2.userContext == r2)
            }
        }
    }

    // Minimal sequence, counterproofs, (b) argument, (c) callback state & reading, (e) two writes with read between
    var minLog: [String] = []
    var cbStateLog: [String] = []
    do {
        let d = Driver()
        let c1 = d.defaultContext
        let c2 = d.makeSharedContext()
        let sg1 = c1.makeSubgraph()
        let sg2 = c2.makeSubgraph()
        let a = d.withSubgraph(sg1) { d.input(Int64(10)) }
        let r: Handle<Int64> = d.withSubgraph(sg2) { d.rule { d.read(a) + 1 } }
        let r2: Handle<Int64> = d.withSubgraph(sg2) { d.rule { d.read(r) + 1 } }

        var count = 0
        var matchedA = false
        var readR2InCb = false
        c2.setInvalidationCallback { attr in
            count += 1
            matchedA = c2.matches(attr, a)
            let cur = d.currentAttributeState(is: nil as Handle<Int64>?)
            let s1 = c1.stateCounters(), s2 = c2.stateCounters()
            let tu = "\(s1[2])\(s1[3])\(s2[3])"
            let aVal = d.read(a)
            let r2Val = readR2InCb ? d.read(r2) : -1
            cbStateLog.append("cur=\(cur),tu=\(tu),a=\(aVal),r2=\(r2Val)")
        }

        // Write before any read -> 0
        d.write(Int64(11), to: a)
        minLog.append("beforeRead=\(count)")

        // Read r2 once, then write a -> 1 (with origin a)
        _ = d.read(r2)
        d.write(Int64(12), to: a)
        minLog.append("afterReadW1=\(count):\(matchedA)")

        // Second consecutive write without reading -> still 1
        d.write(Int64(13), to: a)
        minLog.append("afterW2NoRead=\(count)")

        // (e) Read r2 between writes, then write a (with readR2InCb = true) -> 2
        _ = d.read(r2)
        readR2InCb = true
        d.write(Int64(14), to: a)
        readR2InCb = false
        minLog.append("afterReadR2W3=\(count)")

        // Write a again without external read (callback read r2 during previous write, matching epoch) -> still 2
        d.write(Int64(15), to: a)
        minLog.append("afterCbReadW4=\(count)")

        // Single-context counterproof
        let ds = Driver()
        var singleCount = 0
        ds.defaultContext.setInvalidationCallback { _ in singleCount += 1 }
        let sa = ds.input(Int64(1))
        let sr1: Handle<Int64> = ds.rule { ds.read(sa) + 1 }
        let sr2: Handle<Int64> = ds.rule { ds.read(sr1) + 1 }
        _ = ds.read(sr2)
        ds.write(Int64(2), to: sa)
        minLog.append("single=\(singleCount)")
    }

    // (c) Inside an update (invalidateValue inside withoutUpdate during rule evaluation)
    var insideUpdateLog = ""
    do {
        let d = Driver()
        let c1 = d.defaultContext
        let c2 = d.makeSharedContext()
        let sg1 = c1.makeSubgraph()
        let sg2 = c2.makeSubgraph()
        let trig = d.withSubgraph(sg1) { d.input(Int64(0)) }
        let srcA = d.withSubgraph(sg1) { d.input(Int64(100)) }
        let aRule: Handle<Int64> = d.withSubgraph(sg1) { d.rule { d.read(srcA) + 1 } }
        let mRule: Handle<Int64> = d.withSubgraph(sg1) {
            d.rule {
                let v = d.read(trig)
                if v > 0 { d.withoutUpdate { d.invalidateValue(of: aRule) } }
                return v
            }
        }
        let cr1: Handle<Int64> = d.withSubgraph(sg2) { d.rule { d.read(aRule) + 1 } }
        let cr2: Handle<Int64> = d.withSubgraph(sg2) { d.rule { d.read(cr1) + 1 } }
        c2.setInvalidationCallback { attr in
            let cur = d.currentAttributeState(is: nil as Handle<Int64>?)
            let s1 = c1.stateCounters(), s2 = c2.stateCounters()
            insideUpdateLog = "match=\(c2.matches(attr, aRule)),cur=\(cur),tu=\(s1[2])\(s1[3])\(s2[3]),src=\(d.read(srcA))"
        }
        _ = d.read(cr2)
        _ = d.read(mRule)
        d.write(Int64(1), to: trig)
        _ = d.read(mRule)
    }

    // (d), (f), (g): Three contexts A -> B -> C, subgraph invalidation, and context invalidation
    var threeLog: [String] = []
    do {
        let d = Driver()
        let c1 = d.defaultContext
        let c2 = d.makeSharedContext()
        let c3 = d.makeSharedContext()
        let sg1 = c1.makeSubgraph()
        let sg2 = c2.makeSubgraph()
        let sg3 = c3.makeSubgraph()
        let a = d.withSubgraph(sg1) { d.input(Int64(10)) }
        let b: Handle<Int64> = d.withSubgraph(sg2) { d.rule { d.read(a) + 1 } }
        let c: Handle<Int64> = d.withSubgraph(sg3) { d.rule { d.read(b) + 1 } }

        var e1 = 0, e2 = 0, e3 = 0
        c1.setInvalidationCallback { _ in e1 += 1 }
        c2.setInvalidationCallback { attr in if c2.matches(attr, a) { e2 += 1 } }
        c3.setInvalidationCallback { attr in
            if c3.matches(attr, a) { e3 += 10 }
            else if c3.matches(attr, b) { e3 += 100 }
        }

        // Without output on C: only c2 receives A
        _ = d.read(c)
        d.write(Int64(20), to: a)
        threeLog.append("noOutC=\(e1),\(e2),\(e3)")

        // With output on C: both c2 and c3 receive A
        let cOut: Handle<Int64> = d.withSubgraph(sg3) { d.rule { d.read(c) + 1 } }
        _ = d.read(cOut)
        d.write(Int64(30), to: a)
        threeLog.append("withOutC=\(e1),\(e2),\(e3)")

        // Invalidate b in c2: only c3 receives B (+100)
        _ = d.read(cOut)
        d.invalidateValue(of: b)
        threeLog.append("fromB=\(e1),\(e2),\(e3)")

        // (f) Invalidate sg3 and write a
        _ = d.read(cOut)
        d.invalidate(sg3)
        d.write(Int64(40), to: a)
        threeLog.append("afterInvSg3=\(e1),\(e2),\(e3)")

        // (g) Add output on b in sg2, read it, invalidate context 2, and write a
        let bOut: Handle<Int64> = d.withSubgraph(sg2) { d.rule { d.read(b) + 1 } }
        _ = d.read(bOut)
        d.write(Int64(50), to: a)
        threeLog.append("beforeInvCtx2=\(e2)")
        _ = d.read(bOut)
        c2.invalidateContext()
        d.write(Int64(60), to: a)
        threeLog.append("afterInvCtx2=\(e2),sg2Valid=\(d.isValid(sg2))")
    }

    print("shared-context-invalidation-callback|ctx=\(ctxLog)|min=\(minLog)|cbState=\(cbStateLog)|inside=\(insideUpdateLog)|three=\(threeLog)")
}
