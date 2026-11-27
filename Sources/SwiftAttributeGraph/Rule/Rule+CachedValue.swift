/// Options of ``Rule/cachedValue(options:owner:)`` (`AGCachedValueOptions` in native AttributeGraph). The bits are defined
/// by the native header; their effect was not measured: all five behaved like `[]` in the oracle (scenario `c8`).
public struct AGCachedValueOptions: OptionSet, Sendable {
    /// The raw option bits.
    public let rawValue: UInt32

    /// Creates the options from their raw bits.
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    /// Native option bit 0 (`1 << 0`); no effect was measured (oracle scenarios `c8`, `c8b`).
    public static let option1 = AGCachedValueOptions(rawValue: 1 << 0)
    /// Native option bit 1 (`1 << 1`); no effect was measured (oracle scenarios `c8`, `c8b`).
    public static let option2 = AGCachedValueOptions(rawValue: 1 << 1)
    /// Native option bit 2 (`1 << 2`); no effect was measured (oracle scenarios `c8`, `c8b`).
    public static let option4 = AGCachedValueOptions(rawValue: 1 << 2)
    /// Native option bit 3 (`1 << 3`); no effect was measured (oracle scenarios `c8`, `c8b`).
    public static let option8 = AGCachedValueOptions(rawValue: 1 << 3)
    /// Native option bit 4 (`1 << 4`); no effect was measured (oracle scenarios `c8`, `c8b`).
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
            typeKey: ObjectIdentifier(Self.self), key: AnyHashable(RawCacheKey(hash: hashValue, body: self)), owner: ownerSubgraph
        ) { graph.makeRule(self) }!
        return attribute.value
    }

    /// The cached value of an equal rule, or `nil` if none was created in that subgraph (`cachedValueIfExists` in native
    /// AttributeGraph). Native stops with a segmentation fault when the subgraph has never cached a rule of this type;
    /// this returns `nil` there instead.
    public func cachedValueIfExists(options: AGCachedValueOptions = [], owner: AnyAttribute?) -> Value? {
        let (graph, ownerSubgraph) = Self.cacheOwner(owner)
        let attribute: Attribute<Value>? = graph.existingCachedAttribute(
            typeKey: ObjectIdentifier(Self.self), key: AnyHashable(RawCacheKey(hash: hashValue, body: self)), owner: ownerSubgraph
        )
        return attribute?.value
    }

    /// The cached value for an entry named by `hashValue` and the rule `bodyPtr` points to, creating it with `update` the
    /// first time (`Rule._cachedValue(options:owner:hashValue:bodyPtr:update:)` in native AttributeGraph; oracle scenario `c13`).
    ///
    /// `update` is asked for once per rule type and subgraph; it returns the body of the attribute, which gets a copy of the
    /// rule and the attribute and must write the value through `RuleContext(attribute:)`. Later entries of the same type run
    /// that first body, so the `update` of later calls is never called. The returned pointer is valid until the next call
    /// for that entry.
    public static func _cachedValue(
        options: AGCachedValueOptions = [],
        owner: AnyAttribute?,
        hashValue: Int,
        bodyPtr: UnsafeRawPointer,
        update: () -> (UnsafeMutableRawPointer, AnyAttribute) -> Void
    ) -> UnsafePointer<Value> {
        let (graph, ownerSubgraph) = cacheOwner(owner)
        let rule = bodyPtr.assumingMemoryBound(to: Self.self).pointee
        let key = AnyHashable(RawCacheKey(hash: hashValue, body: rule))
        let typeKey = ObjectIdentifier(Self.self)
        let attribute: Attribute<Value> = withoutActuallyEscaping(update) { update in
            graph.cachedAttribute(typeKey: typeKey, key: key, owner: ownerSubgraph) {
                let owning = ownerSubgraph ?? graph.runningRuleSubgraph()
                let inner = graph.rawUpdater(in: owning, typeKey: typeKey, make: update)
                let storage = UnsafeMutablePointer<Self>.allocate(capacity: 1)
                storage.initialize(to: rule)
                let node = RawCachedRuleNode<Value>(
                    storage: UnsafeMutableRawPointer(storage),
                    destroyStorage: { raw in
                        let typed = raw.assumingMemoryBound(to: Self.self)
                        typed.deinitialize(count: 1)
                        typed.deallocate()
                    },
                    update: inner, typeName: String(describing: Self.self),
                    type: graph.comparators.nodeType(.viewValue, for: Value.self))
                return Attribute<Value>(id: graph.allocateTypeRule(node))
            }!
        }
        _ = attribute.value
        let node = graph.table.box(at: attribute.id.index) as! RawCachedRuleNode<Value>
        return node.exportedPointer()
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

/// The key of a cache entry: the hash value it was asked with and the rule, compared with the rule's `==`.
struct RawCacheKey<Body: Hashable>: Hashable {
    let hash: Int
    let body: Body
}

extension Graph {
    /// The subgraph of the rule that is running, or the current one.
    func runningRuleSubgraph() -> Subgraph {
        if evaluatingNode != Graph.noNode { return Subgraph(id: subgraphs.id(at: table.owner(at: evaluatingNode))) }
        return Subgraph(id: currentSubgraph)
    }

    /// The inner body of the first `_cachedValue` call of a rule type in `subgraph`; `make` is only called for that first one.
    func rawUpdater(in subgraph: Subgraph, typeKey: ObjectIdentifier,
                    make: () -> (UnsafeMutableRawPointer, AnyAttribute) -> Void) -> (UnsafeMutableRawPointer, AnyAttribute) -> Void {
        if let existing = nodeCaches[subgraph.id.index]?.updaters[typeKey] { return existing }
        let inner = make()
        nodeCaches[subgraph.id.index, default: SubgraphNodeCache()].updaters[typeKey] = inner
        return inner
    }
}
