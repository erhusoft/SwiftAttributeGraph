/// One entry of the update stack: a node being brought up to date and the next input edge to verify.
///
/// Resuming at `next` instead of rescanning the inputs is the update-stack idea of Compute (`UpdateStack`).
struct UpdateFrame {
    var node: UInt32
    /// A nonnegative input cursor, or `-1` while a resumable rule is suspended.
    var next: Int
    /// Remembers whether an earlier input edge already had a changed version when the frame leaves to update a later
    /// dirty input edge.
    var inputChanged = false
    /// Fits the original frame's padding on 64-bit platforms; no source is freed while an update is active.
    var waiting: UInt32 = Graph.noNode
    /// Cooperative cancellation flag set by `Graph.cancelUpdate()`.
    var isCancelled = false
}

extension Graph {
    // MARK: Cancellation

    /// Cooperatively marks all active frames on the current update stack as cancelled.
    public func cancelUpdate() {
        assertOwnThread()
        precondition(!frames.isEmpty, "cancelUpdate: no update is currently running")
        for index in frames.indices {
            if frames[index].isCancelled { continue }
            frames[index].isCancelled = true
        }
    }

    /// Whether the current update frame has been marked cancelled via ``cancelUpdate()``.
    public var updateWasCancelled: Bool {
        assertOwnThread()
        precondition(!frames.isEmpty, "updateWasCancelled: no update is currently running")
        return frames[frames.count - 1].isCancelled
    }

    @inline(__always)
    var isCurrentFrameCancelled: Bool {
        !frames.isEmpty && frames[frames.count - 1].isCancelled
    }

    /// Whether any input of the currently evaluating rule changed, excluding `excluded`.
    public func anyInputsChanged(excluding excluded: [AnyAttribute] = []) -> Bool {
        precondition(evaluatingNode != Graph.noNode, "anyInputsChanged: no rule is currently evaluating")
        return anyInputChanged(of: evaluatingNode, excluding: excluded.map { $0.id.index })
    }

    // MARK: Reading

    /// The value of an attribute, bringing it up to date first if it is dirty.
    ///
    /// Inside a rule the read is recorded as a dependency of that rule.
    ///
    /// The generic part is inlined into the caller so it is specialized for `Value`: the rest of the read is the
    /// non-generic ``beginRead(_:)`` (see there for why).
    @inlinable
    public func value<Value>(of attribute: Attribute<Value>) -> Value {
        guard let box = beginRead(attribute.id) else { return readIndirect(attribute) }
        return finishRead(box, as: Value.self)
    }

    /// Everything ``value(of:)`` does before taking the value out of the node, for a node that is not indirect:
    /// returns its box, or `nil` (having done nothing) when the attribute is indirect.
    ///
    /// A fully generic `value(of:)` compiled once in this module paid, on every read, for instantiating the metadata of
    /// `TypedNode<Value>` and `Optional<Value>`, stack probes for their dynamic allocas and value-witness copies: 40 % of
    /// the `batch-writes` profile [O]. Keeping the generic part tiny and `@inlinable` lets the caller's specialization
    /// do it with static types.
    @usableFromInline
    func beginRead(_ id: AttributeID) -> NodeBox? {
        assertOwnThread()
        if let running = ThreadLocalGraph.current() {
            precondition(running === self, "a rule cannot read an attribute of another graph")
        }
        if table.isLive(id), table.state[Int(id.index)] & NodeState.indirect != 0 { return nil }
        // Native drains the update callbacks only when a rule is read, never an input [O].
        if hasPendingUpdateCallback, table.isLive(id), table.state[Int(id.index)] & NodeState.isRule != 0 {
            flushUpdateCallbackIfReady()
        }
        return beginRuleRead(id)
    }

    /// The generic slow path of ``value(of:)`` for an indirect attribute (or a dead one, which stops the program).
    @usableFromInline
    func readIndirect<Value>(_ attribute: Attribute<Value>) -> Value {
        // An indirect attribute counts as the rule (or input) it resolves to, as `clearNeedsUpdateFlags` does. The
        // resolution is only needed when a callback could fire, so the common read pays nothing for it (an extra
        // `resolveIndirect` per read cost +15 % on the 20,000-indirect benchmark, measured since 5466663).
        if hasPendingUpdateCallback, table.isLive(attribute.id) {
            let node = table.state[Int(attribute.id.index)] & NodeState.indirect != 0
                ? resolveIndirect(attribute).id.index : attribute.id.index
            if table.state[Int(node)] & NodeState.isRule != 0 { flushUpdateCallbackIfReady() }
        }
        return read(attribute)
    }

