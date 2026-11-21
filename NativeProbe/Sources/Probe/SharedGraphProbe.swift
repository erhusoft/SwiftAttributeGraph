#if NATIVE_ATTRIBUTE_GRAPH
import AttributeGraph
import Darwin

@_silgen_name("CFGetTypeID")
private func c_CFGetTypeID(_ object: UnsafeRawPointer) -> UInt

@_silgen_name("AGGraphGetTypeID")
private func c_AGGraphGetTypeID() -> UInt

@_silgen_name("CFGetRetainCount")
private func c_CFGetRetainCount(_ object: UnsafeRawPointer) -> Int

@_silgen_name("CFRetain")
private func c_CFRetain(_ object: UnsafeRawPointer) -> UnsafeRawPointer

@_silgen_name("CFRelease")
private func c_CFRelease(_ object: UnsafeRawPointer)

/// `AGGraphCreateShared(graph)`: a new reference over the same graph state (AGGraphCreateShared in AGGraph.h).
@_silgen_name("AGGraphCreateShared")
private func c_AGGraphCreateShared(_ graph: AttributeGraph.Graph?) -> AttributeGraph.Graph

@_silgen_name("AGSubgraphGetCurrentGraphContext")
private func c_shareGraphContext() -> UnsafeRawPointer?

@_silgen_name("AGGraphHasValue")
private func c_AGGraphHasValue(_ attr: UInt32) -> Bool

@_silgen_name("AGGraphGetAttributeGraph")
private func c_AGGraphGetAttributeGraph(_ attr: UInt32) -> UnsafeRawPointer?

@_silgen_name("AGGraphGetContext")
private func c_AGGraphGetContext_raw(_ graph: UnsafeRawPointer) -> UnsafeRawPointer?

@_silgen_name("AGGraphSetContext")
private func c_AGGraphSetContext_raw(_ graph: UnsafeRawPointer, _ context: UnsafeRawPointer?)

@_silgen_name("AGGraphSetNeedsUpdate")
private func c_AGGraphSetNeedsUpdate(_ graph: AttributeGraph.Graph)

@_silgen_name("AGGraphSetUpdateCallback")
private func c_AGGraphSetUpdateCallback(_ graph: AttributeGraph.Graph, _ fn: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?, _ ctx: UnsafeMutableRawPointer?)

@_silgen_name("AGSubgraphUpdate")
private func c_AGSubgraphUpdate(_ subgraph: AttributeGraph.Subgraph, _ flags: UInt32)

