/// Spellings of native AttributeGraph that mutate the body of an attribute or add an input to it.
extension Attribute {
    /// Mutates the stored rule body of this attribute in place (`Attribute.mutateBody(as:invalidating:_:)` in native AttributeGraph).
    public func mutateBody<V>(as type: V.Type, invalidating: Bool, _ body: (inout V) -> Void) {
        graph.mutateBody(of: self, as: type, invalidating: invalidating, body)
    }

    /// Makes this attribute depend on `attribute` (`Attribute.addInput(_:options:token:)` in native AttributeGraph).
    /// `options` and `token` are accepted and not used.
    public func addInput(_ attribute: AnyAttribute, options: AGInputOptions = [], token: Int) {
        addInput(attribute)
    }

    /// The typed form of ``addInput(_:options:token:)-(AnyAttribute,_,_)``.
    public func addInput<V>(_ attribute: Attribute<V>, options: AGInputOptions = [], token: Int) {
        addInput(attribute.erased)
    }
}

extension AnyAttribute {
    /// Mutates the stored rule body of this attribute in place (`AnyAttribute.mutateBody(as:invalidating:_:)` in native AttributeGraph).
    public func mutateBody<Value>(as type: Value.Type, invalidating: Bool, _ body: (inout Value) -> Void) {
        guard let graph = GraphRegistry.graph(forTag: id.graphTag) else {
            preconditionFailure("mutateBody called after graph was released")
        }
        graph.mutateBody(of: Attribute<Void>(id: id), as: type, invalidating: invalidating, body)
    }

    /// Makes this attribute depend on `attribute` (`AnyAttribute.addInput(_:options:token:)` in native AttributeGraph).
    /// `options` and `token` are accepted and not used.
    public func addInput(_ attribute: AnyAttribute, options: AGInputOptions = [], token: Int) {
        guard let graph = GraphRegistry.graph(forTag: id.graphTag) else {
            preconditionFailure("addInput called after graph was released")
        }
        graph.addInput(self, attribute)
    }

    /// The typed form of ``addInput(_:options:token:)-(AnyAttribute,_,_)``.
    public func addInput<Value>(_ attribute: Attribute<Value>, options: AGInputOptions = [], token: Int) {
        addInput(attribute.erased, options: options, token: token)
    }

    /// The attribute whose rule is running on this thread, or `nil` outside a rule (`AnyAttribute.current` in native AttributeGraph).
    public static var current: AnyAttribute? { Graph.currentAttribute }
}

extension AnyAttribute: CustomStringConvertible {
    /// `#` followed by the raw identifier, as native prints it.
    public var description: String { "#\(id.rawValue)" }
}

extension AnyWeakAttribute: CustomStringConvertible {
    /// The description of the attribute it refers to, or `nil` when it is empty or was freed.
    public var description: String { attribute?.description ?? "nil" }
}

extension OptionalAttribute {
    /// Reads the value with `options` and reports whether it changed, or returns `nil` when empty
    /// (`OptionalAttribute.changedValue(options:)` in native AttributeGraph).
    public func changedValue(options: AGValueOptions = []) -> (value: Value, changed: Bool)? {
        attribute?.changedValue(options: options)
    }
}

extension Subgraph {
    /// Runs `body` with this subgraph as the current one and returns its result (`Subgraph.apply(_:)` in native
    /// AttributeGraph). Invalidations requested while it ran are delivered when it ends.
    public func apply<Value>(_ body: () -> Value) -> Value {
        let graph = owningGraph()
        defer { if graph.evaluatingNode == Graph.noNode && !graph.deferredInvalidations.isEmpty { graph.flushDeferredInvalidations() } }
        return graph.withCurrent(self, body)
    }

    /// Calls `callback` on every attribute of this subgraph and its descendants whose flags intersect `flags`
    /// (`Subgraph.forEach(_:_:)` in native AttributeGraph).
    public func forEach(_ flags: AnyAttribute.Flags, _ callback: (AnyAttribute) -> Void) {
        owningGraph().forEach(in: self, flags: flags, callback)
    }
}
