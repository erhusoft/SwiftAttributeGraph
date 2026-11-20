/// An attribute graph: attributes with a value or a rule, the dependencies between them, and the subgraphs that own
/// them.
///
/// A graph belongs to **one thread**: it is not `Sendable` and every operation assumes it is not used concurrently
/// (debug builds check it). Programming errors (a dead ID, a cycle, a wrong type, writing from inside a rule) stop the
/// program with `precondition`; nothing here throws.
public final class Graph {
    /// Marks "no rule is running".
    static let noNode = UInt32.max

    // Mutable state. Release builds turn off the dynamic exclusivity check on these stored properties: the profile of
    // `batch-writes` spent 29 % of its time in `swift_beginAccess`/`SwiftTLSContext::get` on them [O]. The graph is used
    // from one thread and no engine function holds a long `inout` access to one of them while it calls back into user
    // code, which is what the check would catch; debug builds keep the check so the tests still find such an access.
    #if DEBUG && !SAG_UNCHECKED
    var table = NodeTable()
    /// The tag that the IDs of this graph carry (see `GraphRegistry`).
    let graphTag: UInt32
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
    var nodeCaches: [UInt32: SubgraphNodeCache] = [:]
    struct WeakGraphContext {
        weak var value: GraphContext?
    }

    var updateContexts: [WeakGraphContext] = []
    var nextGraphContextID: UInt32 = 1
    var hasAnyInvalidationCallback = false
    @usableFromInline var readEpoch: UInt32 = 0
    lazy var defaultUpdateContext: GraphContext = {
        let ctx = GraphContext(graph: self, id: 0, contextID: graphCounterID + 1,
                               subgraphContext: SubgraphContext(rawValue: SubgraphTable.defaultContext))
        updateContexts.append(WeakGraphContext(value: ctx))
        return ctx
    }()
    var isInUpdateCallback = false
    var edgeComparators: [UInt32: [UInt32: (Any, Any) -> Bool]] = [:]
    var stickyChangedEdges: [UInt32: Set<UInt32>] = [:]
    var offsetIndirects: [UInt32: (offset: Int, size: Int)] = [:]
    var offsetFieldReaders: [UInt32: () -> Any] = [:]
    var indirectsWithOffsetInChain: Set<UInt32> = []
    var isInvalidating = false
    var deferringSubgraphInvalidationDepth = 0

    // Update machinery (see `Graph+Update.swift`).
    var frames: [UpdateFrame] = []
    @usableFromInline var evaluatingNode: UInt32 = Graph.noNode
    var isResumingStep = false
    /// Number of times a rule has been executed (recalculations) since the graph was created.
    public internal(set) var recalculationCount = 0

    // Counters behind `counter(for:)` (see `Graph+Counters.swift`).
    var transactionCount: UInt64 = 0
    var updateCount: UInt64 = 0
    var changeCount: UInt64 = 0
    var createdNodeCount: UInt64 = 0
    var countsUpdateOnNextRule = false
    /// `counter(for: .graphID)`; the default context is `graphCounterID + 1`.
    let graphCounterID: UInt64
    /// Raised by ``setNeedsUpdate()``, lowered at the start of the next top-level read of a rule.
    var needsUpdateFlag = false

    // Propagation and notifications (see `Graph+Propagation.swift` and `Graph+Observation.swift`).
    var dirtyStack: [UInt32] = []
    var pendingNotifications: [UInt32] = []
    var observers: [UInt32: [Observer]] = [:]
    var nextObserverID = 0
    var batchDepth = 0
    var isFlushing = false
    #else
    @exclusivity(unchecked) var table = NodeTable()
    /// The tag that the IDs of this graph carry (see `GraphRegistry`).
    let graphTag: UInt32
    /// Comparators resolved so far, one per value type and policy (see `ValueComparator.Cache`).
    @exclusivity(unchecked) var comparators = ValueComparator.Cache()
    @exclusivity(unchecked) var subgraphs = SubgraphTable()
    @exclusivity(unchecked) var currentSubgraph: SubgraphID

    /// Global epoch counter bumped every time an attribute value in the graph changes.
    @exclusivity(unchecked) public internal(set) var globalVersion: UInt32 = 1

