/// A handle to a subgraph: the owner of a set of attributes that all die together.
///
/// Every attribute is created in the *current* subgraph (see ``Graph/withCurrent(_:_:)``). Invalidating a subgraph
/// frees everything it owns, which is how the engine meets the rule "nothing persists without an owner".
public struct Subgraph: Hashable, Sendable {
    /// Alias matching `Subgraph.Flags` in native AttributeGraph.
    public typealias Flags = AttributeFlags

    /// The ID of the subgraph inside its graph.
    public let id: SubgraphID

    /// Whether the debug tree recording is enabled (`AGSubgraphShouldRecordTree`).
    nonisolated(unsafe) public private(set) static var shouldRecordTree: Bool = false

    /// Enables tree recording (`AGSubgraphSetShouldRecordTree`).
    public static func setShouldRecordTree() {
        shouldRecordTree = true
    }
}
