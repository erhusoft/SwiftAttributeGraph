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

    // Update machinery (see `Graph+Update.swift`).
    var frames: [UpdateFrame] = []
    var evaluatingNode: UInt32 = Graph.noNode
    var trackCursor = 0

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
        let root = subgraphs.allocate()
        rootSubgraph = Subgraph(id: root)
        currentSubgraph = root
    }

    /// Stops the program in debug builds if the graph is used from another thread than the one that created it.
    @inline(__always)
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

    /// Creates a subgraph. Attributes created while it is current belong to it and die with it.
    public func makeSubgraph() -> Subgraph {
        assertOwnThread()
        return Subgraph(id: subgraphs.allocate())
    }

    /// Runs `body` with `subgraph` as the current one, so the attributes created inside belong to it.
    public func withCurrent<T>(_ subgraph: Subgraph, _ body: () -> T) -> T {
        assertOwnThread()
        precondition(subgraphs.isLive(subgraph.id), "withCurrent: the subgraph was invalidated")
        let previous = currentSubgraph
        currentSubgraph = subgraph.id
        defer { currentSubgraph = previous }
        return body()
    }

    /// The subgraph that owns the attribute.
    func subgraph(of id: AttributeID) -> Subgraph {
        precondition(table.isLive(id), "subgraph(of:): the attribute is dead")
        let owner = table.owner(at: id.index)
        return Subgraph(id: SubgraphID(index: owner, generation: subgraphs.generations[Int(owner)]))
    }

    // MARK: Creating attributes

    /// Whether the ID names a live attribute.
    func contains(_ id: AttributeID) -> Bool { table.isLive(id) }

    /// Creates a leaf attribute holding `value`, in the current subgraph.
    public func makeInput<Value>(_ value: Value, comparison: Comparison = .viewValue) -> Attribute<Value> {
        assertOwnThread()
        let id = allocate(InputNode(value: value, isEqual: comparators.comparator(comparison, for: Value.self)), state: NodeState.hasValue)
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

    private func allocate(_ box: NodeBox, state: UInt8) -> AttributeID {
        precondition(subgraphs.isLive(currentSubgraph), "the current subgraph was invalidated")
        let id = table.allocate(owner: currentSubgraph.index, box: box, state: state, version: 1)
        subgraphs.add(member: id.index, to: currentSubgraph)
        return id
    }

    func typedNode<Value>(_ attribute: Attribute<Value>) -> TypedNode<Value> {
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
