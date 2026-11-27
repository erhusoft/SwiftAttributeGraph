/// Attribute accessors with the names Apple uses in `AGAttribute` (`hasValue`, `flags`; `value` already exists inside rules) [O, native headers
/// AGAttribute.h]. They resolve the owning graph from the attribute's tag. The graph-level methods stay for hot paths.
extension Attribute {
    /// Whether the attribute has a value (`AGAttribute.hasValue`).
    public var hasValue: Bool {
        guard let graph = GraphRegistry.graph(forTag: id.graphTag) else { return false }
        return graph.hasValue(of: self)
    }

    /// The attribute's flags (`AGAttribute.flags`).
    public var flags: AttributeFlags {
        get {
            guard let graph = GraphRegistry.graph(forTag: id.graphTag) else { return [] }
            return graph.flags(of: self)
        }
        nonmutating set {
            guard let graph = GraphRegistry.graph(forTag: id.graphTag) else {
                preconditionFailure("Attribute flags set after its graph was released")
            }
            graph.setFlags(newValue, for: self)
        }
    }

    /// Updates this attribute's flags using a bitmask (`AGAttribute.setFlags(_:mask:)`).
    ///
    /// Bitwise equivalent to `flags = (flags & ~mask) | (newFlags & mask)`.
    public func setFlags(_ newFlags: AttributeFlags, mask: AttributeFlags) {
        guard let graph = GraphRegistry.graph(forTag: id.graphTag) else {
            preconditionFailure("Attribute flags set after its graph was released")
        }
        let current = graph.flags(of: self)
        let updated = AttributeFlags(rawValue: (current.rawValue & ~mask.rawValue) | (newFlags.rawValue & mask.rawValue))
        graph.setFlags(updated, for: self)
    }

    /// Makes `target` depend on `dependency` as an input (`AGGraphAddInput`).
    public func addInput(_ dependency: AnyAttribute) {
        guard let graph = GraphRegistry.graph(forTag: id.graphTag) else {
            preconditionFailure("addInput called after graph was released")
        }
        graph.addInput(self.erased, dependency)
    }

    /// Performs a breadth-first traversal starting at this attribute (`Attribute.breadthFirstSearch(options:_:)`).
    @discardableResult
    public func breadthFirstSearch(options: SearchOptions = [], _ body: (AnyAttribute) -> Bool) -> Bool {
        guard let graph = GraphRegistry.graph(forTag: id.graphTag) else {
            preconditionFailure("breadthFirstSearch called after graph was released")
        }
        return graph.breadthFirstSearch(from: self, options: options, body)
    }

    /// Visits the stored body of this attribute using `visitor` (`Attribute.visitBody`).
    public func visitBody<V: AttributeBodyVisitor>(_ visitor: inout V) {
        precondition(graph.table.isLive(erased.id), "visitBody: the attribute is dead")
        graph.table.box(at: erased.id.index).visitBody(&visitor)
    }

    /// The graph value state of the attribute (`AGAttribute.valueState`).
    public var valueState: ValueState {
        graph.valueStateImpl(of: erased)
    }

    /// The subgraph that owns this attribute (`AGAttribute.subgraph`).
    public var subgraph: Subgraph {
        graph.subgraphImpl(of: erased)
    }

    /// The subgraph that owns this attribute, or `nil` if it was freed (`AGAttribute.subgraphOrNil`).
    public var subgraphOrNil: Subgraph? {
        guard let owner = GraphRegistry.graph(forTag: id.graphTag) else { return nil }
        return owner.subgraphOrNilImpl(of: erased)
    }

    /// The source attribute if this is an indirect attribute (`AGAttribute.source`).
    public var source: Attribute<Value> {
        get { Attribute(id: graph.sourceImpl(of: erased).id) }
        nonmutating set { graph.setSource(newValue, for: self) }
    }
}

extension AnyAttribute {
    /// Whether the attribute has a value (`AGAttribute.hasValue`).
    public var hasValue: Bool {
        guard let graph = GraphRegistry.graph(forTag: id.graphTag) else { return false }
        return graph.hasValue(of: self)
    }

