/// Options of ``Rule/cachedValue(options:owner:)`` (`AGCachedValueOptions` in native AttributeGraph). The bits are defined
/// by the native header; their effect was not measured: all five behaved like `[]` in the oracle (scenario `c8`).
public struct AGCachedValueOptions: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let option1 = AGCachedValueOptions(rawValue: 1 << 0)
    public static let option2 = AGCachedValueOptions(rawValue: 1 << 1)
    public static let option4 = AGCachedValueOptions(rawValue: 1 << 2)
    public static let option8 = AGCachedValueOptions(rawValue: 1 << 3)
    public static let option16 = AGCachedValueOptions(rawValue: 1 << 4)
}

extension Rule where Self: Hashable {
    /// The value of this rule, computed once per equal rule in a subgraph and kept in that subgraph's cache
    /// (`Rule.cachedValue(options:owner:)` in native AttributeGraph; measured on macOS 15.8.3, oracle scenarios `c0` to
    /// `c10`).
    ///
    /// Two rules are the same entry when they are equal by `==`, whatever else they hold. The entry lives in the subgraph
    /// of `owner`; without `owner` it is the subgraph of the rule that is running, or else the current subgraph, and
    /// with neither the program stops, as native does (`no subgraph`). A changed input the body read re-evaluates it.
    public func cachedValue(options: AGCachedValueOptions = [], owner: AnyAttribute?) -> Value {
        let (graph, ownerSubgraph) = Self.cacheOwner(owner)
        let attribute: Attribute<Value> = graph.cachedAttribute(
            typeKey: ObjectIdentifier(Self.self), key: AnyHashable(self), owner: ownerSubgraph
        ) { graph.makeRule(self) }!
        return attribute.value
    }

    /// The cached value of an equal rule, or `nil` if none was created in that subgraph (`cachedValueIfExists` in native
    /// AttributeGraph). Native stops with a segmentation fault when the subgraph has never cached a rule of this type;
    /// this returns `nil` there instead.
    public func cachedValueIfExists(options: AGCachedValueOptions = [], owner: AnyAttribute?) -> Value? {
        let (graph, ownerSubgraph) = Self.cacheOwner(owner)
        let attribute: Attribute<Value>? = graph.existingCachedAttribute(
            typeKey: ObjectIdentifier(Self.self), key: AnyHashable(self), owner: ownerSubgraph
        )
        return attribute?.value
    }

    /// The graph and the owner subgraph a cached value is looked up in (`nil` subgraph: the running rule's, chosen by the
    /// graph).
    private static func cacheOwner(_ owner: AnyAttribute?) -> (Graph, Subgraph?) {
        if let owner {
            guard let graph = GraphRegistry.graph(forTag: owner.id.graphTag) else {
                preconditionFailure("cachedValue: the graph of the owner was released")
            }
            return (graph, graph.subgraph(of: owner))
        }
        if let graph = ThreadLocalGraph.current(), graph.evaluatingNode != Graph.noNode {
            return (graph, nil)
        }
        guard let current = Subgraph.current else { preconditionFailure("no subgraph") }
        return (current.graph, current)
    }
}
