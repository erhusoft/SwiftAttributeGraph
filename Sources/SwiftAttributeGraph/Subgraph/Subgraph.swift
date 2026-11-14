/// A handle to a subgraph: the owner of a set of attributes that all die together.
///
/// Every attribute is created in the *current* subgraph (see ``Graph/withCurrent(_:_:)``). Invalidating a subgraph
/// frees everything it owns, which is how the engine meets the rule "nothing persists without an owner".
public struct Subgraph: Hashable, Sendable {
    /// The ID of the subgraph inside its graph.
    public let id: SubgraphID
}
