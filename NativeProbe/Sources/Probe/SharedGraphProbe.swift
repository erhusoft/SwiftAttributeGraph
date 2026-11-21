#if NATIVE_ATTRIBUTE_GRAPH
import AttributeGraph
import Darwin

/// `AGGraphCreateShared(graph)`: a new reference over the same graph state (AGGraphCreateShared in AGGraph.h).
@_silgen_name("AGGraphCreateShared")
private func c_AGGraphCreateShared(_ graph: AttributeGraph.Graph?) -> AttributeGraph.Graph

@_silgen_name("AGSubgraphGetCurrentGraphContext")
private func c_shareGraphContext() -> UnsafeRawPointer?

/// `Probe share-probe`: behaviour of a shared graph reference, measured against the graph it shares.
/// Prints one line per question. Identity is the raw reference bits.
func runSharedGraphProbeIfRequested() {
    guard CommandLine.arguments.count > 1, CommandLine.arguments[1] == "share-probe" else { return }
    let d = Driver()
    let shared = c_AGGraphCreateShared(d.graph)
    let sharedRoot = AttributeGraph.Subgraph(graph: shared)
    let rawA = unsafeBitCast(d.graph, to: UnsafeRawPointer.self)
    let rawB = unsafeBitCast(shared, to: UnsafeRawPointer.self)
    print("share|sameReferenceBits=\(rawA == rawB)")

    // 1. Visibility: an input in the first graph, read by a rule in the shared reference.
    let input: Handle<Int64> = d.input(7)
    let reader: Handle<Int64> = sharedRoot.apply { Handle(NativeRule(body: { input.value })) }
    print("share|readFromShared=\(reader.value)")
    d.write(9, to: input)
    print("share|afterWriteInFirst=\(reader.value)")

    // 2. Counters: nodes counted by each reference.
    print("share|nodesFirst=\(d.graph.counter(for: .nodes))|nodesShared=\(shared.counter(for: .nodes))")

    // 3. Invalidation callbacks: installed on each reference; a write, then a read of the reader in the shared reference.
    var firstCalls = 0
    var sharedCalls = 0
    d.graph.onInvalidation { _ in firstCalls += 1 }
    shared.onInvalidation { _ in sharedCalls += 1 }
    _ = reader.value
    d.write(10, to: input)
    _ = reader.value
    d.write(11, to: input)
    _ = reader.value
    print("share|invalidationFirst=\(firstCalls)|invalidationShared=\(sharedCalls)|readAfterLast=\(reader.value)")

    // 4. Context identity: the context of the current subgraph in each reference.
    let ctxFirst = d.currentSubgraph.apply { c_shareGraphContext() }
    let ctxShared = sharedRoot.apply { c_shareGraphContext() }
    print("share|contextFirst=\(String(describing: ctxFirst))|contextShared=\(String(describing: ctxShared))|sameContext=\(ctxFirst == ctxShared)")
    exit(0)
}

/// `Probe share-life`: the shared reference after the first graph's driver is closed.
func runSharedGraphLifeProbeIfRequested() {
    guard CommandLine.arguments.count > 1, CommandLine.arguments[1] == "share-life" else { return }
    var d: Driver? = Driver()
    let shared = c_AGGraphCreateShared(d!.graph)
    let sharedRoot = AttributeGraph.Subgraph(graph: shared)
    let input: Handle<Int64> = d!.input(3)
    let reader: Handle<Int64> = sharedRoot.apply { Handle(NativeRule(body: { input.value })) }
    print("life|beforeClose=\(reader.value)")
    d = nil
    print("life|afterFirstClosed=\(reader.value)")
    exit(0)
}
#endif

#if NATIVE_ATTRIBUTE_GRAPH
/// `Probe share-ctx`: the oracle's own shared-context topology (a shared context made with `makeSharedContext`, a rule in
/// it reading an input of the default context, a callback on the shared context). Counts notices per context, and checks
/// that the two contexts hold different user pointers.
func runSharedContextTopologyProbeIfRequested() {
    guard CommandLine.arguments.count > 1, CommandLine.arguments[1] == "share-ctx" else { return }
    let d = Driver()
    let c1 = d.defaultContext
    let c2 = d.makeSharedContext()
    let sg1 = c1.makeSubgraph()
    let sg2 = c2.makeSubgraph()
    var pointer: Int64 = 111
    withUnsafePointer(to: &pointer) { p in
        c1.userContext = UnsafeRawPointer(p)
    }
    print("ctx|c2UserContextAfterSettingC1=\(String(describing: c2.userContext))")
    c1.userContext = nil

    let a: Handle<Int64> = d.withSubgraph(sg1) { d.input(Int64(10)) }
    let b: Handle<Int64> = d.withSubgraph(sg2) { d.rule { d.read(a) + 1 } }
    var notices = 0
    c2.setInvalidationCallback { _ in notices += 1 }

    _ = d.read(b)
    d.write(Int64(20), to: a)
    print("ctx|noticeAfterWriteWithoutRead=\(notices)")
    _ = d.read(b)
    d.write(Int64(30), to: a)
    print("ctx|noticeAfterReadAndWrite=\(notices)")
    _ = d.read(b)
    print("ctx|readValue=\(d.read(b))|noticesFinal=\(notices)")
    exit(0)
}
#endif

