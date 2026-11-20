extension Graph {
    /// The graph that owns `attribute`, or `nil` if the attribute is dead (its subgraph was invalidated) or its graph is
    /// gone.
    ///
    /// Handles do not hold their graph; the graph is found through the tag its IDs carry. Native
    /// `AGGraphGetAttributeGraph` returns the graph the attribute was created in, also when two graphs live in the same
    /// process [O], and traps on a dead attribute [O]; this variant returns `nil` instead. Use ``Attribute/graph`` for
    /// the trapping form.
    public static func graph(of attribute: AnyAttribute) -> Graph? {
        guard let graph = GraphRegistry.graph(forTag: attribute.id.graphTag) else { return nil }
        graph.assertOwnThread()
        return graph.table.isLive(attribute.id) ? graph : nil
    }

    /// The graph that owns `subgraph`, or `nil` if the subgraph was invalidated or its graph is gone.
    ///
    /// Native `AGSubgraphGetGraph` returns the graph the subgraph was created in [O] and traps on an invalidated
    /// subgraph [O]; this variant returns `nil` instead. Use ``Subgraph/graph`` for the trapping form.
    public static func graph(of subgraph: Subgraph) -> Graph? {
        guard let graph = GraphRegistry.graph(forTag: subgraph.id.graphTag) else { return nil }
        graph.assertOwnThread()
        return graph.subgraphs.isLive(subgraph.id) ? graph : nil
    }
}

extension AnyAttribute {
    /// The graph that owns the attribute (`AnyAttribute.graph` in native AttributeGraph, which traps on a dead one [O]).
    ///
    /// Stops the program if the attribute is dead or its graph is gone; use ``Graph/graph(of:)-(AnyAttribute)`` to ask
    /// without trapping.
    public var graph: Graph {
        guard let graph = Graph.graph(of: self) else {
            preconditionFailure("AnyAttribute.graph: the attribute is dead or its graph was released")
        }
        return graph
    }
}

extension Attribute {
    /// The graph that owns the attribute (`Attribute.graph` in native AttributeGraph, which traps on a dead one [O]).
    ///
    /// Stops the program if the attribute is dead or its graph is gone; use ``Graph/graph(of:)-(AnyAttribute)`` to ask
    /// without trapping.
    public var graph: Graph { erased.graph }
}

extension Subgraph {
    /// The graph that owns the subgraph (`Subgraph.graph` in native AttributeGraph, which traps on an invalidated
    /// one [O]).
    ///
    /// Stops the program if the subgraph was invalidated or its graph is gone; use ``Graph/graph(of:)-(Subgraph)`` to
    /// ask without trapping.
    public var graph: Graph {
        guard let graph = Graph.graph(of: self) else {
            preconditionFailure("Subgraph.graph: the subgraph was invalidated or its graph was released")
        }
        return graph
    }
}