    // Subgraph invalidation (see `Graph+Invalidation.swift`).
    @exclusivity(unchecked) var subgraphObservers: [UInt32: [Observer]] = [:]
    /// Invalidations asked for while a rule runs (or from a notice), done when the outermost update ends.
    @exclusivity(unchecked) var deferredInvalidations: [Subgraph] = []
    @exclusivity(unchecked) var nodeCaches: [UInt32: SubgraphNodeCache] = [:]
    struct WeakGraphContext {
        weak var value: GraphContext?
    }

    @exclusivity(unchecked) var updateContexts: [WeakGraphContext] = []
    @exclusivity(unchecked) var nextGraphContextID: UInt32 = 1
    @exclusivity(unchecked) var hasAnyInvalidationCallback = false
    @exclusivity(unchecked) @usableFromInline var readEpoch: UInt32 = 0
    lazy var defaultUpdateContext: GraphContext = {
        let ctx = GraphContext(graph: self, id: 0, contextID: graphCounterID + 1,
                               subgraphContext: SubgraphContext(rawValue: SubgraphTable.defaultContext))
        updateContexts.append(WeakGraphContext(value: ctx))
        return ctx
    }()
    @exclusivity(unchecked) var isInUpdateCallback = false
    @exclusivity(unchecked) var edgeComparators: [UInt32: [UInt32: (Any, Any) -> Bool]] = [:]
    @exclusivity(unchecked) var stickyChangedEdges: [UInt32: Set<UInt32>] = [:]
    @exclusivity(unchecked) var offsetIndirects: [UInt32: (offset: Int, size: Int)] = [:]
    @exclusivity(unchecked) var offsetFieldReaders: [UInt32: () -> Any] = [:]
    @exclusivity(unchecked) var indirectsWithOffsetInChain: Set<UInt32> = []
    @exclusivity(unchecked) var isInvalidating = false
    @exclusivity(unchecked) var deferringSubgraphInvalidationDepth = 0

    // Update machinery (see `Graph+Update.swift`).
    @exclusivity(unchecked) var frames: [UpdateFrame] = []
    @exclusivity(unchecked) @usableFromInline var evaluatingNode: UInt32 = Graph.noNode
    @exclusivity(unchecked) var isResumingStep = false
    /// Number of times a rule has been executed (recalculations) since the graph was created.
    @exclusivity(unchecked) public internal(set) var recalculationCount = 0

    // Counters behind `counter(for:)` (see `Graph+Counters.swift`).
    @exclusivity(unchecked) var transactionCount: UInt64 = 0
    @exclusivity(unchecked) var updateCount: UInt64 = 0
    @exclusivity(unchecked) var changeCount: UInt64 = 0
    @exclusivity(unchecked) var createdNodeCount: UInt64 = 0
    @exclusivity(unchecked) var countsUpdateOnNextRule = false
    /// `counter(for: .graphID)`; the default context is `graphCounterID + 1`.
    let graphCounterID: UInt64
    /// Raised by ``setNeedsUpdate()``, lowered at the start of the next top-level read of a rule.
    @exclusivity(unchecked) var needsUpdateFlag = false

    // Propagation and notifications (see `Graph+Propagation.swift` and `Graph+Observation.swift`).
    @exclusivity(unchecked) var dirtyStack: [UInt32] = []
    @exclusivity(unchecked) var pendingNotifications: [UInt32] = []
    @exclusivity(unchecked) var observers: [UInt32: [Observer]] = [:]
    @exclusivity(unchecked) var nextObserverID = 0
    @exclusivity(unchecked) var batchDepth = 0
    @exclusivity(unchecked) var isFlushing = false
    #endif

    #if DEBUG && !SAG_UNCHECKED
    let owningThread = currentThreadToken()
    #endif

    /// The subgraph every attribute is born in until ``withCurrent(_:_:)`` says otherwise. It cannot be invalidated.
    public let rootSubgraph: Subgraph

    /// Number of live attributes.
    public var nodeCount: Int { table.liveCount }

    /// The deadline in effect (set by ``withDeadline(_:_:)``), or `nil` when none is.
    public internal(set) var deadline: ContinuousClock.Instant?

