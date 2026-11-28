extension AnyAttribute {
    fileprivate var introspectedGraph: Graph {
        guard let graph = GraphRegistry.graph(forTag: id.graphTag) else {
            preconditionFailure("the graph of the attribute was released")
        }
        precondition(graph.table.isLive(id), "the attribute is dead")
        return graph
    }

    /// The node of a direct attribute: not an indirect one nor an offset one, which native refuses (`non-direct attribute id`).
    private func directBox() -> NodeBox {
        let graph = introspectedGraph
        let box = graph.table.box(at: id.index)
        precondition(graph.table.state[Int(id.index)] & NodeState.indirect == 0 && !box.isOffsetAttribute,
                     "non-direct attribute id: \(id.rawValue)")
        return box
    }

    /// The type of the value (`AnyAttribute.valueType` in native AttributeGraph; oracle scenarios `v1` to `v5`). It is the type the
    /// attribute really holds, whatever `unsafeCast(to:)` made of the handle. Indirect and offset attributes stop the program.
    public var valueType: Any.Type { directBox().valueType }

    /// The type of the body: `External<Value>` for an input, the rule type for a rule (`AnyAttribute._bodyType`; scenarios `b1`
    /// to `b4`).
    public var _bodyType: Any.Type { directBox().bodyType }

    /// A pointer to the body (`AnyAttribute._bodyPointer`; scenarios `p1` to `p3`): read it as ``_bodyType``. For an input, whose
    /// body `External` has no stored fields, the pointer is only valid, not a value to read.
    public var _bodyPointer: UnsafeRawPointer { directBox().bodyPointer }

    /// The producer an indirect attribute waits for (`AnyAttribute.indirectDependency`; scenarios `d1` to `d4`, `u3`). Setting it
    /// is `Graph.setDependency(_:for:)`. Direct and offset attributes stop the program (`not an indirect attribute`).
    public var indirectDependency: AnyAttribute? {
        get {
            let box = indirectNode()
            return box.dependency.map { AnyAttribute(id: $0) }
        }
        nonmutating set {
            _ = indirectNode()
            introspectedGraph.setDependencyErased(newValue, forID: id)
        }
    }

    private func indirectNode() -> AnyIndirectNode {
        let graph = introspectedGraph
        let index = id.index
        guard graph.table.state[Int(index)] & NodeState.indirect != 0,
              graph.offsetIndirects[index] == nil, graph.offsetFieldReaders[index] == nil,
              let box = graph.table.box(at: index) as? AnyIndirectNode else {
            preconditionFailure("not an indirect attribute: \(id.rawValue)")
        }
        return box
    }
}

extension Attribute {
    /// An attribute holding the `Member` that sits `offset` bytes into this attribute's value (`Attribute.unsafeOffset(at:as:)` in
    /// native AttributeGraph; oracle scenarios `u1`, `u2`, `u5`). It follows the attribute. Reading one whose range lies outside the
    /// value stops the program (`invalid value size for attribute`).
    public func unsafeOffset<Member>(at offset: Int, as _: Member.Type) -> Attribute<Member> {
        guard let graph = GraphRegistry.graph(forTag: id.graphTag) else {
            preconditionFailure("unsafeOffset(at:as:) called after the graph was released")
        }
        return graph.makeProjectedAttribute(of: self, project: { (source: Value) -> Member in
            let end = offset + MemoryLayout<Member>.size
            precondition(offset >= 0 && end <= MemoryLayout<Value>.size,
                         "invalid value size for attribute: (saw \(MemoryLayout<Value>.size), expected \(end))")
            return withUnsafeBytes(of: source) { raw in
                raw.baseAddress!.advanced(by: offset).assumingMemoryBound(to: Member.self).pointee
            }
        }, isEqual: { _, _ in false })
    }
}

extension AnyAttribute {
    /// An attribute that reads the value `offset` bytes into this attribute's, whose type is given when it is cast
    /// (`AnyAttribute.unsafeOffset(at:)` in native AttributeGraph; oracle scenarios `u5a` and `u5b`). It is made in the current
    /// subgraph, and stops the program when there is none (`attempting to create attribute with no subgraph`).
    ///
    /// Cast it with ``unsafeCast(to:)``: the cast is the attribute that reads the bytes, as one per type. Reading one whose range lies outside
    /// the value stops the program (`invalid value size for attribute`), and like any offset attribute it is neither direct nor indirect
    /// (``valueType``, ``indirectDependency``... stop the program).
    public func unsafeOffset(at offset: Int) -> AnyAttribute {
        let graph = introspectedGraph
        precondition(offset >= 0 && offset < 0x3fff_ffff, "invalid offset: \(offset)")
        let node = ErasedOffsetNode(source: id, offset: offset)
        let made = graph.allocate(node, state: 0)
        erasedOffsetsMade += 1
        return AnyAttribute(id: made)
    }
}
