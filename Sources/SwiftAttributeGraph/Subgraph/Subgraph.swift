/// Identifies the invalidation context of a subgraph (matching `Subgraph + 0x30` in native AttributeGraph).
///
/// When a subgraph is invalidated, children in the same context are invalidated with it (and unlinked from any other
/// living parents), whereas children in a different context only lose the link from the invalidated parent and survive.
public struct SubgraphContext: Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

/// A handle to a subgraph: the owner of a set of attributes that all die together.
///
/// Every attribute is created in the *current* subgraph (see ``Graph/withCurrent(_:_:)``). Invalidating a subgraph
/// frees everything it owns, which is how the engine meets the rule "nothing persists without an owner".
public struct Subgraph: Hashable, Sendable {
    /// Alias matching `Subgraph.Flags` in native AttributeGraph.
    public typealias Flags = AttributeFlags

    /// The ID of the subgraph inside its graph.
    public let id: SubgraphID
}