    /// Creates an empty graph with a root subgraph.
    public init() {
        let tag = GraphRegistry.reserveTag()
        graphTag = tag
        graphCounterID = GraphRegistry.reserveCounterIDs()
        table.generationBase = tag << 16
        subgraphs.generationBase = tag << 16
        let root = subgraphs.allocate(parent: nil)
        rootSubgraph = Subgraph(id: root)
        currentSubgraph = root
        ThreadLocalSubgraph.resetCleared()
        GraphRegistry.bind(tag: tag, to: self)
    }

    deinit {
        GraphRegistry.release(tag: graphTag)
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

    private var nextSubgraphContextID: UInt32 = 2

    /// Creates a new invalidation context distinct from the root subgraph's default context.
    public func makeSubgraphContext() -> SubgraphContext {
        assertOwnThread()
        precondition(nextSubgraphContextID != UInt32.max, "makeSubgraphContext: context ID space exhausted")
        let id = nextSubgraphContextID
        nextSubgraphContextID += 1
        return SubgraphContext(rawValue: id)
    }

    /// Returns the invalidation context of `subgraph`.
    public func context(of subgraph: Subgraph) -> SubgraphContext {
        assertOwnThread()
        precondition(subgraphs.isLive(subgraph.id), "context(of:): the subgraph was invalidated")
        return SubgraphContext(rawValue: subgraphs.context(of: subgraph.id.index))
    }

    /// Creates a subgraph as a child of `parent` (by default the current subgraph). Attributes created while it is
    /// current belong to it, and it dies with its parent when they share the same invalidation context.
    public func makeSubgraph(parent: Subgraph? = nil, context: SubgraphContext? = nil) -> Subgraph {
        assertOwnThread()
        let owner = parent?.id ?? currentSubgraph
        precondition(subgraphs.isLive(owner), "makeSubgraph: the parent subgraph was invalidated")
        precondition(!subgraphs.isFalling(index: owner.index), "makeSubgraph: the parent subgraph is being invalidated")
        return Subgraph(id: subgraphs.allocate(parent: owner, context: context?.rawValue))
    }

    /// Links `child` under `parent` in the subgraph DAG. Rejects self-links and cycles.
    func addChild(_ child: Subgraph, to parent: Subgraph) {
        assertOwnThread()
        precondition(subgraphs.isLive(parent.id) && !subgraphs.isFalling(index: parent.id.index),
                     "addChild: the parent subgraph was invalidated")
        precondition(subgraphs.isLive(child.id) && !subgraphs.isFalling(index: child.id.index),
                     "addChild: the child subgraph was invalidated")
        subgraphs.addChild(child.id.index, to: parent.id.index)
    }

    /// Unlinks `child` from `parent` in the subgraph DAG without invalidating `child`.
    func removeChild(_ child: Subgraph, from parent: Subgraph) {
        assertOwnThread()
        precondition(subgraphs.isLive(parent.id), "removeChild: the parent subgraph was invalidated")
        precondition(subgraphs.isLive(child.id), "removeChild: the child subgraph was invalidated")
        subgraphs.removeChild(child.id.index, from: parent.id.index)
    }

    /// Runs `body` with `subgraph` as the current one, so the attributes created inside belong to it.
    public func withCurrent<T>(_ subgraph: Subgraph, _ body: () -> T) -> T {
        assertOwnThread()
        precondition(subgraphs.isLive(subgraph.id), "withCurrent: the subgraph was invalidated")
        precondition(!subgraphs.isFalling(index: subgraph.id.index), "withCurrent: the subgraph is being invalidated")
        let previous = currentSubgraph
        currentSubgraph = subgraph.id
        let previousVisible = ThreadLocalSubgraph.exchange(subgraph.id.rawValue)
        defer {
            currentSubgraph = previous
            ThreadLocalSubgraph.exchange(previousVisible)
        }
        return body()
    }

    /// Number of live subgraphs, the root included.
    public var liveSubgraphCount: Int { subgraphs.liveCount }

    /// Whether the subgraph exists (it was not freed).
    func isLive(_ subgraph: Subgraph) -> Bool { subgraphs.isLive(subgraph.id) }

    /// Whether the subgraph is valid (it is alive and has not been invalidated).
    func isValid(_ subgraph: Subgraph) -> Bool {
        assertOwnThread()
        return subgraphs.isLive(subgraph.id) && !subgraphs.isFalling(index: subgraph.id.index)
    }

    /// Whether `subgraph` is `other` or an ancestor of `other` in the subgraph DAG (`Subgraph.isAncestor(of:)` in
    /// native AttributeGraph).
    public func isAncestor(_ subgraph: Subgraph, of other: Subgraph) -> Bool {
        assertOwnThread()
        guard isValid(subgraph), isValid(other) else { return false }
        return subgraphs.isAncestor(subgraph.id.index, of: other.id.index)
    }

    /// Returns the caller-defined ``AttributeFlags`` attached to `attribute` (default `[]`).
    public func flags<Value>(of attribute: Attribute<Value>) -> AttributeFlags {
        flags(of: attribute.erased)
    }

    /// Returns the caller-defined ``AttributeFlags`` attached to `attribute` (default `[]`).
    public func flags(of attribute: AnyAttribute) -> AttributeFlags {
        assertOwnThread()
        precondition(table.isLive(attribute.id), "flags(of:): the attribute is dead")
        return AttributeFlags(rawValue: table.flags[Int(attribute.id.index)])
    }

    /// Sets the caller-defined ``AttributeFlags`` attached to `attribute`.
    public func setFlags<Value>(_ flags: AttributeFlags, for attribute: Attribute<Value>) {
        setFlags(flags, for: attribute.erased)
    }

    /// Sets the caller-defined ``AttributeFlags`` attached to `attribute`.
    public func setFlags(_ flags: AttributeFlags, for attribute: AnyAttribute) {
        assertOwnThread()
        precondition(table.isLive(attribute.id), "setFlags(_:for:): the attribute is dead")
        let n = Int(attribute.id.index)
        table.flags[n] = flags.rawValue
        if flags.rawValue != 0 && (table.state[n] & NodeState.dirty) != 0 {
            subgraphs.markDirtyFlags(flags.rawValue, on: table.owner(at: attribute.id.index))
        }
    }

    /// Whether `subgraph` or any of its valid descendant subgraphs owns a live attribute whose flags intersect `flags`
    /// (`Subgraph.intersects(flags:)` in native AttributeGraph).
    public func intersects(_ subgraph: Subgraph, flags: AttributeFlags) -> Bool {
        assertOwnThread()
        guard isValid(subgraph), flags.rawValue != 0 else { return false }
        for sgIndex in subgraphs.reverseCreationSubgraphOrder(from: subgraph.id.index) {
            for member in subgraphs.members[Int(sgIndex)] where table.isLive(index: member) {
                if (table.flags[Int(member)] & flags.rawValue) != 0 { return true }
            }
        }
        return false
    }

    /// Whether `subgraph` or any of its valid descendant subgraphs owns a live **dirty** attribute whose flags
    /// intersect `flags` (`Subgraph.isDirty(flags:)` in native AttributeGraph).
    public func isDirty(_ subgraph: Subgraph, flags: AttributeFlags) -> Bool {
        assertOwnThread()
        guard isValid(subgraph), flags.rawValue != 0 else { return false }
        let i = Int(subgraph.id.index)
        return ((subgraphs.dirtyOwnFlags[i] | subgraphs.dirtyDescendantFlags[i]) & flags.rawValue) != 0
    }

    /// Calls `body` on every live attribute in `subgraph` and its valid descendant subgraphs whose flags intersect
    /// `flags`, visiting attributes within each subgraph in reverse creation order and child subgraphs in reverse
    /// creation order (`Subgraph.forEach(_:_:)` in native AttributeGraph).
    public func forEach(in subgraph: Subgraph, flags: AttributeFlags, _ body: (AnyAttribute) -> Void) {
        assertOwnThread()
        guard isValid(subgraph), flags.rawValue != 0 else { return }
        for sgIndex in subgraphs.reverseCreationSubgraphOrder(from: subgraph.id.index) {
            let members = subgraphs.members[Int(sgIndex)]
            for member in members.reversed() where table.isLive(index: member) {
                let m = Int(member)
                if (table.flags[m] & flags.rawValue) != 0 {
                    body(AnyAttribute(id: AttributeID(index: member, generation: table.generations[m])))
                }
            }
        }
    }

    /// Updates every dirty live attribute in `subgraph` and its valid descendant subgraphs whose flags intersect
    /// `flags`, visiting attributes and child subgraphs in reverse creation order (`Subgraph.update(flags:)` in native
    /// AttributeGraph), repeating the walk until a pass updates nothing: attributes with `flags` that become dirty while
    /// it runs (for example through ``mutateBody(of:as:invalidating:_:)`` from a rule it updates) are updated in the same
    /// call. The ``isDirty(_:flags:)`` bits are cleared for `subgraph` and its descendants once the walk ends.
    public func update(_ subgraph: Subgraph, flags: AttributeFlags = .all) {
        assertOwnThread()
        guard isValid(subgraph), flags.rawValue != 0 else { return }
        withoutUpdate {
            var updatedAny = true
            while updatedAny {
                updatedAny = false
                for sgIndex in subgraphs.reverseCreationSubgraphOrder(from: subgraph.id.index) {
                    let members = subgraphs.members[Int(sgIndex)]
                    for member in members.reversed() where table.isLive(index: member) {
                        let m = Int(member)
                        if (table.flags[m] & flags.rawValue) != 0 && (table.state[m] & NodeState.dirty) != 0 {
                            update(member)
                            // A node that is still dirty (cancelled, or kept dirty by a body mutation) must not
                            // make the walk repeat forever.
                            if table.state[m] & NodeState.dirty == 0 { updatedAny = true }
                        }
                    }
                }
            }
            // Cleared only after the last pass: what became dirty during the walk was updated in this same call.
            if subgraphs.isLive(subgraph.id) {
                for sgIndex in subgraphs.reverseCreationSubgraphOrder(from: subgraph.id.index) {
                    subgraphs.clearDirtyFlags(flags.rawValue, on: sgIndex)
                }
            }
        }
        if evaluatingNode == Graph.noNode && !deferredInvalidations.isEmpty {
            flushDeferredInvalidations()
        }
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
    ///
    /// `@inlinable` so the node is built in the caller's specialization, with static types (see the closure form of `makeRule`).
    @inlinable
    public func makeInput<Value>(_ value: Value, comparison: Comparison = .viewValue) -> Attribute<Value> {
        assertOwnThread()
        let node = InputNode(value: value, type: nodeType(comparison, for: Value.self))
        return Attribute(id: allocateInput(node))
    }

    /// What the nodes of `Value` under `comparison` share, resolved once per type by the graph's cache.
    @usableFromInline
    func nodeType<Value>(_ comparison: Comparison, for type: Value.Type) -> NodeType<Value> {
        comparators.nodeType(comparison, for: Value.self)
    }

    /// The non-generic end of ``makeInput(_:comparison:)``.
    @usableFromInline
    func allocateInput(_ node: NodeBox) -> AttributeID {
        let id = allocate(node, state: NodeState.hasValue)
        changeCount &+= 1
        return id
    }

    /// The non-generic end of the closure form of `makeRule`.
    @usableFromInline
    func allocateRule(_ node: NodeBox) -> AttributeID {
        allocate(node, state: NodeState.isRule | NodeState.dirty | NodeState.pending)
    }

    /// Creates an indirect attribute that redirects to `source`, in the current subgraph.
    ///
    /// Reading the indirect attribute reads `source`; writing it writes to `source` (if the terminal source is an
    /// input). Its target can be redirected with ``setSource(_:for:)``.
    public func makeIndirect<Value>(_ source: Attribute<Value>) -> Attribute<Value> {
        assertOwnThread()
        precondition(table.isLive(source.id), "makeIndirect: the source attribute is dead")
        let s = Int(source.id.index)
        let initialState: UInt16 = NodeState.hasValue | NodeState.indirect
            | (table.state[s] & NodeState.dirty)
        let seenVersion = table.state[s] & NodeState.hasValue != 0 ? table.versions[s] : 0
        let id = allocate(IndirectNode<Value>(source: source.id, sourceSeenVersion: seenVersion), state: initialState)
        if offsetIndirects[source.id.index] != nil || indirectsWithOffsetInChain.contains(source.id.index) {
            indirectsWithOffsetInChain.insert(id.index)
        }
        rebuildIndirectEdges(for: id.index)
        return Attribute(id: id)
    }

    /// Returns the attribute that `indirect` currently redirects to.
    public func source<Value>(of indirect: Attribute<Value>) -> Attribute<Value> {
        assertOwnThread()
        precondition(table.isLive(indirect.id), "source(of:): the indirect attribute is dead")
        precondition(table.state[Int(indirect.id.index)] & NodeState.indirect != 0,
                     "source(of:): the attribute is not an indirect attribute")
        let box = table.box(at: indirect.id.index) as! IndirectNode<Value>
        return Attribute(id: box.source)
    }

    /// Redirects `indirect` to `newSource`.
    ///
    /// Setting the same source does nothing. Redirecting to a different attribute detaches the previous source and
    /// marks readers of `indirect` dirty and pending so they re-evaluate against `newSource` even when both hold equal
    /// values (matching native AttributeGraph).
    public func setSource<Value>(_ newSource: Attribute<Value>, for indirect: Attribute<Value>) {
        assertOwnThread()
        precondition(table.isLive(indirect.id), "setSource(_:for:): the indirect attribute is dead")
        precondition(table.isLive(newSource.id), "setSource(_:for:): the source attribute is dead")
        let index = indirect.id.index
        precondition(offsetFieldReaders[index] == nil,
                     "setSource(_:for:): cannot redirect an offset-field attribute")
        let n = Int(index)
        precondition(table.state[n] & NodeState.indirect != 0,
                     "setSource(_:for:): the attribute is not an indirect attribute")
        let box = table.box(at: index) as! IndirectNode<Value>
        if box.source == newSource.id { return }

        // Reject cycles through chains of indirect attributes.
        var cursor = newSource.id
        while table.isLive(cursor), table.state[Int(cursor.index)] & NodeState.indirect != 0 {
            precondition(cursor.index != index,
                         "setSource(_:for:): cycle detected (an indirect attribute cannot redirect to itself)")
            guard let nextBox = table.box(at: cursor.index) as? AnyIndirectNode else { break }
            cursor = nextBox.source
        }
        precondition(cursor.index != index,
                     "setSource(_:for:): cycle detected (an indirect attribute cannot redirect to itself)")

        let oldResolved = resolveIndirect(Attribute<Value>(id: box.source))
        let newResolved = resolveIndirect(newSource)
        let oldVal = resolvedValueIfAvailable(of: oldResolved)
        let newVal = resolvedValueIfAvailable(of: newResolved)

        let s = Int(newSource.id.index)
        box.source = newSource.id
        box.sourceSeenVersion = table.state[s] & NodeState.hasValue != 0 ? table.versions[s] : 0
        box.sourceRedirected = true
        rebuildIndirectEdges(for: index)

        let rootParentHasOffset = offsetIndirects[newSource.id.index] != nil || indirectsWithOffsetInChain.contains(newSource.id.index)
        var indQueue: [(node: UInt32, parentHasOffset: Bool)] = [(index, rootParentHasOffset)]
        var indVisited: Set<UInt32> = [index]
        var indHead = 0
        while indHead < indQueue.count {
            let (cur, parentHasOffset) = indQueue[indHead]
            indHead += 1
            let curHasOffset = offsetIndirects[cur] != nil || parentHasOffset
            if curHasOffset {
                indirectsWithOffsetInChain.insert(cur)
            } else {
                indirectsWithOffsetInChain.remove(cur)
            }
            for dep in table.outputs[Int(cur)] where table.state[Int(dep)] & NodeState.indirect != 0 {
                if indVisited.insert(dep).inserted { indQueue.append((dep, curHasOffset)) }
            }
        }

        globalVersion &+= 1
        table.versions[n] &+= 1
        let depDirty = box.dependency.map { table.isLive($0) && table.state[Int($0.index)] & NodeState.dirty != 0 } ?? false
        if table.state[s] & NodeState.dirty != 0 || depDirty {
            table.state[n] |= NodeState.dirty
        } else {
            table.state[n] &= ~NodeState.dirty
        }
        if table.state[n] & NodeState.observed != 0 { queueNotification(index) }
        if let oldVal, let newVal {
            evaluateEdgeComparators(for: index, oldValue: oldVal, newValue: newVal)
        } else {
            markStickyEdgesThroughIndirects(from: index)
        }
        for dependent in table.outputs[n] {
            if edgeComparators[dependent]?[index] != nil,
               stickyChangedEdges[dependent]?.contains(index) != true {
                continue
            }
            table.state[Int(dependent)] |= NodeState.pending
        }
        propagateDirty(from: index)
        flushNotifications()
    }

    /// Resets `indirect` back to the initial source attribute it was created with (matching
    /// `IndirectAttribute.resetSource()` in native AttributeGraph).
    public func resetSource<Value>(for indirect: Attribute<Value>) {
        assertOwnThread()
        precondition(table.isLive(indirect.id), "resetSource(for:): the indirect attribute is dead")
        let index = indirect.id.index
        precondition(offsetFieldReaders[index] == nil,
                     "resetSource(for:): cannot reset an offset-field attribute")
        precondition(table.state[Int(index)] & NodeState.indirect != 0,
                     "resetSource(for:): the attribute is not an indirect attribute")
        let box = table.box(at: index) as! IndirectNode<Value>
        setSource(Attribute(id: box.initialSource), for: indirect)
    }

    /// Returns the optional producer dependency attached to `indirect` (`IndirectAttribute.dependency` in native
    /// AttributeGraph).
    public func dependency<Value>(of indirect: Attribute<Value>) -> AnyAttribute? {
        assertOwnThread()
        precondition(table.isLive(indirect.id), "dependency(of:): the indirect attribute is dead")
        precondition(table.state[Int(indirect.id.index)] & NodeState.indirect != 0,
                     "dependency(of:): the attribute is not an indirect attribute")
        let box = table.box(at: indirect.id.index) as! IndirectNode<Value>
        guard let dep = box.dependency, table.isLive(dep) else { return nil }
        return AnyAttribute(id: dep)
    }

    /// Attaches or detaches an optional producer `dependency` in the same subgraph to `indirect`
    /// (`IndirectAttribute.dependency` in native AttributeGraph).
    ///
    /// When `dependency` becomes dirty, `indirect` and its readers become dirty; when a reader pulls `indirect`,
    /// `dependency` updates before `indirect`'s `source`. If `dependency` finishes without redirecting `indirect` and
    /// `source`'s value did not change, `indirect`'s version does not rise and downstream readers are cut.
    public func setDependency<Value>(_ dependency: AnyAttribute?, for indirect: Attribute<Value>) {
        assertOwnThread()
        precondition(table.isLive(indirect.id), "setDependency(_:for:): the indirect attribute is dead")
        let index = indirect.id.index
        precondition(offsetFieldReaders[index] == nil,
                     "setDependency(_:for:): cannot set dependency on an offset-field attribute")
        let n = Int(index)
        precondition(table.state[n] & NodeState.indirect != 0,
                     "setDependency(_:for:): the attribute is not an indirect attribute")
        if let dep = dependency {
            precondition(table.isLive(dep.id), "setDependency(_:for:): the dependency attribute is dead")
            precondition(dep.id.index != index, "setDependency(_:for:): an indirect attribute cannot depend on itself")
            precondition(table.owner(at: dep.id.index) == table.owner(at: index),
                         "setDependency(_:for:): the dependency must belong to the same subgraph as the indirect attribute")
        }
        let box = table.box(at: index) as! IndirectNode<Value>
        if box.dependency == dependency?.id { return }
        box.dependency = dependency?.id
        rebuildIndirectEdges(for: index)

        let s = Int(box.source.index)
        let depDirty = box.dependency.map { table.isLive($0) && table.state[Int($0.index)] & NodeState.dirty != 0 } ?? false
        if table.state[s] & NodeState.dirty != 0 || depDirty {
            if table.state[n] & NodeState.dirty == 0 {
                table.state[n] |= NodeState.dirty
                if table.state[n] & NodeState.observed != 0 { queueNotification(index) }
                propagateDirty(from: index)
                flushNotifications()
            }
        } else {
            table.state[n] &= ~NodeState.dirty
        }
    }

    /// Creates a rule attribute from a type that conforms to ``Rule``, in the current subgraph. The rule runs lazily.
    public func makeRule<R: Rule>(_ rule: R, comparison: Comparison = .viewValue) -> Attribute<R.Value> {
        assertOwnThread()
        let id = allocate(TypeRuleNode(rule: rule, type: comparators.nodeType(comparison, for: R.Value.self)),
                         state: NodeState.isRule | NodeState.dirty)
        return Attribute(id: id)
    }

    /// Creates a rule attribute from a closure, in the current subgraph. The closure runs lazily.
    ///
    /// `@inlinable` so the node, and the function that stores each result of the rule, are built in the caller's
    /// specialization: compiled once here, generic, they asked the runtime for type metadata on every rule created and
    /// on every run (13 % of the `fan-out` profile) [O].
    @inlinable
    public func makeRule<Value>(_ body: @escaping () -> Value, comparison: Comparison = .viewValue) -> Attribute<Value> {
        assertOwnThread()
        let type = nodeType(comparison, for: Value.self)
        if type.runClosureRule == nil {
            // Built here, in the caller's specialization: a closure without captures, so it costs no allocation.
            type.runClosureRule = { box in
                let node = unsafeDowncast(box, to: ClosureRuleNode<Value>.self)
                return node.store(node.body())
            }
        }
        return Attribute(id: allocateRule(ClosureRuleNode(body: body, type: type)))
    }

    /// Creates a stateful rule from a type that conforms to ``StatefulRule``, in the current subgraph.
    public func makeStatefulRule<R: StatefulRule>(_ rule: R, comparison: Comparison = .viewValue) -> Attribute<R.Value> {
        assertOwnThread()
        let id = allocate(StatefulRuleNode(rule: rule, type: comparators.nodeType(comparison, for: R.Value.self)),
                          state: NodeState.isRule | NodeState.dirty | NodeState.stateful)
        return Attribute(id: id)
    }

    /// Creates a stateful rule from a closure, in the current subgraph. `initialValue` is the value before the first run.
    public func makeStatefulRule<Value>(initialValue: Value? = nil, comparison: Comparison = .viewValue,
                                        _ body: @escaping (inout RuleContext<Value>) -> Void) -> Attribute<Value> {
        assertOwnThread()
        let id = allocate(ClosureStatefulRuleNode(initialValue: initialValue, body: body,
                                                  type: comparators.nodeType(comparison, for: Value.self)),
                          state: NodeState.isRule | NodeState.dirty | NodeState.stateful)
        return Attribute(id: id)
    }

    func allocate(_ box: NodeBox, state: UInt16) -> AttributeID {
        precondition(ThreadLocalSubgraph.get() != ThreadLocalSubgraph.cleared,
                     "attempting to create attribute with no subgraph")
        precondition(subgraphs.isLive(currentSubgraph), "the current subgraph was invalidated")
        precondition(!subgraphs.isFalling(index: currentSubgraph.index), "the current subgraph is being invalidated")
        let id = table.allocate(owner: currentSubgraph.index, box: box, state: state, version: 1)
        createdNodeCount &+= 1
        subgraphs.add(member: id.index, to: currentSubgraph)
        return id
    }

    private func resolvedValueIfAvailable<Value>(of resolved: Attribute<Value>) -> Value? {
        guard table.isLive(resolved.id),
              table.state[Int(resolved.id.index)] & NodeState.hasValue != 0 else { return nil }
        if let reader = offsetFieldReaders[resolved.id.index] {
            return reader() as? Value
        }
        return typedNode(resolved).value
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
    @inlinable
    public var value: Value {
        guard let graph = ThreadLocalGraph.current() else {
            preconditionFailure("Attribute.value can only be read inside a rule; use Graph.value(of:) elsewhere")
        }
        guard let box = graph.beginRuleRead(id) else { return graph.read(self) }
        return graph.finishRead(box, as: Value.self)
    }
}