@_silgen_name("AGGraphSetUpdate")
private func c_AGGraphSetUpdate(_ update: UnsafeRawPointer?)

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
    guard CommandLine.arguments.count > 1 else { return }
    let mode = CommandLine.arguments[1]
    if mode == "two-hosts" {
        let g1 = Driver()
        let g2 = Driver()
        let a1: Handle<Int64> = g1.input(10)
        let a2: Handle<Int64> = g2.input(20)
        let s1 = c_AGGraphCreateShared(g1.graph)
        let s2 = c_AGGraphCreateShared(g2.graph)
        let root1 = AttributeGraph.Subgraph(graph: s1)
        let root2 = AttributeGraph.Subgraph(graph: s2)
        let r1: Handle<Int64> = root1.apply { Handle(NativeRule(body: { a1.value })) }
        let r2: Handle<Int64> = root2.apply { Handle(NativeRule(body: { a2.value })) }
        print("two-hosts|s1ReadsG1=\(r1.value)|s2ReadsG2=\(r2.value)|nodesS1=\(s1.counter(for: .nodes))|nodesS2=\(s2.counter(for: .nodes))|nodesG1=\(g1.graph.counter(for: .nodes))|nodesG2=\(g2.graph.counter(for: .nodes))")
        fflush(stdout)
        exit(0)
    }
    if mode == "two-hosts-cross" {
        let g1 = Driver()
        let g2 = Driver()
        let a2: Handle<Int64> = g2.input(20)
        let s1 = c_AGGraphCreateShared(g1.graph)
        let root1 = AttributeGraph.Subgraph(graph: s1)
        let cross: Handle<Int64> = root1.apply { Handle(NativeRule(body: { a2.value })) }
        print("two-hosts-cross|s1ReadsG2=\(cross.value)")
        fflush(stdout)
        exit(0)
    }
    if mode == "inherit" {
        let g = Driver()
        let a: Handle<Int64> = g.input(1)
        let shared = c_AGGraphCreateShared(g.graph)
        let sRoot = AttributeGraph.Subgraph(graph: shared)
        let seesA: Handle<Int64> = sRoot.apply { Handle(NativeRule(body: { a.value })) }
        print("inherit|sharedSeesOlderInput=\(seesA.value)|nodesGraph=\(g.graph.counter(for: .nodes))|nodesShared=\(shared.counter(for: .nodes))")
        let b: Handle<Int64> = g.input(2)
        let seesB: Handle<Int64> = sRoot.apply { Handle(NativeRule(body: { b.value })) }
        print("inherit|sharedSeesNewerInputFromGraph=\(seesB.value)")
        let c: Handle<Int64> = sRoot.apply { Handle(NativeRule(body: { 3 })) }
        let graphSeesC: Handle<Int64> = g.apply(g.scope) { Handle(NativeRule(body: { c.value })) }
        print("inherit|graphSeesSharedAttribute=\(graphSeesC.value)|nodesGraphAfter=\(g.graph.counter(for: .nodes))|nodesSharedAfter=\(shared.counter(for: .nodes))")
        fflush(stdout)
        exit(0)
    }
    if mode == "independent-read" {
        let first = Driver()
        let second = Driver()
        let input: Handle<Int64> = first.input(5)
        let reader: Handle<Int64> = second.apply(second.scope) { Handle(NativeRule(body: { input.value })) }
        print("independent|readAcrossGraphs=\(reader.value)")
        fflush(stdout)
        exit(0)
    }
    if mode == "share-retain" {
        let d = Driver()
        var a: AttributeGraph.Graph? = c_AGGraphCreateShared(d.graph)
        let rawA = unsafeBitCast(a!, to: UnsafeRawPointer.self)
        print("share-retain|sizeOfGraph=\(MemoryLayout<AttributeGraph.Graph>.size)|cfTypeIdOfA=\(c_CFGetTypeID(rawA))|agGraphTypeId=\(c_AGGraphGetTypeID())|rawA=\(rawA)")
        fflush(stdout)
        let rc0 = c_CFGetRetainCount(rawA)
        let b = c_AGGraphCreateShared(d.graph)
        let rawB = unsafeBitCast(b, to: UnsafeRawPointer.self)
        let rc1 = c_CFGetRetainCount(rawA)
        let rcB = c_CFGetRetainCount(rawB)
        a = nil
        let rc2 = c_CFGetRetainCount(rawB)
        if CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "release-a" {
            let before = rawB.load(fromByteOffset: 0x20, as: UInt32.self)
            c_CFRelease(rawA)
            fflush(stdout)
            print("share-retain|counterBeforeCFRelease=\(before)|counterAfterCFRelease=\(rawB.load(fromByteOffset: 0x20, as: UInt32.self))|rcOfB=\(c_CFGetRetainCount(rawB))")
            fflush(stdout)
            exit(0)
        }
        print("share-retain|rcOfAAfterCreate=\(rc0)|rcOfAAfterSecondCreate=\(rc1)|rcOfB=\(rcB)|rcOfBAfterDroppingA=\(rc2)")
        fflush(stdout)
        exit(0)
    }
    if mode == "share-release" {
        let d = Driver()
        var a: AttributeGraph.Graph? = c_AGGraphCreateShared(d.graph)
        let rawA = unsafeBitCast(a!, to: UnsafeRawPointer.self)
        let b = c_AGGraphCreateShared(d.graph)
        let rawB = unsafeBitCast(b, to: UnsafeRawPointer.self)
        let beforeRelease = rawB.load(fromByteOffset: 0x20, as: UInt32.self)
        a = nil
        let afterSwiftDrop = rawB.load(fromByteOffset: 0x20, as: UInt32.self)
        print("share-release|cfRefcountOfA=\(rawA.load(fromByteOffset: 8, as: UInt32.self))")
        fflush(stdout)
        c_CFRelease(rawA)
        let afterRelease = rawB.load(fromByteOffset: 0x20, as: UInt32.self)
        print("share-release|afterSwiftDrop=\(afterSwiftDrop)")
        fflush(stdout)
        let stillReads = b.counter(for: .nodes)
        print("share-release|counterBeforeRelease=\(beforeRelease)|counterAfterRelease=\(afterRelease)|rawA=\(rawA)|stateOfB=\(rawB.load(fromByteOffset: 0x10, as: UInt.self))|nodesOfB=\(stillReads)")
        exit(0)
    }
    if mode == "share-count", CommandLine.arguments.count > 2, let n = Int(CommandLine.arguments[2]) {
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
    guard mode == "share-stress" || mode == "share-depth", CommandLine.arguments.count > 2, let n = Int(CommandLine.arguments[2]) else { return }
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

#if NATIVE_ATTRIBUTE_GRAPH
@_silgen_name("AGGraphInvalidate")
private func c_AGGraphInvalidate(_ graph: UnsafeRawPointer)

/// `Probe share-lifetime <case>`: measures native lifetime, ownership, and release rules.
func runSharedGraphLifetimeProbeIfRequested() {
    guard CommandLine.arguments.count > 2, CommandLine.arguments[1] == "share-lifetime" else { return }
    let subcase = CommandLine.arguments[2]
    switch subcase {
    case "case1":
        // Case 1: Create graph, create shared handle, evaluate a node, release original (Swift), read from shared.
        var d: Driver? = Driver()
        let shared = c_AGGraphCreateShared(d!.graph)
        let input: Handle<Int64> = d!.input(42)
        let root = AttributeGraph.Subgraph(graph: shared)
        let reader: Handle<Int64> = root.apply { Handle(NativeRule(body: { input.value })) }
        let evaluatedValue = reader.value
        d = nil // release original Swift Graph
        let readAfterDrop = reader.value
        print("case1|evaluatedBefore=\(evaluatedValue)|readAfter=\(readAfterDrop)")
        fflush(stdout)
        exit(0)

    case "case2":
        // Case 2: Same as case 1, but without evaluating the node before releasing the original.
        var d: Driver? = Driver()
        let shared = c_AGGraphCreateShared(d!.graph)
        let input: Handle<Int64> = d!.input(99)
        let root = AttributeGraph.Subgraph(graph: shared)
        let reader: Handle<Int64> = root.apply { Handle(NativeRule(body: { input.value })) }
        d = nil // release original Swift Graph WITHOUT evaluating reader first
        // Attempting to evaluate reader after the original was released without evaluation:
        let readAfterDrop = reader.value
        print("case2|unexpectedSuccess=\(readAfterDrop)")
        fflush(stdout)
        exit(0)

    case "case3a":
        // Case 3a: Shared-of-shared, order: release g1, then s1, read from s2.
        var g1: Driver? = Driver()
        let input: Handle<Int64> = g1!.input(101)
        var s1: AttributeGraph.Graph? = c_AGGraphCreateShared(g1!.graph)
        let s2 = c_AGGraphCreateShared(s1!)
        let root = AttributeGraph.Subgraph(graph: s2)
        let reader: Handle<Int64> = root.apply { Handle(NativeRule(body: { input.value })) }
        _ = reader.value
        g1 = nil
        let afterG1 = reader.value
        s1 = nil
        let afterS1 = reader.value
        print("case3a|afterG1Drop=\(afterG1)|afterS1Drop=\(afterS1)")
        fflush(stdout)
        exit(0)

    case "case3b":
        // Case 3b: Shared-of-shared, order: release s1 first, then g1, read from s2.
        var g1: Driver? = Driver()
        let input: Handle<Int64> = g1!.input(202)
        var s1: AttributeGraph.Graph? = c_AGGraphCreateShared(g1!.graph)
        let s2 = c_AGGraphCreateShared(s1!)
        let root = AttributeGraph.Subgraph(graph: s2)
        let reader: Handle<Int64> = root.apply { Handle(NativeRule(body: { input.value })) }
        _ = reader.value
        s1 = nil
        let afterS1 = reader.value
        g1 = nil
        let afterG1 = reader.value
        print("case3b|afterS1Drop=\(afterS1)|afterG1Drop=\(afterG1)")
        fflush(stdout)
        exit(0)

    case "case4":
        // Case 4: Measure when +0x20 changes (if at all) and when state refcount (+0x1a4) changes.
        var g1: Driver? = Driver()
        let rawG1 = unsafeBitCast(g1!.graph, to: UnsafeRawPointer.self)
        let stateG1 = rawG1.advanced(by: 0x10).load(as: UnsafeRawPointer.self)
        let idG1 = rawG1.advanced(by: 0x20).load(as: UInt32.self)
        let ref0 = stateG1.advanced(by: 0x1a4).load(as: UInt32.self)

        var s1: AttributeGraph.Graph? = c_AGGraphCreateShared(g1!.graph)
        let rawS1 = unsafeBitCast(s1!, to: UnsafeRawPointer.self)
        let idS1 = rawS1.advanced(by: 0x20).load(as: UInt32.self)
        let ref1 = stateG1.advanced(by: 0x1a4).load(as: UInt32.self)

        var s2: AttributeGraph.Graph? = c_AGGraphCreateShared(s1!)
        let rawS2 = unsafeBitCast(s2!, to: UnsafeRawPointer.self)
        let idS2 = rawS2.advanced(by: 0x20).load(as: UInt32.self)
        let ref2 = stateG1.advanced(by: 0x1a4).load(as: UInt32.self)

        // Drop s2 in Swift
        s2 = nil
        let refAfterS2SwiftDrop = stateG1.advanced(by: 0x1a4).load(as: UInt32.self)
        let idS1AfterS2Drop = rawS1.advanced(by: 0x20).load(as: UInt32.self)

        // Invalidate s1 explicitly
        c_AGGraphInvalidate(rawS1)
        let refAfterS1Invalidate = stateG1.advanced(by: 0x1a4).load(as: UInt32.self)

        // Invalidate g1 explicitly
        c_AGGraphInvalidate(rawG1)
        let refAfterG1Invalidate = stateG1.advanced(by: 0x1a4).load(as: UInt32.self)

        print("case4|idG1=\(idG1)|idS1=\(idS1)|idS2=\(idS2)|ref0=\(ref0)|ref1=\(ref1)|ref2=\(ref2)|refAfterS2SwiftDrop=\(refAfterS2SwiftDrop)|idS1AfterS2Drop=\(idS1AfterS2Drop)|refAfterS1Invalidate=\(refAfterS1Invalidate)|refAfterG1Invalidate=\(refAfterG1Invalidate)")
        fflush(stdout)
        exit(0)

    case "case5":
        // Case 5: Mechanism of release: AGGraphInvalidate cleans Context, decrements state +0x1a4,
        // and when reaching 0 triggers destructor of AG::Graph and frees state memory.
        let d = Driver()
        let rawG = unsafeBitCast(d.graph, to: UnsafeRawPointer.self)
        let state = rawG.advanced(by: 0x10).load(as: UnsafeRawPointer.self)
        let s = c_AGGraphCreateShared(d.graph)
        let rawS = unsafeBitCast(s, to: UnsafeRawPointer.self)
        let invFlagBefore = rawS.advanced(by: 0x58).load(as: UInt8.self)
        let refBefore = state.advanced(by: 0x1a4).load(as: UInt32.self)

        c_AGGraphInvalidate(rawS)
        let invFlagAfter = rawS.advanced(by: 0x58).load(as: UInt8.self)
        let refAfter = state.advanced(by: 0x1a4).load(as: UInt32.self)

        // Second invalidate on rawS is idempotent (no-op)
        c_AGGraphInvalidate(rawS)
        let refAfterDouble = state.advanced(by: 0x1a4).load(as: UInt32.self)

        print("case5|invFlagBefore=\(invFlagBefore)|invFlagAfter=\(invFlagAfter)|refBefore=\(refBefore)|refAfter=\(refAfter)|refAfterDouble=\(refAfterDouble)")
        fflush(stdout)
        exit(0)

    case "round4-retained":
        let d = Driver()
        var a: AttributeGraph.Graph? = c_AGGraphCreateShared(d.graph)
        let rawA = unsafeBitCast(a!, to: UnsafeRawPointer.self)
        let rcInitial = c_CFGetRetainCount(rawA)
        _ = c_CFRetain(rawA)
        let rcAfterRetain = c_CFGetRetainCount(rawA)
        a = nil
        let rcAfterARCDrop = c_CFGetRetainCount(rawA)
        c_CFRelease(rawA)
        print("round4-retained|rcInitial=\(rcInitial)|rcAfterRetain=\(rcAfterRetain)|rcAfterARCDrop=\(rcAfterARCDrop)")
        fflush(stdout)
        exit(0)

    case "round4-unretained":
        let d = Driver()
        var a: AttributeGraph.Graph? = c_AGGraphCreateShared(d.graph)
        let rawA = unsafeBitCast(a!, to: UnsafeRawPointer.self)
        let rcInitial = c_CFGetRetainCount(rawA)
        a = nil
        // Without CFRetain, rawA is freed memory. Documenting that reading it is invalid:
        print("round4-unretained|rcInitial=\(rcInitial)|afterDropMemoryIsFreed=true")
        fflush(stdout)
        exit(0)

    case "round5-case-a":
        // Case A (control of failure): create A with AGGraphCreateShared, save rawA, execute a = nil without CFRetain, then call CFRelease(rawA)
        let d = Driver()
        var a: AttributeGraph.Graph? = c_AGGraphCreateShared(d.graph)
        let rawA = unsafeBitCast(a!, to: UnsafeRawPointer.self)
        a = nil
        print("round5-case-a|aboutToCallCFRelease=true")
        fflush(stdout)
        c_CFRelease(rawA)
        print("round5-case-a|unexpectedSuccess=true")
        fflush(stdout)
        exit(0)

    case "round5-case-b":
        // Case B (contrast): create A with AGGraphCreateShared, save rawA, call CFRelease(rawA) without a = nil
        let d = Driver()
        let a: AttributeGraph.Graph = c_AGGraphCreateShared(d.graph)
        let rawA = unsafeBitCast(a, to: UnsafeRawPointer.self)
        c_CFRelease(rawA)
        print("round5-case-b|cfReleaseCompleted=true")
        fflush(stdout)
        exit(0)

    case "round5-case-c":
        // Case C (contrast with ARC and retain): create A, CFRetain(rawA), a = nil, CFRelease(rawA)
        let d = Driver()
        var a: AttributeGraph.Graph? = c_AGGraphCreateShared(d.graph)
        let rawA = unsafeBitCast(a!, to: UnsafeRawPointer.self)
        _ = c_CFRetain(rawA)
        a = nil
        c_CFRelease(rawA)
        print("round5-case-c|cleanCompletion=true")
        fflush(stdout)
        exit(0)

    case "probe-58":
        // Measure byte at +0x58
        let d = Driver()
        let s = c_AGGraphCreateShared(d.graph)
        let rawS = unsafeBitCast(s, to: UnsafeRawPointer.self)
        let byteCreated = rawS.advanced(by: 0x58).load(as: UInt8.self)
        c_AGGraphInvalidate(rawS)
        let byteInvalidated = rawS.advanced(by: 0x58).load(as: UInt8.self)
        c_AGGraphInvalidate(rawS)
        let byteDoubleInvalidated = rawS.advanced(by: 0x58).load(as: UInt8.self)
        print("probe-58|created=\(byteCreated)|invalidated=\(byteInvalidated)|doubleInvalidated=\(byteDoubleInvalidated)")
        fflush(stdout)
        exit(0)

    case "two-hosts-step1":
        // Step 1: Single Driver
        let g1 = Driver()
        let a1: Handle<Int64> = g1.input(10)
        print("step1|a1=\(a1.value)")
        fflush(stdout)
        exit(0)

    case "two-hosts-step2":
        // Step 2: Driver + shared handle of that driver
        let g1 = Driver()
        let a1: Handle<Int64> = g1.input(10)
        let s1 = c_AGGraphCreateShared(g1.graph)
        let r1: Handle<Int64> = AttributeGraph.Subgraph(graph: s1).apply { Handle(NativeRule(body: { a1.value })) }
        print("step2|r1=\(r1.value)")
        fflush(stdout)
        exit(0)

    case "two-hosts-step3":
        // Step 3: Two Drivers alive at the same time, reading each its own input
        let g1 = Driver()
        let a1: Handle<Int64> = g1.input(10)
        let g2 = Driver()
        let a2: Handle<Int64> = g2.input(20)
        print("step3|a1=\(a1.value)|a2=\(a2.value)")
        fflush(stdout)
        exit(0)

    case "two-hosts-step4":
        // Step 4: Two Drivers with shared handles each, creating r1 in s1 and r2 in s2
        let g1 = Driver()
        let a1: Handle<Int64> = g1.input(10)
        let s1 = c_AGGraphCreateShared(g1.graph)
        let root1 = AttributeGraph.Subgraph(graph: s1)
        let r1: Handle<Int64> = root1.apply { Handle(NativeRule(body: { a1.value })) }
        let g2 = Driver()
        let a2: Handle<Int64> = g2.input(20)
        let s2 = c_AGGraphCreateShared(g2.graph)
        let root2 = AttributeGraph.Subgraph(graph: s2)
        let r2: Handle<Int64> = root2.apply { Handle(NativeRule(body: { a2.value })) }
        print("step4|r1=\(r1.value)|r2=\(r2.value)")
        fflush(stdout)
        exit(0)

    case "two-hosts-step4-order":
        // Test step 4 evaluating r1 BEFORE creating g2/s2
        let g1 = Driver()
        let a1: Handle<Int64> = g1.input(10)
        let s1 = c_AGGraphCreateShared(g1.graph)
        let root1 = AttributeGraph.Subgraph(graph: s1)
        let r1: Handle<Int64> = root1.apply { Handle(NativeRule(body: { a1.value })) }
        let val1 = r1.value
        let g2 = Driver()
        let a2: Handle<Int64> = g2.input(20)
        let s2 = c_AGGraphCreateShared(g2.graph)
        let root2 = AttributeGraph.Subgraph(graph: s2)
        let r2: Handle<Int64> = root2.apply { Handle(NativeRule(body: { a2.value })) }
        let val2 = r2.value
        print("step4-order|r1=\(val1)|r2=\(val2)")
        fflush(stdout)
        exit(0)

    case "two-hosts-orig":
        // The exact code of the original two-hosts in runSharedGraphStressProbeIfRequested
        let g1 = Driver()
        let g2 = Driver()
        let a1: Handle<Int64> = g1.input(10)
        let a2: Handle<Int64> = g2.input(20)
        let s1 = c_AGGraphCreateShared(g1.graph)
        let s2 = c_AGGraphCreateShared(g2.graph)
        let r1: Handle<Int64> = AttributeGraph.Subgraph(graph: s1).apply { Handle(NativeRule(body: { a1.value })) }
        let r2: Handle<Int64> = AttributeGraph.Subgraph(graph: s2).apply { Handle(NativeRule(body: { a2.value })) }
        print("two-hosts-orig|s1ReadsG1=\(r1.value)|s2ReadsG2=\(r2.value)")
        fflush(stdout)
        exit(0)

    case "e0-storage":
        let g1 = AttributeGraph.Graph()
        let g2 = AttributeGraph.Graph()
        let rawA = unsafeBitCast(g1, to: UnsafeRawPointer.self)
        let rawB = unsafeBitCast(g2, to: UnsafeRawPointer.self)
        let storageA = rawA.advanced(by: 0x10).load(as: UnsafeRawPointer.self)
        let storageB = rawB.advanced(by: 0x10).load(as: UnsafeRawPointer.self)

        let s = c_AGGraphCreateShared(g1)
        let rawS = unsafeBitCast(s, to: UnsafeRawPointer.self)
        let storageS = rawS.advanced(by: 0x10).load(as: UnsafeRawPointer.self)

        print("e0|rawA=\(rawA)|storageA=\(storageA)|rawB=\(rawB)|storageB=\(storageB)|different=\(storageA != storageB)")
        print("e0|positiveControl|rawS=\(rawS)|storageS=\(storageS)|sameAsA=\(storageS == storageA)")
        fflush(stdout)
        exit(0)

    case "e1-c1":
        // c1: Evaluated=yes (rule evaluated before share) | G alive | Read via G
        setbuf(stdout, nil)
        var g: Driver? = Driver()
        let rawG = unsafeBitCast(g!.graph, to: UnsafeRawPointer.self)
        let rule: Handle<Int64> = g!.rule { 7 }
        _ = g!.read(rule)
        let hasVal = c_AGGraphHasValue(rule.identifier.rawValue)
        let s = c_AGGraphCreateShared(g!.graph)
        let rawS = unsafeBitCast(s, to: UnsafeRawPointer.self)
        let storageG = rawG.advanced(by: 0x10).load(as: UnsafeRawPointer.self)
        let storageS = rawS.advanced(by: 0x10).load(as: UnsafeRawPointer.self)
        let owner = c_AGGraphGetAttributeGraph(rule.identifier.rawValue)
        let ownerLabel = (owner == rawG) ? "G" : ((owner == rawS) ? "S" : "unknown")
        print("e1-case|cell=c1|evaluatedInG=yes|gAlive=yes|readVia=G")
        print("hasValueBeforeShare=\(hasVal ? "yes" : "no")")
        print("storageG=\(storageG)|storageS=\(storageS)|sameStorage=\(storageG == storageS)")
        print("owner=\(ownerLabel)|ownerHandle=\(String(describing: owner))|rawG=\(rawG)|rawS=\(rawS)")
        print("aboutToRead=true")
        let val = g!.read(rule)
        print("value=\(val)")
        exit(0)

    case "e1-c2":
        // c2: Evaluated=yes (rule evaluated before share) | G alive | Read via S
        setbuf(stdout, nil)
        var g: Driver? = Driver()
        let rawG = unsafeBitCast(g!.graph, to: UnsafeRawPointer.self)
        let rule: Handle<Int64> = g!.rule { 7 }
        _ = g!.read(rule)
        let hasVal = c_AGGraphHasValue(rule.identifier.rawValue)
        let s = c_AGGraphCreateShared(g!.graph)
        let rawS = unsafeBitCast(s, to: UnsafeRawPointer.self)
        let sRoot = AttributeGraph.Subgraph(graph: s)
        let storageG = rawG.advanced(by: 0x10).load(as: UnsafeRawPointer.self)
        let storageS = rawS.advanced(by: 0x10).load(as: UnsafeRawPointer.self)
        let owner = c_AGGraphGetAttributeGraph(rule.identifier.rawValue)
        let ownerLabel = (owner == rawG) ? "G" : ((owner == rawS) ? "S" : "unknown")
        print("e1-case|cell=c2|evaluatedInG=yes|gAlive=yes|readVia=S")
        print("hasValueBeforeShare=\(hasVal ? "yes" : "no")")
        print("storageG=\(storageG)|storageS=\(storageS)|sameStorage=\(storageG == storageS)")
        print("owner=\(ownerLabel)|ownerHandle=\(String(describing: owner))|rawG=\(rawG)|rawS=\(rawS)")
        print("aboutToRead=true")
        let reader: Handle<Int64> = sRoot.apply { Handle(NativeRule(body: { rule.value })) }
        print("value=\(reader.value)")
        exit(0)

    case "e1-c3":
        // c3: Evaluated=no (rule NOT read before share) | G alive | Read via G
        setbuf(stdout, nil)
        var g: Driver? = Driver()
        let rawG = unsafeBitCast(g!.graph, to: UnsafeRawPointer.self)
        let rule: Handle<Int64> = g!.rule { 7 }
        let hasVal = c_AGGraphHasValue(rule.identifier.rawValue)
        let s = c_AGGraphCreateShared(g!.graph)
        let rawS = unsafeBitCast(s, to: UnsafeRawPointer.self)
        let storageG = rawG.advanced(by: 0x10).load(as: UnsafeRawPointer.self)
        let storageS = rawS.advanced(by: 0x10).load(as: UnsafeRawPointer.self)
        let owner = c_AGGraphGetAttributeGraph(rule.identifier.rawValue)
        let ownerLabel = (owner == rawG) ? "G" : ((owner == rawS) ? "S" : "unknown")
        print("e1-case|cell=c3|evaluatedInG=no|gAlive=yes|readVia=G")
        print("hasValueBeforeShare=\(hasVal ? "yes" : "no")")
        print("storageG=\(storageG)|storageS=\(storageS)|sameStorage=\(storageG == storageS)")
        print("owner=\(ownerLabel)|ownerHandle=\(String(describing: owner))|rawG=\(rawG)|rawS=\(rawS)")
        print("aboutToRead=true")
        let val = g!.read(rule)
        print("value=\(val)")
        exit(0)

    case "e1-c4":
        // c4: Evaluated=no (rule NOT read before share) | G alive | Read via S
        setbuf(stdout, nil)
        var g: Driver? = Driver()
        let rawG = unsafeBitCast(g!.graph, to: UnsafeRawPointer.self)
        let rule: Handle<Int64> = g!.rule { 7 }
        let hasVal = c_AGGraphHasValue(rule.identifier.rawValue)
        let s = c_AGGraphCreateShared(g!.graph)
        let rawS = unsafeBitCast(s, to: UnsafeRawPointer.self)
        let sRoot = AttributeGraph.Subgraph(graph: s)
        let storageG = rawG.advanced(by: 0x10).load(as: UnsafeRawPointer.self)
        let storageS = rawS.advanced(by: 0x10).load(as: UnsafeRawPointer.self)
        let owner = c_AGGraphGetAttributeGraph(rule.identifier.rawValue)
        let ownerLabel = (owner == rawG) ? "G" : ((owner == rawS) ? "S" : "unknown")
        print("e1-case|cell=c4|evaluatedInG=no|gAlive=yes|readVia=S")
        print("hasValueBeforeShare=\(hasVal ? "yes" : "no")")
        print("storageG=\(storageG)|storageS=\(storageS)|sameStorage=\(storageG == storageS)")
        print("owner=\(ownerLabel)|ownerHandle=\(String(describing: owner))|rawG=\(rawG)|rawS=\(rawS)")
        print("aboutToRead=true")
        let reader: Handle<Int64> = sRoot.apply { Handle(NativeRule(body: { rule.value })) }
        print("value=\(reader.value)")
        exit(0)

    case "e1-c5":
        // c5: Evaluated=yes | G released | Read via S
        setbuf(stdout, nil)
        var g: Driver? = Driver()
        let rawG = unsafeBitCast(g!.graph, to: UnsafeRawPointer.self)
        let rule: Handle<Int64> = g!.rule { 7 }
        _ = g!.read(rule)
        let hasVal = c_AGGraphHasValue(rule.identifier.rawValue)
        let s = c_AGGraphCreateShared(g!.graph)
        let rawS = unsafeBitCast(s, to: UnsafeRawPointer.self)
        let sRoot = AttributeGraph.Subgraph(graph: s)
        let storageG = rawG.advanced(by: 0x10).load(as: UnsafeRawPointer.self)
        let storageS = rawS.advanced(by: 0x10).load(as: UnsafeRawPointer.self)
        let owner = c_AGGraphGetAttributeGraph(rule.identifier.rawValue)
        let ownerLabel = (owner == rawG) ? "G" : ((owner == rawS) ? "S" : "unknown")
        print("e1-case|cell=c5|evaluatedInG=yes|gAlive=no|readVia=S")
        print("hasValueBeforeShare=\(hasVal ? "yes" : "no")")
        print("storageG=\(storageG)|storageS=\(storageS)|sameStorage=\(storageG == storageS)")
        print("owner=\(ownerLabel)|ownerHandle=\(String(describing: owner))|rawG=\(rawG)|rawS=\(rawS)")
        let reader: Handle<Int64> = sRoot.apply { Handle(NativeRule(body: { rule.value })) }
        g = nil
        print("aboutToRead=true")
        print("value=\(reader.value)")
        exit(0)

    case "e1-c6":
        // c6: Evaluated=no | G released | Read via S
        setbuf(stdout, nil)
        var g: Driver? = Driver()
        let rawG = unsafeBitCast(g!.graph, to: UnsafeRawPointer.self)
        let rule: Handle<Int64> = g!.rule { 7 }
        let hasVal = c_AGGraphHasValue(rule.identifier.rawValue)
        let s = c_AGGraphCreateShared(g!.graph)
        let rawS = unsafeBitCast(s, to: UnsafeRawPointer.self)
        let sRoot = AttributeGraph.Subgraph(graph: s)
        let storageG = rawG.advanced(by: 0x10).load(as: UnsafeRawPointer.self)
        let storageS = rawS.advanced(by: 0x10).load(as: UnsafeRawPointer.self)
        let owner = c_AGGraphGetAttributeGraph(rule.identifier.rawValue)
        let ownerLabel = (owner == rawG) ? "G" : ((owner == rawS) ? "S" : "unknown")
        print("e1-case|cell=c6|evaluatedInG=no|gAlive=no|readVia=S")
        print("hasValueBeforeShare=\(hasVal ? "yes" : "no")")
        print("storageG=\(storageG)|storageS=\(storageS)|sameStorage=\(storageG == storageS)")
        print("owner=\(ownerLabel)|ownerHandle=\(String(describing: owner))|rawG=\(rawG)|rawS=\(rawS)")
        let reader: Handle<Int64> = sRoot.apply { Handle(NativeRule(body: { rule.value })) }
        g = nil
        print("aboutToRead=true")
        print("value=\(reader.value)")
        exit(0)

    case "e1-c9":
        // c9: Evaluated=yes | G invalidated-retained | Read via S
        setbuf(stdout, nil)
        var g: Driver? = Driver()
        let rawG = unsafeBitCast(g!.graph, to: UnsafeRawPointer.self)
        let rule: Handle<Int64> = g!.rule { 7 }
        _ = g!.read(rule)
        let hasVal = c_AGGraphHasValue(rule.identifier.rawValue)
        let s = c_AGGraphCreateShared(g!.graph)
        let rawS = unsafeBitCast(s, to: UnsafeRawPointer.self)
        let sRoot = AttributeGraph.Subgraph(graph: s)
        let storageG = rawG.advanced(by: 0x10).load(as: UnsafeRawPointer.self)
        let storageS = rawS.advanced(by: 0x10).load(as: UnsafeRawPointer.self)
        let owner = c_AGGraphGetAttributeGraph(rule.identifier.rawValue)
        let ownerLabel = (owner == rawG) ? "G" : ((owner == rawS) ? "S" : "unknown")
        print("e1-case|cell=c9|evaluatedInG=yes|gAlive=invalidated-retained|readVia=S")
        print("hasValueBeforeShare=\(hasVal ? "yes" : "no")")
        print("storageG=\(storageG)|storageS=\(storageS)|sameStorage=\(storageG == storageS)")
        print("owner=\(ownerLabel)|ownerHandle=\(String(describing: owner))|rawG=\(rawG)|rawS=\(rawS)")
        let reader: Handle<Int64> = sRoot.apply { Handle(NativeRule(body: { rule.value })) }
        _ = c_CFRetain(rawG)
        c_AGGraphInvalidate(rawG)
        print("aboutToRead=true")
        print("value=\(reader.value)")
        c_CFRelease(rawG)
        exit(0)

    case "e1-c10":
        // c10: Evaluated=no | G invalidated-retained | Read via S
        setbuf(stdout, nil)
        var g: Driver? = Driver()
        let rawG = unsafeBitCast(g!.graph, to: UnsafeRawPointer.self)
        let rule: Handle<Int64> = g!.rule { 7 }
        let hasVal = c_AGGraphHasValue(rule.identifier.rawValue)
        let s = c_AGGraphCreateShared(g!.graph)
        let rawS = unsafeBitCast(s, to: UnsafeRawPointer.self)
        let sRoot = AttributeGraph.Subgraph(graph: s)
        let storageG = rawG.advanced(by: 0x10).load(as: UnsafeRawPointer.self)
        let storageS = rawS.advanced(by: 0x10).load(as: UnsafeRawPointer.self)
        let owner = c_AGGraphGetAttributeGraph(rule.identifier.rawValue)
        let ownerLabel = (owner == rawG) ? "G" : ((owner == rawS) ? "S" : "unknown")
        print("e1-case|cell=c10|evaluatedInG=no|gAlive=invalidated-retained|readVia=S")
        print("hasValueBeforeShare=\(hasVal ? "yes" : "no")")
        print("storageG=\(storageG)|storageS=\(storageS)|sameStorage=\(storageG == storageS)")
        print("owner=\(ownerLabel)|ownerHandle=\(String(describing: owner))|rawG=\(rawG)|rawS=\(rawS)")
        let reader: Handle<Int64> = sRoot.apply { Handle(NativeRule(body: { rule.value })) }
        _ = c_CFRetain(rawG)
        c_AGGraphInvalidate(rawG)
        print("aboutToRead=true")
        print("value=\(reader.value)")
        c_CFRelease(rawG)
        exit(0)

    case "subgraph-c1", "subgraph-c2", "subgraph-c3", "subgraph-c4":
        setbuf(stdout, nil)
        var g: Driver? = Driver()
        let rawG = unsafeBitCast(g!.graph, to: UnsafeRawPointer.self)
        let s = c_AGGraphCreateShared(g!.graph)
        let rawS = unsafeBitCast(s, to: UnsafeRawPointer.self)
        let sRoot = AttributeGraph.Subgraph(graph: s)

        // Common input created in G
        let commonInput: Handle<Int64> = g!.input(10)

        // SG1 and SG2 created in G
        let sg1 = AttributeGraph.Subgraph(graph: g!.graph)
        let sg2 = AttributeGraph.Subgraph(graph: g!.graph)

        // R1 in SG1, R2 in SG2
        let r1: Handle<Int64> = sg1.apply {
            Handle(NativeRule(body: { commonInput.value + 1 }))
        }
        let r2: Handle<Int64> = sg2.apply {
            Handle(NativeRule(body: { commonInput.value + 2 }))
        }

        // None is read before share (hasValue=no)
        let hasValR1Before = c_AGGraphHasValue(r1.identifier.rawValue)
        let hasValR2Before = c_AGGraphHasValue(r2.identifier.rawValue)

        // Readers created in S
        let readerR1: Handle<Int64> = sRoot.apply {
            Handle(NativeRule(body: { r1.value }))
        }
        let readerR2: Handle<Int64> = sRoot.apply {
            Handle(NativeRule(body: { r2.value }))
        }

        let cellName = subcase.replacingOccurrences(of: "subgraph-", with: "")

        switch cellName {
        case "c1":
            // c1: Invalidate SG1, read R1 from S
            sg1.invalidate()
            let sg1Valid = sg1.isValid
            let sg2Valid = sg2.isValid
            print("subgraph-case|cell=c1|hasValR1Before=\(hasValR1Before ? "yes" : "no")|hasValR2Before=\(hasValR2Before ? "yes" : "no")|sg1Valid=\(sg1Valid)|sg2Valid=\(sg2Valid)|readVia=S|target=R1")
            print("aboutToRead=true")
            let val = readerR1.value
            print("value=\(val)")
            exit(0)

        case "c2":
            // c2: Invalidate SG1, read R2 from S
            sg1.invalidate()
            let sg1Valid = sg1.isValid
            let sg2Valid = sg2.isValid
            print("subgraph-case|cell=c2|hasValR1Before=\(hasValR1Before ? "yes" : "no")|hasValR2Before=\(hasValR2Before ? "yes" : "no")|sg1Valid=\(sg1Valid)|sg2Valid=\(sg2Valid)|readVia=S|target=R2")
            print("aboutToRead=true")
            let val = readerR2.value
            print("value=\(val)")
            exit(0)

        case "c3":
            // c3 (control): Without invalidating anything, read R1 from S
            let sg1Valid = sg1.isValid
            let sg2Valid = sg2.isValid
            print("subgraph-case|cell=c3|hasValR1Before=\(hasValR1Before ? "yes" : "no")|hasValR2Before=\(hasValR2Before ? "yes" : "no")|sg1Valid=\(sg1Valid)|sg2Valid=\(sg2Valid)|readVia=S|target=R1")
            print("aboutToRead=true")
            let val = readerR1.value
            print("value=\(val)")
            exit(0)

        case "c4":
            // c4 (control): Invalidate SG1, read R1 from G (creator)
            sg1.invalidate()
            let sg1Valid = sg1.isValid
            let sg2Valid = sg2.isValid
            print("subgraph-case|cell=c4|hasValR1Before=\(hasValR1Before ? "yes" : "no")|hasValR2Before=\(hasValR2Before ? "yes" : "no")|sg1Valid=\(sg1Valid)|sg2Valid=\(sg2Valid)|readVia=G|target=R1")
            print("aboutToRead=true")
            let val = r1.value
            print("value=\(val)")
            exit(0)

        default:
            exit(2)
        }

    case "rss-independent", "rss-shared":
        setbuf(stdout, nil)
        func getRSS() -> UInt64 {
            var info = mach_task_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / 4)
            let kerr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
                }
            }
            guard kerr == KERN_SUCCESS else { return 0 }
            return info.resident_size
        }

        let count = CommandLine.arguments.count > 3 ? (Int(CommandLine.arguments[3]) ?? 1000) : 1000
        let rssBefore = getRSS()

        if subcase == "rss-independent" {
            var drivers: [Driver] = []
            drivers.reserveCapacity(count)
            for _ in 0..<count {
                drivers.append(Driver())
            }
            let rssAfter = getRSS()
            print("rss-case|mode=independent|count=\(count)|rssBefore=\(rssBefore)|rssAfter=\(rssAfter)|delta=\(Int64(rssAfter) - Int64(rssBefore))")
            _ = drivers.count
            exit(0)
        } else {
            let baseDriver = Driver()
            var sharedHandles: [AttributeGraph.Graph] = []
            sharedHandles.reserveCapacity(count)
            for _ in 0..<count {
                sharedHandles.append(c_AGGraphCreateShared(baseDriver.graph))
            }
            let rssAfter = getRSS()
            print("rss-case|mode=shared|count=\(count)|rssBefore=\(rssBefore)|rssAfter=\(rssAfter)|delta=\(Int64(rssAfter) - Int64(rssBefore))")
            _ = sharedHandles.count
            _ = baseDriver.graph
            exit(0)
        }

    case "coord-write-G", "coord-write-S":
        setbuf(stdout, nil)
        var evalCount: Int = 0

        // 1. Create in G an input and shared handle S
        var g = Driver()
        let rawG = unsafeBitCast(g.graph, to: UnsafeRawPointer.self)
        let s = c_AGGraphCreateShared(g.graph)
        let rawS = unsafeBitCast(s, to: UnsafeRawPointer.self)
        let sRoot = AttributeGraph.Subgraph(graph: s)

        let input: Handle<Int64> = g.input(100)

        // 2. Rule R reading input, created from shared handle S
        let r: Handle<Int64> = sRoot.apply {
            Handle(NativeRule(body: {
                evalCount += 1
                return input.value + 1
            }))
        }

        // 3. Read R once (evaluation 1)
        let firstVal = r.value
        let countAfterFirstRead = evalCount

        // 4. Write to input from G or from S
        if subcase == "coord-write-G" {
            // Write from G
            input.value = 200
        } else {
            // Write from S: set value of input
            // To ensure write through S or same input
            input.value = 200
        }

        // 5. DO NOT READ R. Check evalCount immediately after write.
        let countAfterWrite = evalCount

        // 6. Read R now to verify it computes new value and increments count
        let secondVal = r.value
        let countAfterSecondRead = evalCount

        print("coord-case|writeVia=\(subcase == "coord-write-G" ? "G" : "S")|firstVal=\(firstVal)|countAfterFirstRead=\(countAfterFirstRead)|countAfterWrite=\(countAfterWrite)|secondVal=\(secondVal)|countAfterSecondRead=\(countAfterSecondRead)")
        exit(0)

    case "coord-u1":
        // U1: AGGraphSetNeedsUpdate() sobre G después de escribir, y luego leer desde S.
        setbuf(stdout, nil)
        var evalCount: Int = 0
        var g = Driver()
        let s = c_AGGraphCreateShared(g.graph)
        let sRoot = AttributeGraph.Subgraph(graph: s)
        let input: Handle<Int64> = g.input(100)
        let r: Handle<Int64> = sRoot.apply {
            Handle(NativeRule(body: {
                evalCount += 1
                return input.value + 1
            }))
        }
        _ = r.value // first read
        input.value = 200 // write
        let countAfterWrite = evalCount
        c_AGGraphSetNeedsUpdate(g.graph) // update step on G
        let countAfterUpdateStep = evalCount
        let finalVal = r.value // read from S
        let countAfterRead = evalCount
        print("coord-u1|countAfterWrite=\(countAfterWrite)|countAfterUpdateStep=\(countAfterUpdateStep)|finalVal=\(finalVal)|countAfterRead=\(countAfterRead)")
        exit(0)

    case "coord-u2":
        // U2: registrar AGGraphSetUpdateCallback en G, escribir, y anotar si el callback se dispara antes de cualquier lectura.
        setbuf(stdout, nil)
        var evalCount: Int = 0
        final class CallbackBox {
            var callbackFired = false
            var callbackCount = 0
        }
        let box = CallbackBox()
        let unmanaged = Unmanaged.passRetained(box)
        let rawPtr = unmanaged.toOpaque()

        var g = Driver()
        let s = c_AGGraphCreateShared(g.graph)
        let sRoot = AttributeGraph.Subgraph(graph: s)
        let input: Handle<Int64> = g.input(100)
        let r: Handle<Int64> = sRoot.apply {
            Handle(NativeRule(body: {
                evalCount += 1
                return input.value + 1
            }))
        }
        _ = r.value // first read

        let cCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { ctx in
            guard let ctx = ctx else { return }
            let b = Unmanaged<CallbackBox>.fromOpaque(ctx).takeUnretainedValue()
            b.callbackFired = true
            b.callbackCount += 1
        }
        c_AGGraphSetUpdateCallback(g.graph, cCallback, rawPtr)

        input.value = 200 // write
        let countAfterWrite = evalCount
        let firedAfterWrite = box.callbackFired
        let callbackCountAfterWrite = box.callbackCount

        // Step: perform setNeedsUpdate or trigger update pass
        c_AGGraphSetNeedsUpdate(g.graph)
        let countAfterUpdateStep = evalCount
        let firedAfterUpdateStep = box.callbackFired

        let finalVal = r.value // read from S
        let countAfterRead = evalCount
        let firedAfterRead = box.callbackFired

        unmanaged.release()
        print("coord-u2|countAfterWrite=\(countAfterWrite)|firedAfterWrite=\(firedAfterWrite)|callbackCountAfterWrite=\(callbackCountAfterWrite)|countAfterUpdateStep=\(countAfterUpdateStep)|firedAfterUpdateStep=\(firedAfterUpdateStep)|finalVal=\(finalVal)|countAfterRead=\(countAfterRead)|firedAfterRead=\(firedAfterRead)")
        exit(0)

    case "coord-u3":
        // U3: escribir dentro de una regla (un atributo que escribe en la entrada mientras se evalúa),
        // y anotar si R se evalúa en el mismo ciclo o en el siguiente.
        setbuf(stdout, nil)
        var evalCountR: Int = 0
        var evalCountWriter: Int = 0
        var g = Driver()
        let s = c_AGGraphCreateShared(g.graph)
        let gRoot = AttributeGraph.Subgraph(graph: g.graph)
        let sRoot = AttributeGraph.Subgraph(graph: s)
        let input: Handle<Int64> = g.input(100)

        // R reading input in S
        let r: Handle<Int64> = sRoot.apply {
            Handle(NativeRule(body: {
                evalCountR += 1
                return input.value + 1
            }))
        }
        _ = r.value // initial read of R, evalCountR = 1

        // Writer attribute in G that mutates input during its evaluation inside withoutUpdate
        let writerTrigger: Handle<Int64> = g.input(1)
        let writerRule: Handle<Int64> = gRoot.apply {
            Handle(NativeRule(body: {
                evalCountWriter += 1
                let trig = writerTrigger.value
                g.withoutUpdate {
                    input.value = trig * 50
                }
                return trig * 50
            }))
        }
        _ = writerRule.value // evaluate writer rule once -> writes 50 into input

        // Check if R was evaluated during/immediately after writer evaluation
        let countAfterWriterRun = evalCountR

        // Update step: evaluate writer again with new trigger
        writerTrigger.value = 2
        _ = writerRule.value // writes 100 into input
        let countAfterSecondWriterRun = evalCountR

        // Finally read R
        let finalVal = r.value
        let countAfterFinalRead = evalCountR
        print("coord-u3|countAfterWriterRun=\(countAfterWriterRun)|countAfterSecondWriterRun=\(countAfterSecondWriterRun)|finalVal=\(finalVal)|countAfterFinalRead=\(countAfterFinalRead)")
        exit(0)

    case "coord-u4":
        // U4: drenar el ciclo de actualización con AGSubgraphUpdate sobre un subgrafo (no sobre G),
        // después de escribir, y luego leer desde S.
        setbuf(stdout, nil)
        var evalCount: Int = 0
        var g = Driver()
        let s = c_AGGraphCreateShared(g.graph)
        let sRoot = AttributeGraph.Subgraph(graph: s)
        let input: Handle<Int64> = g.input(100)
        let r: Handle<Int64> = sRoot.apply {
            Handle(NativeRule(body: {
                evalCount += 1
                return input.value + 1
            }))
        }
        _ = r.value // first read
        input.value = 200 // write
        let countAfterWrite = evalCount

        // Drain update cycle with AGSubgraphUpdate on sRoot
        c_AGSubgraphUpdate(sRoot, 1) // flags = 1 (.all)
        let countAfterSubgraphUpdate = evalCount

        let finalVal = r.value // read from S
        let countAfterRead = evalCount
        print("coord-u4|countAfterWrite=\(countAfterWrite)|countAfterSubgraphUpdate=\(countAfterSubgraphUpdate)|finalVal=\(finalVal)|countAfterRead=\(countAfterRead)")
        exit(0)

    case "routing":
        setbuf(stdout, nil)
        let g = Driver()
        let rawG = unsafeBitCast(g.graph, to: UnsafeRawPointer.self)
        let s = c_AGGraphCreateShared(g.graph)
        let rawS = unsafeBitCast(s, to: UnsafeRawPointer.self)
        let sRoot = AttributeGraph.Subgraph(graph: s)

        let markerG = UnsafeRawPointer(bitPattern: 0xDEAD_1111)!
        let markerS = UnsafeRawPointer(bitPattern: 0xBEEF_2222)!
        c_AGGraphSetContext_raw(rawG, markerG)
        c_AGGraphSetContext_raw(rawS, markerS)

        let input: Handle<Int64> = g.input(100)
        let inputID = input.identifier.rawValue

        var insideRuleGraphInput: UnsafeRawPointer? = nil
        var insideRuleCtxInput: UnsafeRawPointer? = nil

        var rID: UInt32 = 0
        let r: Handle<Int64> = sRoot.apply {
            Handle(NativeRule(body: {
                insideRuleGraphInput = c_AGGraphGetAttributeGraph(inputID)
                if let gh = insideRuleGraphInput {
                    insideRuleCtxInput = c_AGGraphGetContext_raw(gh)
                }
                return input.value + 1
            }))
        }
        rID = r.identifier.rawValue
        let r2: Handle<Int64> = sRoot.apply {
            Handle(NativeRule(body: {
                r.value + 1
            }))
        }

        var invalidationCallbackAttr: UInt32 = 0
        var invalidationCallbackGraph: UnsafeRawPointer? = nil
        var invalidationCallbackCtx: UnsafeRawPointer? = nil
        s.onInvalidation { attr in
            invalidationCallbackAttr = attr.rawValue
            invalidationCallbackGraph = c_AGGraphGetAttributeGraph(attr.rawValue)
            if let gh = invalidationCallbackGraph {
                invalidationCallbackCtx = c_AGGraphGetContext_raw(gh)
            }
        }

        // Evaluate R and R2
        let val1 = r.value
        let valR2 = r2.value

        let outGraphInput = c_AGGraphGetAttributeGraph(inputID)
        let outCtxInput = outGraphInput != nil ? c_AGGraphGetContext_raw(outGraphInput!) : nil

        let outGraphR = c_AGGraphGetAttributeGraph(rID)
        let outCtxR = outGraphR != nil ? c_AGGraphGetContext_raw(outGraphR!) : nil

        // Mutate input in G via g.write (AGGraphSetValue) to invalidate R (and R2) in S
        g.write(200, to: input)

        let afterWriteGraphR = c_AGGraphGetAttributeGraph(rID)
        let afterWriteCtxR = afterWriteGraphR != nil ? c_AGGraphGetContext_raw(afterWriteGraphR!) : nil

        let matchInputG = (outGraphInput == rawG) && (outCtxInput == markerG) && (insideRuleGraphInput == rawG) && (insideRuleCtxInput == markerG)
        let matchRS = (outGraphR == rawS) && (outCtxR == markerS) && (afterWriteGraphR == rawS) && (afterWriteCtxR == markerS)
        let matchInvG = (invalidationCallbackAttr == inputID) && (invalidationCallbackGraph == rawG) && (invalidationCallbackCtx == markerG)

        print("routing|rawG=\(rawG)|rawS=\(rawS)|markerG=\(markerG)|markerS=\(markerS)|inputID=\(inputID)|rID=\(rID)|val1=\(val1)|valR2=\(valR2)|outGraphInput=\(String(describing: outGraphInput))|outCtxInput=\(String(describing: outCtxInput))|outGraphR=\(String(describing: outGraphR))|outCtxR=\(String(describing: outCtxR))|invAttr=\(invalidationCallbackAttr)|invGraph=\(String(describing: invalidationCallbackGraph))|invCtx=\(String(describing: invalidationCallbackCtx))|matchInputG=\(matchInputG)|matchRS=\(matchRS)|matchInvG=\(matchInvG)")
        exit(0)

    case "interop-i1":
        // I1: dos handles compartidos de G. Entrada en G (o S1), regla en S2 que la lee, modificar la entrada, releer.
        setbuf(stdout, nil)
        let g = Driver()
        let s1 = c_AGGraphCreateShared(g.graph)
        let s2 = c_AGGraphCreateShared(g.graph)
        let s1Root = AttributeGraph.Subgraph(graph: s1)
        let s2Root = AttributeGraph.Subgraph(graph: s2)

        let inputG: Handle<Int64> = g.input(10)
        let inputS1: Handle<Int64> = s1Root.apply { Handle(AttributeGraph.Attribute(value: Int64(20))) }

        let r2: Handle<Int64> = s2Root.apply {
            Handle(NativeRule(body: {
                inputG.value + inputS1.value
            }))
        }

        let v1 = r2.value
        inputG.value = 100
        inputS1.value = 200
        let v2 = r2.value
        print("interop-i1|v1=\(v1)|v2=\(v2)|status=OK")
        exit(0)

    case "interop-i2":
        // I2 (control): dos grafos independientes; regla en el segundo que lee una entrada del primero.
        setbuf(stdout, nil)
        let g1 = Driver()
        let g2 = Driver()
        let g2Root = AttributeGraph.Subgraph(graph: g2.graph)

        let input1: Handle<Int64> = g1.input(10)
        let r2: Handle<Int64> = g2Root.apply {
            Handle(NativeRule(body: {
                input1.value + 1
            }))
        }
        print("interop-i2|aboutToRead=true")
        let v1 = r2.value
        print("interop-i2|v1=\(v1)")
        exit(0)

    case "inv-routing-G", "inv-routing-S", "inv-routing-chain-G", "inv-routing-chain-S":
        setbuf(stdout, nil)
        // 1. Crea G y S = AGGraphCreateShared(G). Asigna a cada handle un callback de invalidación distinto.
        let g = Driver()
        let s = c_AGGraphCreateShared(g.graph)
        let sRoot = AttributeGraph.Subgraph(graph: s)

        var cntG = 0
        var cntS = 0
        g.graph.onInvalidation { _ in cntG += 1 }
        s.onInvalidation { _ in cntS += 1 }

        // 2. Crea una entrada en G y una regla R en S que la lea.
        let input: Handle<Int64> = g.input(100)
        let r: Handle<Int64> = sRoot.apply {
            Handle(NativeRule(body: {
                input.value + 1
            }))
        }

        let isChain = subcase.contains("chain")
        var r2: Handle<Int64>? = nil
        if isChain {
            r2 = sRoot.apply {
                Handle(NativeRule(body: {
                    r.value + 1
                }))
            }
        }

        // Evalúa R (o R2 -> R) una vez (leer desde S).
        let val1 = isChain ? sRoot.apply { r2!.value } : sRoot.apply { r.value }
        let cntGAfterFirstRead = cntG
        let cntSAfterFirstRead = cntS

        // 3 & 4. Escribe en la entrada desde G o desde S. Sin leer R, registra cntG y cntS.
        let writeFromG = subcase.hasSuffix("-G")
        if writeFromG {
            g.write(200, to: input)
        } else {
            sRoot.apply {
                input.value = 200
            }
        }
        let cntGAfterWrite = cntG
        let cntSAfterWrite = cntS

        // Después lee R (o R2 -> R) desde S y registra de nuevo ambos contadores.
        let val2 = isChain ? sRoot.apply { r2!.value } : sRoot.apply { r.value }
        let cntGAfterSecondRead = cntG
        let cntSAfterSecondRead = cntS

        let writeVia = writeFromG ? "G" : "S"
        let topo = isChain ? "chain(input->R->R2)" : "single(input->R)"
        print("inv-routing|topo=\(topo)|writeVia=\(writeVia)|val1=\(val1)|cntG_init=\(cntGAfterFirstRead)|cntS_init=\(cntSAfterFirstRead)|cntG_afterWrite=\(cntGAfterWrite)|cntS_afterWrite=\(cntSAfterWrite)|val2=\(val2)|cntG_afterRead=\(cntGAfterSecondRead)|cntS_afterRead=\(cntSAfterSecondRead)")
        exit(0)

    default:
        exit(2)
    }
}
#endif

#endif
