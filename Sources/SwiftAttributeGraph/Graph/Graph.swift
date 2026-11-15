/// An attribute graph: attributes with a value or a rule, the dependencies between them, and the subgraphs that own
/// them.
///
/// A graph belongs to **one thread**: it is not `Sendable` and every operation assumes it is not used concurrently
/// (debug builds check it). Programming errors (a dead ID, a cycle, a wrong type, writing from inside a rule) stop the
/// program with `precondition`; nothing here throws.
public final class Graph {
    /// Marks "no rule is running".
    static let noNode = UInt32.max

    var table = NodeTable()
    /// Comparators resolved so far, one per value type and policy (see `ValueComparator.Cache`).
    var comparators = ValueComparator.Cache()
    var subgraphs = SubgraphTable()
    var currentSubgraph: SubgraphID

    /// Global epoch counter bumped every time an attribute value in the graph changes.
    public internal(set) var globalVersion: UInt32 = 1

    // Subgraph invalidation (see `Graph+Invalidation.swift`).
    var subgraphObservers: [UInt32: [Observer]] = [:]
    /// Invalidations asked for while a rule runs (or from a notice), done when the outermost update ends.
    var deferredInvalidations: [Subgraph] = []
    var isInvalidating = false

    // Update machinery (see `Graph+Update.swift`).
    var frames: [UpdateFrame] = []
    @usableFromInline var evaluatingNode: UInt32 = Graph.noNode
    var isResumingStep = false
    /// Number of times a rule has been executed (recalculations) since the graph was created.
    public internal(set) var recalculationCount = 0

    // Propagation and notifications (see `Graph+Propagation.swift` and `Graph+Observation.swift`).
    var dirtyStack: [UInt32] = []
    var pendingNotifications: [UInt32] = []
    var observers: [UInt32: [Observer]] = [:]
    var nextObserverID = 0
    var batchDepth = 0
    var isFlushing = false

    #if DEBUG && !SAG_UNCHECKED
    let owningThread = currentThreadToken()
    #endif

    /// The subgraph every attribute is born in until ``withCurrent(_:_:)`` says otherwise. It cannot be invalidated.
    public let rootSubgraph: Subgraph

    /// Number of live attributes.
    public var nodeCount: Int { table.liveCount }

    /// Creates an empty graph with a root subgraph.
    public init() {
        let root = subgraphs.allocate(parent: nil)
        rootSubgraph = Subgraph(id: root)
        currentSubgraph = root
    }

    /// Stops the program in debug builds if the graph is used from another thread than the one that created it.
    @inline(__always)
    @usableFromInline
    func assertOwnThread() {
        #if DEBUG && !SAG_UNCHECKED
        precondition(isOnOwningThread, "a Graph must be used from the thread that created it")
        #endif
    }

    #if DEBUG && !SAG_UNCHECKED
    /// Whether the calling thread is the one that created the graph (debug builds only).
    var isOnOwningThread: Bool { currentThreadToken() == owningThread }
    #endif

    // MARK: Subgraphs

    /// Creates a subgraph as a child of `parent` (by default the current subgraph). Attributes created while it is
    /// current belong to it, and it dies with its parent.
    public func makeSubgraph(parent: Subgraph? = nil) -> Subgraph {
        assertOwnThread()
        let owner = parent?.id ?? currentSubgraph
        precondition(subgraphs.isLive(owner), "makeSubgraph: the parent subgraph was invalidated")
        precondition(!subgraphs.isFalling(index: owner.index), "makeSubgraph: the parent subgraph is being invalidated")
        return Subgraph(id: subgraphs.allocate(parent: owner))
    }

    /// Runs `body` with `subgraph` as the current one, so the attributes created inside belong to it.
    public func withCurrent<T>(_ subgraph: Subgraph, _ body: () -> T) -> T {
        assertOwnThread()
        precondition(subgraphs.isLive(subgraph.id), "withCurrent: the subgraph was invalidated")
        precondition(!subgraphs.isFalling(index: subgraph.id.index), "withCurrent: the subgraph is being invalidated")
        let previous = currentSubgraph
        currentSubgraph = subgraph.id
        defer { currentSubgraph = previous }
        return body()
    }

    /// Number of live subgraphs, the root included.
    public var liveSubgraphCount: Int { subgraphs.liveCount }

    /// Whether the subgraph exists (it was not freed).
    func isLive(_ subgraph: Subgraph) -> Bool { subgraphs.isLive(subgraph.id) }

    /// Whether the subgraph is valid (it is alive and has not been invalidated).
    public func isValid(_ subgraph: Subgraph) -> Bool {
        assertOwnThread()
        return subgraphs.isLive(subgraph.id) && !subgraphs.isFalling(index: subgraph.id.index)
    }

    /// The parent of a subgraph; `nil` for the root.
    func parent(of subgraph: Subgraph) -> Subgraph? {
        precondition(subgraphs.isLive(subgraph.id), "parent(of:): the subgraph was invalidated")
        return subgraphs.parent(of: subgraph.id).map(Subgraph.init(id:))
    }

    /// The children of a subgraph in creation order.
    func children(of subgraph: Subgraph) -> [Subgraph] {
        precondition(subgraphs.isLive(subgraph.id), "children(of:): the subgraph was invalidated")
        return subgraphs.children(of: subgraph.id.index).map { Subgraph(id: subgraphs.id(at: $0)) }
    }