    /// The non-indirect part of ``read(_:)``: brings the node up to date, records the read and returns its box. The
    /// caller takes the value out and then calls ``endRead()``.
    @usableFromInline
    func beginRuleRead(_ id: AttributeID) -> NodeBox? {
        precondition(table.isLive(id), "reading a dead attribute (its subgraph was invalidated)")
        let index = id.index
        let n = Int(index)
        if table.state[n] & NodeState.indirect != 0 { return nil }
        readEpoch &+= 1
        if frames.isEmpty && table.state[n] & NodeState.isRule != 0 { transactionCount &+= 1; if needsUpdateFlag { clearNeedsUpdateFlags() } }
        if table.state[n] & NodeState.dirty != 0 {
            precondition(!isResumingStep, "a resumable rule must poll a dirty input and return needsInput")
            update(index)
        }
        if evaluatingNode != Graph.noNode { recordRead(of: index) }
        return table.box(at: index)
    }

    /// Takes the value out of the box that ``beginRead(_:)`` or ``beginRuleRead(_:)`` returned and ends the read.
    @inlinable
    @inline(__always)
    func finishRead<Value>(_ box: NodeBox, as type: Value.Type) -> Value {
        #if DEBUG && !SAG_UNCHECKED
        guard let node = box as? TypedNode<Value> else {
            preconditionFailure("the attribute does not hold a value of type \(Value.self)")
        }
        #else
        let node = unsafeDowncast(box, to: TypedNode<Value>.self)
        #endif
        let value = node.value.unsafelyUnwrapped
        endRead()
        return value
    }

    /// Runs the subgraph invalidations deferred during the read once no rule is running.
    @usableFromInline
    func endRead() {
        if evaluatingNode == Graph.noNode && !deferredInvalidations.isEmpty { flushDeferredInvalidations() }
    }

    /// Options for ``value(of:options:)`` (the `options` argument of `AGGraphGetValue` in native AttributeGraph).
    ///
    /// Values measured on macOS 15.8.3: options `0` and `2` behave the same in every probe [O]; `4` and `6` (`2 | 4`)
    /// also behave the same [O]. What bit `2` means beyond that is not known [?].
    public struct ReadOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        /// Native option bit 2: the read records a dependency edge. This is also the default, so it changes nothing
        /// by itself [O] (a rule with no earlier edge reading with `2` is re-evaluated when the source changes).
        public static let dependency = ReadOptions(rawValue: 2)

