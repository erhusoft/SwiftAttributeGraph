extension Subgraph {
    /// The subgraph that is current on this thread (`Subgraph.current` in native AttributeGraph).
    ///
    /// Measured on macOS 15.8.3 in an isolated probe [O]:
    /// - It is `nil` outside any subgraph, and the subgraph inside ``Graph/withCurrent(_:_:)`` (`apply` natively).
    /// - Nested calls are restored on exit, also across two graphs.
    /// - It is `nil` once the current subgraph has been invalidated, also when it is restored to one that was
    ///   invalidated in the meantime.
    /// - A rule does not change it: inside a rule it is whatever was current where the read came from (`nil` when the
    ///   read came from outside any subgraph), and a `withCurrent` inside the rule makes its subgraph current until it
    ///   returns.
    ///
    /// Setting it (`AGSubgraphSetCurrent`) makes `newValue` current until it is set again; `withCurrent` restores the
    /// value that was set. Attributes are created in the subgraph made current [O for the getter, own for creation].
    /// Setting `nil` clears what ``current`` reports but the graph keeps creating attributes in the last subgraph set;
    /// natively a creation with no current subgraph is a programming error that the engine does not model [?].
    public static var current: Subgraph? {
        get {
            let raw = ThreadLocalSubgraph.get()
            guard raw != 0 else { return nil }
            let id = SubgraphID(rawValue: raw)
            guard let graph = GraphRegistry.graph(forTag: id.graphTag) else { return nil }
            graph.assertOwnThread()
            return graph.isValid(Subgraph(id: id)) ? Subgraph(id: id) : nil
        }
        set {
            guard let subgraph = newValue else {
                ThreadLocalSubgraph.exchange(0)
                return
            }
            let graph = subgraph.graph
            graph.assertOwnThread()
            precondition(graph.isValid(subgraph), "Subgraph.current: the subgraph was invalidated")
            graph.currentSubgraph = subgraph.id
            ThreadLocalSubgraph.exchange(subgraph.id.rawValue)
        }
    }
}
