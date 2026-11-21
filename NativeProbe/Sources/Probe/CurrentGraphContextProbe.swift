#if NATIVE_ATTRIBUTE_GRAPH
import AttributeGraph
import Darwin

/// `AGSubgraphGetCurrentGraphContext()`: the context of the current subgraph, if any. Signature assumed (no arguments,
/// returns an opaque pointer); a link error at compile time would mean the native framework does not export it.
@_silgen_name("AGSubgraphGetCurrentGraphContext")
private func c_AGSubgraphGetCurrentGraphContext() -> UnsafeRawPointer?

@_silgen_name("AGSubgraphGetCurrent")
private func c_AGSubgraphGetCurrent() -> UnsafeRawPointer?

@_silgen_name("AGGraphGetContext")
private func c_AGGraphGetContext(_ graph: AttributeGraph.Graph) -> UnsafeRawPointer?

@_silgen_name("AGGraphSetContext")
private func c_AGGraphSetContext(_ graph: AttributeGraph.Graph, _ context: UnsafeRawPointer?)
#endif

/// When launched as `Probe current-graph-context`, prints whether the call returns nil outside a subgraph, in the
/// current subgraph, and inside a rule. Exits without running the other scenarios.
func runCurrentGraphContextProbeIfRequested() {
    guard CommandLine.arguments.count > 1, CommandLine.arguments[1] == "current-graph-context" else { return }
    #if NATIVE_ATTRIBUTE_GRAPH
    let d = Driver()
    let outside = c_AGSubgraphGetCurrentGraphContext() != nil
    let inside = d.currentSubgraph.apply { c_AGSubgraphGetCurrentGraphContext() != nil }
    let rule: Handle<Bool> = d.rule { c_AGSubgraphGetCurrentGraphContext() != nil }
    let inRule = d.read(rule)
    print("current-graph-context|outside=\(outside)|inSubgraph=\(inside)|inRule=\(inRule)")
    // Where the value comes from: compare it with the graph's own context pointer, then set one and read again.
    let sub = d.currentSubgraph.apply { c_AGSubgraphGetCurrentGraphContext() }
    let graphContextBefore = c_AGGraphGetContext(d.graph)
    let marker = UnsafeRawPointer(bitPattern: 0x5A5A_0000)!
    c_AGGraphSetContext(d.graph, marker)
    let after = d.currentSubgraph.apply { c_AGSubgraphGetCurrentGraphContext() }
    let graphContextAfter = c_AGGraphGetContext(d.graph)
    c_AGGraphSetContext(d.graph, graphContextBefore)
    let other = AttributeGraph.Subgraph(graph: d.graph)
    let otherValue = other.apply { c_AGSubgraphGetCurrentGraphContext() }
    let again = d.currentSubgraph.apply { c_AGSubgraphGetCurrentGraphContext() }
    // Inside a rule: is there a current subgraph at all? And is the object the same in a second, separate graph?
    let ruleSubgraph: Handle<Bool> = d.rule { c_AGSubgraphGetCurrent() != nil }
    let ruleHasCurrent = d.read(ruleSubgraph)
    let ruleContext: Handle<Bool> = d.rule { c_AGSubgraphGetCurrentGraphContext() != nil }
    let ruleContextNonNil = d.read(ruleContext)
    let second = Driver()
    let secondValue = second.currentSubgraph.apply { c_AGSubgraphGetCurrentGraphContext() }
    print("current-graph-context-identity|ruleHasCurrentSubgraph=\(ruleHasCurrent)|ruleContextNonNil=\(ruleContextNonNil)|firstGraph=\(String(describing: sub))|secondGraph=\(String(describing: secondValue))")
    if let ptr = sub {
        let isa = ptr.load(as: UnsafeRawPointer.self)
        var info = Dl_info()
        let named = dladdr(isa, &info) != 0 && info.dli_sname != nil ? String(cString: info.dli_sname) : "none"
        print("current-graph-context-class|isa=\(isa)|symbolAtIsa=\(named)")
    }
    if let a = after {
        print("current-graph-context-firstword|afterSet=\(a.load(as: UnsafeRawPointer?.self) == nil ? "nil" : String(describing: a.load(as: UnsafeRawPointer?.self)!))")
    }
    let graphBits = unsafeBitCast(d.graph, to: UnsafeRawPointer.self)
    print("current-graph-context-vs-graph|returnedEqualsGraphRef=\(sub == graphBits)|graphRef=\(graphBits)|returned=\(String(describing: sub))")
    print("current-graph-context-per-subgraph|scope=\(String(describing: sub))|again=\(String(describing: again))|otherSubgraph=\(String(describing: otherValue))")
    print("current-graph-context-source|subgraphValue=\(String(describing: sub))|graphContextBefore=\(String(describing: graphContextBefore))|subgraphAfterSet=\(String(describing: after))|graphContextAfterSet=\(String(describing: graphContextAfter))|equalBefore=\(sub == graphContextBefore)")
    d.close()
    exit(0)
    #else
    print("current-graph-context|skipped=own-engine")
    exit(0)
    #endif
}