        /// Native option bit 4: the read does not record a dependency edge, inside or outside a rule [O]. It wins over
        /// ``dependency`` when both are set [O].
        public static let noDependency = ReadOptions(rawValue: 4)
    }

    /// The value of an attribute, bringing it up to date first if it is dirty, with the read behavior chosen by
    /// `options` (`AGGraphGetValue` with options in native AttributeGraph).
    ///
    /// With ``ReadOptions/noDependency`` the read adds no edge to the running rule [O] (a rule that reads only this way
    /// is not re-evaluated when the source changes: values `[10, 10]`, 1 run). The up-to-date value is still computed.
    /// An edge that a normal read of the same attribute recorded earlier in the same run is kept [O]. An edge from an
    /// earlier run is pruned if the later run reads only with `noDependency` [O]. Outside a rule every option returns
    /// the current value and creates no edge [O].
    public func value<Value>(of attribute: Attribute<Value>, options: ReadOptions) -> Value {
        if options.contains(.noDependency) {
            return withoutUpdate { value(of: attribute) }
        }
        return value(of: attribute)
    }

    /// The read itself, for callers that already know the running graph is this one (`Attribute.value` found it in
    /// the thread-local slot, so it skips the second lookup).
    @inline(__always)
    @usableFromInline
    func read<Value>(_ attribute: Attribute<Value>) -> Value {
        precondition(table.isLive(attribute.id), "reading a dead attribute (its subgraph was invalidated)")
        let index = attribute.id.index
        let n = Int(index)

        // An indirect attribute redirects to another attribute: bringing the indirect up to date updates its source,
        // and the reader records a single dependency edge on the indirect attribute itself.
        if table.state[n] & NodeState.indirect != 0 {
            readEpoch &+= 1
            if table.state[n] & NodeState.dirty != 0 {
                precondition(!isResumingStep, "a resumable rule must poll a dirty input and return needsInput")
                update(index)
            }
            if evaluatingNode != Graph.noNode { recordRead(of: index) }
            if let reader = offsetFieldReaders[index] {
                guard let result = reader() as? Value else {
                    preconditionFailure("offsetFieldReaders: projected field type mismatch")
                }
                return result
            }
            let resolved = resolveIndirect(attribute)
            if frames.isEmpty && table.state[Int(resolved.id.index)] & NodeState.isRule != 0 { transactionCount &+= 1; if needsUpdateFlag { clearNeedsUpdateFlags() } }
            if let reader = offsetFieldReaders[resolved.id.index] {
                guard let result = reader() as? Value else {
                    preconditionFailure("offsetFieldReaders: projected field type mismatch")
                }
                if evaluatingNode == Graph.noNode && !deferredInvalidations.isEmpty { flushDeferredInvalidations() }
                return result
            }
            if table.state[Int(resolved.id.index)] & NodeState.dirty != 0 {
                precondition(!isResumingStep, "a resumable rule must poll a dirty input and return needsInput")
                update(resolved.id.index)
            }
            let value = typedNode(resolved).value.unsafelyUnwrapped
            if evaluatingNode == Graph.noNode && !deferredInvalidations.isEmpty { flushDeferredInvalidations() }
            return value
        }

        return finishRead(beginRuleRead(attribute.id).unsafelyUnwrapped, as: Value.self)
    }

    /// Runs `body` without recording dependency edges on the currently evaluating rule (`Graph.withoutUpdate` in
    /// native AttributeGraph).
    ///
    /// Dirty attributes read inside `body` still evaluate normally to produce their up-to-date value, but no edge is
    /// added from those attributes to the outer rule.
    public func withoutUpdate<T>(_ body: () -> T) -> T {
        assertOwnThread()
        let previousNode = evaluatingNode
        let previousResuming = isResumingStep
        evaluatingNode = Graph.noNode
        isResumingStep = false
        defer {
            evaluatingNode = previousNode
            isResumingStep = previousResuming
        }
        return body()
    }

    /// Static convenience for ``withoutUpdate(_:)-5k18s`` that uses the graph whose rule is currently running on this
    /// thread (or runs `body` directly if no rule is running).
    public static func withoutUpdate<T>(_ body: () -> T) -> T {
        let token = clearUpdate()
        defer { setUpdate(token) }
        return body()
    }

    private final class UpdateToken {
        let graph: Graph?
        let evaluatingNode: UInt32
        let isResumingStep: Bool

        init(graph: Graph?, evaluatingNode: UInt32, isResumingStep: Bool) {
            self.graph = graph
            self.evaluatingNode = evaluatingNode
            self.isResumingStep = isResumingStep
        }
    }

    /// Clears the current thread-local rule update state and returns an opaque token to restore it later via
    /// ``setUpdate(_:)`` (`AGGraphClearUpdate` in native AttributeGraph).
    ///
    /// [O] Returns a non-nil opaque token even when called nested or outside a rule; reads performed while cleared do
    /// not record dependency edges. Every `clearUpdate()` call must be balanced with ``setUpdate(_:)`` to release the
    /// retained token.
    public static func clearUpdate() -> UnsafeRawPointer? {
        guard let graph = ThreadLocalGraph.current() else {
            let empty = UpdateToken(graph: nil, evaluatingNode: Graph.noNode, isResumingStep: false)
            return UnsafeRawPointer(Unmanaged.passRetained(empty).toOpaque())
        }
        graph.assertOwnThread()
        let token = UpdateToken(graph: graph, evaluatingNode: graph.evaluatingNode, isResumingStep: graph.isResumingStep)
        graph.evaluatingNode = Graph.noNode
        graph.isResumingStep = false
        return UnsafeRawPointer(Unmanaged.passRetained(token).toOpaque())
    }

    /// Restores the thread-local rule update state from a token returned by ``clearUpdate()`` (`AGGraphSetUpdate` in
    /// native AttributeGraph).
    public static func setUpdate(_ token: UnsafeRawPointer?) {
        guard let token else { return }
        let state = Unmanaged<UpdateToken>.fromOpaque(token).takeRetainedValue()
        guard let graph = state.graph else { return }
        graph.assertOwnThread()
        graph.evaluatingNode = state.evaluatingNode
        graph.isResumingStep = state.isResumingStep
    }

    /// The attribute whose rule is running on this thread, or `nil` outside a rule (`AGGraphGetCurrentAttribute` in
    /// native AttributeGraph).
    ///
    /// [O] `nil` outside any rule and while the update state is cleared (``clearUpdate()``, ``withoutUpdate(_:)-5k18s``);
    /// inside a rule it is that rule's attribute, on every run; inside a rule nested by a read it is the inner
    /// attribute, and back in the outer body it is the outer one again; the same for stateful rules. A resumable rule's
    /// steps are an engine feature without a native counterpart [?].
    public static var currentAttribute: AnyAttribute? {
        guard let graph = ThreadLocalGraph.current(), graph.evaluatingNode != Graph.noNode else { return nil }
        let node = graph.evaluatingNode
        return AnyAttribute(id: AttributeID(index: node, generation: graph.table.generations[Int(node)]))
    }

    /// Whether the running rule's attribute was modified (`AGGraphCurrentAttributeWasModified` in native
    /// AttributeGraph).
    ///
    /// [O] Natively this was `false` in every measured case: outside a rule, in plain rules, in stateful rules before
    /// and after writing their value (a different or an equal value, through the context or through
    /// `AGGraphSetOutputValue`), in stateful rules that do not write, and in an outer rule after an inner stateful rule
    /// wrote. [?] The condition that makes it `true` was not found (writing a rule attribute from outside is refused
    /// natively, and `AGGraphSetValue`/`AGGraphInvalidateValue` on the current attribute aborted), so this always
    /// returns `false`.
    public static var currentAttributeWasModified: Bool {
        guard let graph = ThreadLocalGraph.current(), graph.evaluatingNode != Graph.noNode else { return false }
        return (graph.table.state[Int(graph.evaluatingNode)] & NodeState.selfModified) != 0
    }

    /// Whether `attribute` currently holds a computed or initial value (`Attribute.hasValue` in native
    /// AttributeGraph).
    ///
    /// Inputs and indirect attributes always report `true`; rules report `false` until they have completed their first
    /// evaluation.
    public func hasValue<Value>(of attribute: Attribute<Value>) -> Bool {
        hasValue(of: attribute.erased)
    }

    /// Whether `attribute` currently holds a computed or initial value (`AnyAttribute.hasValue` in native
    /// AttributeGraph).
    public func hasValue(of attribute: AnyAttribute) -> Bool {
        assertOwnThread()
        precondition(table.isLive(attribute.id), "hasValue(of:): the attribute is dead")
        return table.state[Int(attribute.id.index)] & NodeState.hasValue != 0
    }

    /// Brings `attribute` up to date if it is dirty, without recording a dependency edge on any currently running rule
    /// (`Attribute.updateValue()` in native AttributeGraph).
    public func updateValue<Value>(of attribute: Attribute<Value>) {
        updateValue(of: attribute.erased)
    }

    /// Brings `attribute` up to date if it is dirty, without recording a dependency edge on any currently running rule
    /// (`AnyAttribute.updateValue()` in native AttributeGraph).
    public func updateValue(of attribute: AnyAttribute) {
        assertOwnThread()
        precondition(table.isLive(attribute.id), "updateValue(of:): the attribute is dead")
        let index = attribute.id.index
        let n = Int(index)
        withoutUpdate {
            if table.state[n] & NodeState.dirty != 0 {
                update(index)
            }
            if table.state[n] & NodeState.indirect != 0 {
                var current = attribute.id
                while table.isLive(current), table.state[Int(current.index)] & NodeState.indirect != 0 {
                    let box = table.box(at: current.index) as! AnyIndirectNode
                    current = box.source
                }
                if table.isLive(current), table.state[Int(current.index)] & NodeState.dirty != 0 {
                    update(current.index)
                }
            }
        }
        if evaluatingNode == Graph.noNode && !deferredInvalidations.isEmpty { flushDeferredInvalidations() }
    }

    /// Asserts that `attribute` is alive and structurally valid in the graph (`Attribute.validate()` in native
    /// AttributeGraph). Does not evaluate dirty rules or record dependency edges.
    public func validate<Value>(_ attribute: Attribute<Value>) {
        validate(attribute.erased)
    }

    /// Asserts that `attribute` is alive and structurally valid in the graph (`AnyAttribute.validate()` in native
    /// AttributeGraph). Does not evaluate dirty rules or record dependency edges.
    public func validate(_ attribute: AnyAttribute) {
        assertOwnThread()
        precondition(table.isLive(attribute.id), "validate(_:): the attribute is dead")
    }

    /// Marks a rule attribute dirty and pending so it is forced to re-evaluate on its next read even if none of its
    /// inputs changed (`Attribute.invalidateValue()` in native AttributeGraph), and propagates dirty to its readers.
    public func invalidateValue<Value>(of attribute: Attribute<Value>) {
        invalidateValue(of: attribute.erased)
    }

    /// Marks a rule attribute dirty and pending so it is forced to re-evaluate on its next read even if none of its
    /// inputs changed (`AnyAttribute.invalidateValue()` in native AttributeGraph), and propagates dirty to its readers.
    ///
    /// Like native AttributeGraph, a rule that is running and tracking its reads must not call it: the program stops
    /// ("setting value during update"). Inside ``withoutUpdate(_:)-5k18s`` the call is accepted. To change a rule from
    /// inside another rule, use ``mutateBody(of:as:invalidating:_:)`` with `invalidating: true`.
    public func invalidateValue(of attribute: AnyAttribute) {
        assertOwnThread()
        precondition(evaluatingNode == Graph.noNode, "invalidateValue(of:): setting value during update")
        precondition(table.isLive(attribute.id), "invalidateValue(of:): the attribute is dead")
        invalidateRuleValue(attribute)
    }

    /// Marks every live rule attribute dirty and pending, so each one re-evaluates on its next read while keeping its
    /// stored value (`AGGraphInvalidateAllValues` in native AttributeGraph; the oracle scenario
    /// `invalidate-all-values` measures that `hasValue` stays true and the read runs the rule again). Input attributes
    /// are not touched. Like ``invalidateValue(of:)-(AnyAttribute)``, it must not run inside a rule.
    public func invalidateAllValues() {
        assertOwnThread()
        precondition(evaluatingNode == Graph.noNode, "invalidateAllValues(): setting value during update")
        for n in 0..<table.slotCount {
            guard table.isLive(index: UInt32(n)), table.state[n] & NodeState.isRule != 0 else { continue }
            invalidateRuleValue(AnyAttribute(id: AttributeID(index: UInt32(n), generation: table.generations[n])))
        }
    }

    /// The invalidation shared by ``invalidateValue(of:)-(AnyAttribute)`` and ``mutateBody(of:as:invalidating:_:)``;
    /// it does not check whether a rule is running.
    func invalidateRuleValue(_ attribute: AnyAttribute) {
        let index = attribute.id.index
        let n = Int(index)
        precondition(table.state[n] & NodeState.isRule != 0, "invalidateValue(of:): only rule attributes can be invalidated")
        let wasDirty = table.state[n] & NodeState.dirty != 0
        table.state[n] |= NodeState.dirty | NodeState.pending | NodeState.selfModified
        if table.flags[n] != 0 { subgraphs.markDirtyFlags(table.flags[n], on: table.owner(at: index)) }
        if !wasDirty && (table.state[n] & NodeState.observed != 0) {
            queueNotification(index)
        }
        propagateDirty(from: index)
        flushNotifications()
    }

    /// Mutates the stored ``Rule`` or ``StatefulRule`` body of `attribute` in place (`Attribute.mutateBody` in native
    /// AttributeGraph).
    ///
    /// When `invalidating` is `true`, ``invalidateValue(of:)-(Attribute<Value>)`` is called after `body` finishes so
    /// the attribute and its readers are marked dirty and the rule is forced to re-run on its next read. When
    /// `invalidating` is `false`, the attribute's dirty state is left untouched.
    public func mutateBody<R, Value>(of attribute: Attribute<Value>, as type: R.Type, invalidating: Bool,
                                     _ body: (inout R) -> Void) {
        assertOwnThread()
        precondition(table.isLive(attribute.id), "mutateBody(of:as:invalidating:_:): the attribute is dead")
        let box = table.box(at: attribute.id.index)
        guard box.mutateRuleBody(as: type, body) else {
            preconditionFailure("mutateBody(of:as:invalidating:_:): the attribute does not hold a rule of type \(R.self)")
        }
        if invalidating {
            invalidateRuleValue(attribute.erased)
            if evaluatingNode != Graph.noNode {
                // Readers on the update stack keep this update's value but stay dirty (native parity).
                for reader in table.outputs[Int(attribute.id.index)]
                where table.state[Int(reader)] & NodeState.evaluating != 0 {
                    table.state[Int(reader)] |= NodeState.staysDirty
                }
            }
        }
    }

    /// Ends a frame of a node marked ``NodeState/staysDirty``: the node is dirty again, and so are its readers.
    @inline(__always)
    func settleStaysDirty(_ node: UInt32) {
        let n = Int(node)
        guard table.state[n] & NodeState.staysDirty != 0 else { return }
        table.state[n] = (table.state[n] & ~NodeState.staysDirty) | NodeState.dirty
        propagateDirty(from: node)
    }

    // MARK: Writing

    /// Writes a new value into an input attribute. If it counts as equal under the attribute's comparison policy,
    /// nothing happens; otherwise the version rises, the readers are marked dirty and observers are notified.
    ///
    /// The generic part is inlined into the caller so the comparison and the store are specialized for `Value`, the way
    /// ``value(of:)`` is: compiled once here, generic, every write asked the runtime for the metadata of
    /// `Optional<Value>` and copied the old and new values through value witnesses [O].
    @inlinable
    public func setValue<Value>(_ value: Value, for attribute: Attribute<Value>) {
        guard let box = beginWrite(attribute.id) else { return setValueSlowly(value, for: attribute) }
        #if DEBUG && !SAG_UNCHECKED
        guard let node = box as? TypedNode<Value> else {
            preconditionFailure("the attribute does not hold a value of type \(Value.self)")
        }
        #else
        let node = unsafeDowncast(box, to: TypedNode<Value>.self)
        #endif
        if node.store(value) { endWrite(attribute.id.index) }
    }

    /// The checks of ``setValue(_:for:)``. Returns the box of a plain input when the write can take the fast path (the
    /// attribute is not indirect and no edge of the graph is compared partially), `nil` otherwise.
    @usableFromInline
    func beginWrite(_ id: AttributeID) -> NodeBox? {
        assertOwnThread()
        precondition(evaluatingNode == Graph.noNode, "setValue(_:for:): a rule must not write to the graph")
        precondition(table.isLive(id), "setValue(_:for:): the attribute is dead (its subgraph was invalidated)")
        let index = Int(id.index)
        precondition(table.state[index] & NodeState.isRule == 0, "setValue(_:for:): cannot write to a rule")
        if table.state[index] & NodeState.indirect != 0 || hasPartialEdgeComparison { return nil }
        return table.box(at: id.index)
    }

    /// What a write that changed the value of input `node` does after storing it: bumps the versions, marks the readers
    /// dirty and notifies observers.
    @usableFromInline
    func endWrite(_ node: UInt32) {
        let index = Int(node)
        globalVersion &+= 1
        changeCount &+= 1
        table.versions[index] &+= 1
        if table.state[index] & NodeState.observed != 0 { queueNotification(node) }
        propagateDirty(from: node)
        flushNotifications()
    }

    /// The generic path of ``setValue(_:for:)`` once its checks passed: an indirect attribute, or a graph with partial
    /// edge comparisons.
    @usableFromInline
    func setValueSlowly<Value>(_ value: Value, for attribute: Attribute<Value>) {
        let index = Int(attribute.id.index)
        // An indirect attribute redirects to another attribute: writing it writes to the terminal source.
        if table.state[index] & NodeState.indirect != 0 {
            precondition(offsetFieldReaders[attribute.id.index] == nil,
                         "setValue(_:for:): cannot write to an offset-field attribute")
            setValue(value, for: resolveIndirect(attribute))
            return
        }

        let oldValue = hasPartialEdgeComparison ? typedNode(attribute).value : nil
        guard typedNode(attribute).store(value) else { return }
        globalVersion &+= 1
        changeCount &+= 1
        table.versions[index] &+= 1
        if table.state[index] & NodeState.observed != 0 { queueNotification(UInt32(index)) }
        if let oldValue {
            evaluateEdgeComparators(for: UInt32(index), oldValue: oldValue, newValue: value)
        }
        propagateDirty(from: UInt32(index))
        flushNotifications()
    }

    // MARK: Updating

    /// Brings a dirty node up to date with an explicit stack: no recursion that depends on the graph's depth.
    ///
    /// A dirty node verifies all its previous input edges in ascending attribute index order, bringing dirty rules up
    /// to date first. Only then, if any input's version differs from the one it saw (or the node never ran or lost an
    /// input), does its own rule run. If no input changed, the rule is skipped and the node is marked clean.
    ///
    /// A rule that reads an input it did not read before reaches this function again from inside the rule; that
    /// nested call still uses the native stack and is the documented limit that M4 removes.
    func update(_ root: UInt32) {
        let base = frames.count
        // An indirect attribute is transparent: the update it starts is counted when it reaches its first rule.
        if base == 0 {
            if table.state[Int(root)] & NodeState.indirect != 0 { countsUpdateOnNextRule = true } else { updateCount &+= 1 }
        }
        defer { countsUpdateOnNextRule = false }
        push(root)
        outer: while frames.count > base {
            let top = frames.count - 1
            let node = frames[top].node
            let n = Int(node)
            if frames[top].isCancelled {
                table.state[n] = (table.state[n] & ~NodeState.evaluating) | NodeState.dirty | NodeState.pending
                frames.removeLast()
                continue
            }
            if frames[top].next < 0 {
                advanceResumable(top: top, firstStep: false)
                continue
            }
            var mustRun = table.state[n] & NodeState.hasValue == 0 || table.state[n] & NodeState.pending != 0
                || frames[top].inputChanged

            var i = frames[top].next
            // Common case: no partial edge comparator on this node and no offset attribute in the graph, so any changed
            // version means "must run" and the scan needs no dictionary lookup.
            if offsetIndirects.isEmpty && (edgeComparators.isEmpty || edgeComparators[node] == nil) {
                let scan = table.scanInputs(of: n, from: i)
                if scan.changed { mustRun = true }
                if scan.stop < table.inputs[n].count {
                    frames[top].next = scan.stop
                    frames[top].inputChanged = mustRun
                    push(table.inputs[n][scan.stop].source)
                    continue outer
                }
                i = scan.stop
            }
            while i < table.inputs[n].count {
                let edge = table.inputs[n][i]
                let source = Int(edge.source)
                if table.state[source] & NodeState.dirty != 0 {
                    frames[top].next = i
                    frames[top].inputChanged = mustRun
                    push(edge.source)
                    continue outer
                }
                if table.versions[source] != edge.seenVersion {
                    if edgeComparators[node]?[edge.source] != nil || hasOffsetInChain(edge.source) {
                        if stickyChangedEdges[node]?.contains(edge.source) == true {
                            mustRun = true
                        } else {
                            table.inputs[n][i].seenVersion = table.versions[source]
                        }
                    } else {
                        mustRun = true
                    }
                }
                i += 1
            }

            if table.state[n] & NodeState.indirect != 0 {
                if let box = table.box(at: node) as? AnyIndirectNode {
                    let s = Int(box.source.index)
                    if table.state[s] & NodeState.dirty != 0 {
                        frames[top].next = table.inputs[n].count
                        frames[top].inputChanged = mustRun
                        push(box.source.index)
                        continue outer
                    }
                    let currentSourceVersion = table.versions[s]
                    let sourceChanged = box.sourceRedirected || currentSourceVersion != box.sourceSeenVersion
                    box.sourceSeenVersion = currentSourceVersion
                    box.sourceRedirected = false
                    for idx in table.inputs[n].indices {
                        let edgeSource = Int(table.inputs[n][idx].source)
                        table.inputs[n][idx].seenVersion = table.versions[edgeSource]
                    }
                    if sourceChanged {
                        globalVersion &+= 1
                        table.versions[n] &+= 1
                    }
                }
                table.state[n] &= ~(NodeState.dirty | NodeState.evaluating | NodeState.pending)
                settleStaysDirty(node)
                frames.removeLast()
                continue
            }

            if mustRun {
                if table.state[n] & NodeState.resumable != 0 {
                    advanceResumable(top: top, firstStep: true)
                    continue
                }
                run(node)
            } else {
                table.state[n] &= ~(NodeState.dirty | NodeState.evaluating | NodeState.selfModified)
                settleStaysDirty(node)
            }
            frames.removeLast()
        }
    }

    func push(_ node: UInt32) {
        let n = Int(node)
        precondition(table.state[n] & NodeState.evaluating == 0,
                     "cycle detected: an attribute depends on itself through its own rule")
        table.state[n] |= NodeState.evaluating
        // A node without a value that is first evaluated inside another update counts as one more update.
        if table.state[n] & NodeState.indirect == 0 {
            if countsUpdateOnNextRule {
                countsUpdateOnNextRule = false
                updateCount &+= 1
            } else if !frames.isEmpty && table.state[n] & NodeState.hasValue == 0 {
                updateCount &+= 1
            }
        }
        frames.append(UpdateFrame(node: node, next: 0))
    }

    /// Runs the rule of a node, rebuilds its input edges from what it read and bumps its version if the value changed.
    private func run(_ node: UInt32) {
        let n = Int(node)
        table.beginRun(of: n)

        let previousNode = evaluatingNode
        evaluatingNode = node
        // A run nested in a rule of this graph finds the thread-local slot already holding this graph: it is read, and
        // written (and restored) only when it holds something else. Swapping it unconditionally cost three
        // thread-local calls per run, and `pthread_get/setspecific` were 6 % of the `diamond-layers` profile [O].
        let previousGraph = ThreadLocalGraph.current()
        let swapsGraph = previousGraph !== self
        if swapsGraph { ThreadLocalGraph.set(self) }
        let previousSubgraph = currentSubgraph
        let owner = table.owner(at: node)
        if !subgraphs.isLive(currentSubgraph) || subgraphs.isFalling(index: currentSubgraph.index) {
            currentSubgraph = subgraphForCreating(in: owner)
        }

        recalculationCount &+= 1
        let changed = table.box(at: node).evaluate(in: self, node: node)

        currentSubgraph = previousSubgraph
        if swapsGraph { ThreadLocalGraph.set(previousGraph) }
        evaluatingNode = previousNode

        if !frames.isEmpty, frames[frames.count - 1].isCancelled {
            table.state[n] = (table.state[n] & ~NodeState.evaluating) | NodeState.dirty | NodeState.pending | NodeState.hasValue
            return
        }

        pruneEdges(of: node)
        table.state[n] = (table.state[n] & ~(NodeState.dirty | NodeState.evaluating | NodeState.pending | NodeState.selfModified))
            | NodeState.hasValue
        if changed {
            globalVersion &+= 1
            changeCount &+= 1
            table.versions[n] &+= 1
        } else {
            for dependent in table.outputs[n] {
                let dep = Int(dependent)
                if table.state[dep] & NodeState.dirty != 0,
                   table.state[dep] & (NodeState.pending | NodeState.stateful) == 0,
                   table.inputs[dep].count == 1,
                   table.inputs[dep][0].source == node,
                   table.inputs[dep][0].seenVersion == table.versions[n] {
                    table.state[dep] &= ~NodeState.dirty
                }
            }
        }
        settleStaysDirty(node)
    }

    /// Where a running rule creates attributes when the caller's current subgraph is being invalidated: the subgraph
    /// that owns the rule (observed in native AttributeGraph), or, when that one is falling too, its nearest ancestor
    /// that is not (kept from M5; not observed natively). With a live caller subgraph, rules create there: evaluating a
    /// rule does not change the current subgraph, as in native AttributeGraph.
    func subgraphForCreating(in owner: UInt32) -> SubgraphID {
        if !subgraphs.isFalling(index: owner) {
            return subgraphs.id(at: owner)
        }
        var queue: [UInt32] = subgraphs.parents(of: owner)
        var visited: Set<UInt32> = [owner]
        var head = 0
        while head < queue.count {
            let candidate = queue[head]
            head += 1
            if !visited.insert(candidate).inserted { continue }
            if !subgraphs.isFalling(index: candidate) {
                return subgraphs.id(at: candidate)
            }
            for p in subgraphs.parents(of: candidate) where !visited.contains(p) {
                queue.append(p)
            }
        }
        return rootSubgraph.id
    }

    // MARK: What changed (for stateful rules)

    /// Whether the edge from `source` into `node` was changed when the node's run began; `nil` if there is no such edge.
    @inline(__always)
    @usableFromInline
    func inputChanged(of node: UInt32, source: UInt32) -> Bool? {
        let edges = table.inputs[Int(node)]
        var low = 0, high = edges.count
        while low < high {
            let mid = (low + high) >> 1
            let midSource = edges[mid].source
            if midSource == source { return edges[mid].changed }
            if midSource < source { low = mid + 1 } else { high = mid }
        }
        return nil
    }

    /// Whether any input edge of `node` was changed, ignoring `excluded`.
    @usableFromInline func anyInputChanged(of node: UInt32, excluding excluded: [UInt32]) -> Bool {
        let n = Int(node)
        for edge in table.inputs[n] where edge.changed && !excluded.contains(edge.source) { return true }
        return false
    }

    // MARK: Tracking

    /// Reads `input` and records a dependency edge against `reader` rather than the currently evaluating rule
    /// (`AGGraphGetInputValue` in native AttributeGraph).
    public func inputValue<Value>(of input: Attribute<Value>, for reader: AnyAttribute) -> Value {
        assertOwnThread()
        let result = withoutUpdate { value(of: input) }
        let readerIndex = reader.id.index
        if table.state[Int(readerIndex)] & NodeState.isRule != 0 {
            recordRead(of: input.id.index, by: readerIndex, keepForNextPrune: true)
        }
        return result
    }

    /// Records that the running rule read `source`. Edges are kept sorted by ascending `source` index; edges not
    /// marked `read` when the rule ends are pruned by `pruneEdges(of:)`.
    @usableFromInline func recordRead(of source: UInt32) {
        recordRead(of: source, by: evaluatingNode)
    }

    @usableFromInline func recordRead(of source: UInt32, by consumerNode: UInt32, keepForNextPrune: Bool = false) {
        let consumer = Int(consumerNode)
        precondition(source != consumerNode, "a rule cannot read itself")
        guard let low = table.markRead(of: source, by: consumer) else { return }
        let version = table.versions[Int(source)]

        // New edge, appended or inserted in the middle: the same bookkeeping for both. The reader is always
        // `consumerNode` (outside a rule `evaluatingNode` is `noNode`), and `positionInOutputs` is where it sits in
        // the source's output list. [O] verified against get-input-value-dup-prune; [?] mid-list insertion has no
        // native probe of its own.
        table.outputs[Int(source)].append(consumerNode)
        let position = UInt32(table.outputs[Int(source)].count - 1)
        table.addInput(InputEdge(source: source, seenVersion: version, read: true, keepForNextPrune: keepForNextPrune,
                                 changed: true, positionInOutputs: position), at: low, of: consumer)
        if subgraphs.context(of: table.owner(at: consumerNode)) != subgraphs.context(of: table.owner(at: source)) {
            table.state[consumer] |= NodeState.hasCrossContextInput
        }
    }

    /// Removes the edges that the rule did not read in its last run (mark-and-sweep preserving ascending `source` order).
    func pruneEdges(of node: UInt32) {
        let n = Int(node)
        if table.keepAllInputsIfAllRead(of: n) { return }
        let count = table.inputs[n].count
        var writeIndex = 0
        for readIndex in 0..<count {
            let edge = table.inputs[n][readIndex]
            if edge.read {
                var kept = edge
                kept.changed = false
                table.inputs[n][writeIndex] = kept
                writeIndex += 1
            } else {
                edgeComparators[node]?.removeValue(forKey: edge.source)
                stickyChangedEdges[node]?.remove(edge.source)
                removeOutput(node, from: edge.source, at: edge.positionInOutputs)
            }
        }
        if writeIndex < count {
            table.inputs[n].removeSubrange(writeIndex..<count)
        }
    }

    /// Removes `dependent` from the output list of `source` at the given position (swap with the last: the list has
    /// no order). The position must be the position of `dependent` in `outputs[source]`, as recorded in the edge's
    /// `positionInOutputs`. O(1) instead of O(degree).
    func removeOutput(_ dependent: UInt32, from source: UInt32, at position: UInt32) {
        let s = Int(source)
        let p = Int(position)
        guard p < table.outputs[s].count else { return }
        let last = table.outputs[s].count - 1
        if p != last {
            let movedNode = table.outputs[s][last]
            table.outputs[s][p] = movedNode
            // Keep the moved node's edge position up to date.
            updatePositionInOutputs(movedNode, from: source, to: UInt32(p))
        }
        table.outputs[s].removeLast()
        parkCachedNodeIfUnreferenced(source)
    }

    /// Finds the edge of `node` that reads `source` and updates its `positionInOutputs` to `position`.
    /// O(log(number of inputs of `node`)).
    @inline(__always)
    func updatePositionInOutputs(_ node: UInt32, from source: UInt32, to position: UInt32) {
        let n = Int(node)
        var low = 0, high = table.inputs[n].count
        while low < high {
            let mid = (low + high) >> 1
            let midSource = table.inputs[n][mid].source
            if midSource == source {
                table.inputs[n][mid].positionInOutputs = position
                return
            }
            if midSource < source { low = mid + 1 } else { high = mid }
        }
    }
}