    /// The subgraph that owns the attribute.
    func subgraph(of id: AttributeID) -> Subgraph {
        precondition(table.isLive(id), "subgraph(of:): the attribute is dead")
        let owner = table.owner(at: id.index)
        return Subgraph(id: SubgraphID(index: owner, generation: subgraphs.generations[Int(owner)]))
    }

    // MARK: Creating attributes

    /// Whether the ID names a live attribute.
    @usableFromInline func contains(_ id: AttributeID) -> Bool { table.isLive(id) }

    /// Creates a leaf attribute holding `value`, in the current subgraph.
    public func makeInput<Value>(_ value: Value, comparison: Comparison = .viewValue) -> Attribute<Value> {
        assertOwnThread()
        let id = allocate(InputNode(value: value, isEqual: comparators.comparator(comparison, for: Value.self)), state: NodeState.hasValue)
        return Attribute(id: id)
    }

    /// Creates an indirect attribute that redirects to `source`, in the current subgraph.
    ///
    /// Reading the indirect attribute reads `source`; writing it writes to `source`. It has no
    /// value of its own and shares `source`'s version, so the value cut applies to `source`.
    /// `source` must not be a rule (rules cannot be written to).
    public func makeIndirect<Value>(_ source: Attribute<Value>) -> Attribute<Value> {
        assertOwnThread()
        precondition(table.isLive(source.id), "makeIndirect: the source attribute is dead")
        precondition(table.state[Int(source.id.index)] & NodeState.isRule == 0,
                     "makeIndirect: cannot redirect to a rule")
        let id = allocate(IndirectNode<Value>(source: source.id), state: NodeState.hasValue | NodeState.indirect)
        return Attribute(id: id)
    }

    /// Creates a rule attribute from a type that conforms to ``Rule``, in the current subgraph. The rule runs lazily.
    public func makeRule<R: Rule>(_ rule: R, comparison: Comparison = .viewValue) -> Attribute<R.Value> {
        assertOwnThread()
        let id = allocate(TypeRuleNode(rule: rule, isEqual: comparators.comparator(comparison, for: R.Value.self)),
                         state: NodeState.isRule | NodeState.dirty)
        return Attribute(id: id)
    }

    /// Creates a rule attribute from a closure, in the current subgraph. The closure runs lazily.
    public func makeRule<Value>(_ body: @escaping () -> Value, comparison: Comparison = .viewValue) -> Attribute<Value> {
        assertOwnThread()
        let id = allocate(ClosureRuleNode(body: body, isEqual: comparators.comparator(comparison, for: Value.self)),
                         state: NodeState.isRule | NodeState.dirty)
        return Attribute(id: id)
    }

    /// Creates a stateful rule from a type that conforms to ``StatefulRule``, in the current subgraph.
    public func makeStatefulRule<R: StatefulRule>(_ rule: R, comparison: Comparison = .viewValue) -> Attribute<R.Value> {
        assertOwnThread()
        let id = allocate(StatefulRuleNode(rule: rule, isEqual: comparators.comparator(comparison, for: R.Value.self)),
                          state: NodeState.isRule | NodeState.dirty | NodeState.stateful)
        return Attribute(id: id)
    }

    /// Creates a stateful rule from a closure, in the current subgraph. `initialValue` is the value before the first run.
    public func makeStatefulRule<Value>(initialValue: Value? = nil, comparison: Comparison = .viewValue,
                                        _ body: @escaping (inout RuleContext<Value>) -> Void) -> Attribute<Value> {
        assertOwnThread()
        let id = allocate(ClosureStatefulRuleNode(initialValue: initialValue, body: body,
                                                  isEqual: comparators.comparator(comparison, for: Value.self)),
                          state: NodeState.isRule | NodeState.dirty | NodeState.stateful)
        return Attribute(id: id)
    }

    func allocate(_ box: NodeBox, state: UInt16) -> AttributeID {
        precondition(subgraphs.isLive(currentSubgraph), "the current subgraph was invalidated")
        precondition(!subgraphs.isFalling(index: currentSubgraph.index), "the current subgraph is being invalidated")
        let id = table.allocate(owner: currentSubgraph.index, box: box, state: state, version: 1)
        subgraphs.add(member: id.index, to: currentSubgraph)
        return id
    }

    @usableFromInline func typedNode<Value>(_ attribute: Attribute<Value>) -> TypedNode<Value> {
        let box = table.box(at: attribute.id.index)
        #if DEBUG && !SAG_UNCHECKED
        guard let node = box as? TypedNode<Value> else {
            preconditionFailure("the attribute does not hold a value of type \(Value.self)")
        }
        return node
        #else
        return unsafeDowncast(box, to: TypedNode<Value>.self)
        #endif
    }
}

extension Attribute {
    /// The value of the attribute, read from the graph whose rule is running on this thread.
    ///
    /// Reading inside a rule records a dependency. Outside a rule there is no current graph: use
    /// ``Graph/value(of:)``.
    public var value: Value {
        guard let graph = ThreadLocalGraph.current() else {
            preconditionFailure("Attribute.value can only be read inside a rule; use Graph.value(of:) elsewhere")
        }
        return graph.read(self)
    }
}