    /// The attribute's flags (`AGAttribute.flags`).
    public var flags: AttributeFlags {
        get {
            guard let graph = GraphRegistry.graph(forTag: id.graphTag) else { return [] }
            return graph.flags(of: self)
        }
        nonmutating set {
            guard let graph = GraphRegistry.graph(forTag: id.graphTag) else {
                preconditionFailure("Attribute flags set after its graph was released")
            }
            graph.setFlags(newValue, for: self)
        }
    }

    /// Updates this attribute's flags using a bitmask (`AGAttribute.setFlags(_:mask:)`).
    ///
    /// Bitwise equivalent to `flags = (flags & ~mask) | (newFlags & mask)`.
    public func setFlags(_ newFlags: AttributeFlags, mask: AttributeFlags) {
        guard let graph = GraphRegistry.graph(forTag: id.graphTag) else {
            preconditionFailure("Attribute flags set after its graph was released")
        }
        let current = graph.flags(of: self)
        let updated = AttributeFlags(rawValue: (current.rawValue & ~mask.rawValue) | (newFlags.rawValue & mask.rawValue))
        graph.setFlags(updated, for: self)
    }

    /// Makes `target` depend on `dependency` as an input (`AGGraphAddInput`).
    public func addInput(_ dependency: AnyAttribute) {
        guard let graph = GraphRegistry.graph(forTag: id.graphTag) else {
            preconditionFailure("addInput called after graph was released")
        }
        graph.addInput(self, dependency)
    }

    /// Performs a breadth-first traversal starting at this attribute (`Attribute.breadthFirstSearch(options:_:)`).
    @discardableResult
    public func breadthFirstSearch(options: SearchOptions = [], _ body: (AnyAttribute) -> Bool) -> Bool {
        guard let graph = GraphRegistry.graph(forTag: id.graphTag) else {
            preconditionFailure("breadthFirstSearch called after graph was released")
        }
        return graph.breadthFirstSearch(from: self, options: options, body)
    }

    /// Visits the stored body of this attribute using `visitor` (`Attribute.visitBody`).
    public func visitBody<V: AttributeBodyVisitor>(_ visitor: inout V) {
        precondition(graph.table.isLive(id), "visitBody: the attribute is dead")
        graph.table.box(at: id.index).visitBody(&visitor)
    }

    /// The graph value state of the attribute (`AGAttribute.valueState`).
    public var valueState: ValueState {
        graph.valueStateImpl(of: self)
    }

    /// The subgraph that owns this attribute (`AGAttribute.subgraph`).
    public var subgraph: Subgraph {
        graph.subgraphImpl(of: self)
    }

    /// The subgraph that owns this attribute, or `nil` if it was freed (`AGAttribute.subgraphOrNil`).
    public var subgraphOrNil: Subgraph? {
        guard let owner = GraphRegistry.graph(forTag: id.graphTag) else { return nil }
        return owner.subgraphOrNilImpl(of: self)
    }

    /// The source attribute if this is an indirect attribute (`AGAttribute.source`).
    public var source: AnyAttribute {
        get { graph.sourceImpl(of: self) }
        nonmutating set { graph.setSource(newValue, for: self) }
    }
}

/// Apple's offset attribute `AGAttribute.create(self:offset:)` and `AGAttribute.create(self:offset:size:)`,
/// on the handle [O, native headers AGAttribute.h].
/// It resolves the owning graph from the tag and delegates to `Graph.makeOffsetIndirect`.
extension Attribute where Value: BitwiseCopyable {
    /// An indirect attribute that depends on the remaining bytes from `offset` to the end of `Value`.
    public func create(offset: Int) -> Attribute<Value> {
        guard let graph = GraphRegistry.graph(forTag: id.graphTag) else {
            preconditionFailure("create(offset:) after the graph was released")
        }
        return graph.makeOffsetIndirect(of: self, offset: offset)
    }

    /// An indirect attribute that depends on the bytes `[offset, offset + size)` of this attribute only.
    public func create(offset: Int, size: Int) -> Attribute<Value> {
        guard let graph = GraphRegistry.graph(forTag: id.graphTag) else {
            preconditionFailure("create(offset:size:) after the graph was released")
        }
        return graph.makeOffsetIndirect(of: self, offset: offset, size: size)
    }
}