#if NATIVE_ATTRIBUTE_GRAPH
/// `Probe share-fault <case>`: one deliberate misuse of AGGraphCreateShared per process. The exit status and the message
/// (stderr) are the result. Cases: nil, shared-of-shared, shared-after-first-freed, read-after-first-freed.
func runSharedGraphFaultProbeIfRequested() {
    guard CommandLine.arguments.count > 2, CommandLine.arguments[1] == "share-fault" else { return }
    switch CommandLine.arguments[2] {
    case "nil":
        let s = c_AGGraphCreateShared(nil)
        print("fault|nil|nodes=\(s.counter(for: .nodes))")
    case "shared-of-shared":
        let d = Driver()
        let s1 = c_AGGraphCreateShared(d.graph)
        let s2 = c_AGGraphCreateShared(s1)
        print("fault|shared-of-shared|nodes=\(s2.counter(for: .nodes))")
    case "shared-after-first-freed":
        var d: Driver? = Driver()
        let s = c_AGGraphCreateShared(d!.graph)
        d = nil
        let s2 = c_AGGraphCreateShared(s)
        print("fault|shared-after-first-freed|nodes=\(s2.counter(for: .nodes))")
    case "read-after-first-freed":
        var d: Driver? = Driver()
        let shared = c_AGGraphCreateShared(d!.graph)
        let root = AttributeGraph.Subgraph(graph: shared)
        let input: Handle<Int64> = d!.input(3)
        let reader: Handle<Int64> = root.apply { Handle(NativeRule(body: { input.value })) }
        d = nil
        print("fault|read-after-first-freed|value=\(reader.value)")
    default:
        exit(2)
    }
    exit(0)
}
#endif

#if NATIVE_ATTRIBUTE_GRAPH
/// `Probe share-stress <count>` and `Probe share-depth <count>`: many shared handles from one graph, and a chain of
/// shared-of-shared handles. Prints the time and whether the first handle still reads.
func runSharedGraphStressProbeIfRequested() {
    guard CommandLine.arguments.count > 2 else { return }
    let mode = CommandLine.arguments[1]
    if mode == "share-count", let n = Int(CommandLine.arguments[2]) {
        let d = Driver()
        var keep: [AttributeGraph.Graph] = []
        for _ in 0..<n { keep.append(c_AGGraphCreateShared(d.graph)) }
        print("share-count|created=\(keep.count)")
        exit(0)
    }
    if mode == "graphs-independent", let n = Int(CommandLine.arguments[2]) {
        let start = ContinuousClock.now
        var graphs: [AttributeGraph.Graph] = []
        for _ in 0..<n { graphs.append(AttributeGraph.Graph()) }
        print("graphs-independent|n=\(n)|time=\(start.duration(to: ContinuousClock.now))|count=\(graphs.count)")
        exit(0)
    }
    guard mode == "share-stress" || mode == "share-depth", let n = Int(CommandLine.arguments[2]) else { return }
    let d = Driver()
    let input: Handle<Int64> = d.input(5)
    let start = ContinuousClock.now
    var last = d.graph
    var handles: [AttributeGraph.Graph] = []
    for _ in 0..<n {
        let next = c_AGGraphCreateShared(mode == "share-depth" ? last : d.graph)
        if mode == "share-stress" { handles.append(next) }
        last = next
    }
    let elapsed = start.duration(to: ContinuousClock.now)
    let root = AttributeGraph.Subgraph(graph: last)
    let reader: Handle<Int64> = root.apply { Handle(NativeRule(body: { input.value })) }
    print("\(mode)|n=\(n)|time=\(elapsed)|lastReads=\(reader.value)")
    exit(0)
}
#endif
