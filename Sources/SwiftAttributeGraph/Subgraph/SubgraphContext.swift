/// Opaque identifier for the invalidation context of a subgraph (matching `Subgraph + 0x30` in native AttributeGraph).
///
/// Contexts are created exclusively via ``Graph/makeSubgraphContext()``. When a subgraph is invalidated, children in
/// the same context are invalidated with it (and unlinked from any other living parents), whereas children in a
/// different context only lose the link from the invalidated parent and survive.
public struct SubgraphContext: Hashable, Sendable {
    let rawValue: UInt32

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}
