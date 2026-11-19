private struct ProjectedRule<Source, Projected>: StatefulRule {
    typealias Value = Projected
    static var initialValue: Projected? { nil }
    let source: Attribute<Source>
    let project: (Source) -> Projected
    let isEqual: (Projected, Projected) -> Bool

    mutating func updateValue(_ context: inout RuleContext<Projected>) {
        let next = project(source.value)
        if context.hasValue, isEqual(context.value, next) {
            return
        }
        context.value = next
    }
}

extension Graph {
    /// Projects a typed slice from `source` with an explicit equality comparator, cutting off downstream propagation
    /// when the projected value is unchanged.
    ///
    /// - Note: Unlike native `AGGraphCreateOffsetAttribute` + `AG::Graph::compare_edge_values`, `SwiftAttributeGraph`
    ///   does not expose raw `(offset, size)` byte slicing over arbitrary Swift generics because `BitwiseCopyable` does
    ///   not guarantee that padding bytes are initialized or that arbitrary byte ranges form valid `Bool`/`enum`
    ///   patterns. This API emulates the **change-cut decision** of a projected slice safely at the Swift type level;
    ///   for key-path projections, ``makeFocus(_:keyPath:)`` is also available.
    public func makeProjectedAttribute<Source, Projected>(
        of source: Attribute<Source>,
        project: @escaping (Source) -> Projected,
        isEqual: @escaping (Projected, Projected) -> Bool
    ) -> Attribute<Projected> {
        assertOwnThread()
        return makeStatefulRule(ProjectedRule(source: source, project: project, isEqual: isEqual))
    }

    /// Projects an `Equatable` slice from `source`, cutting off downstream propagation when the projected value is
    /// equal.
    public func makeProjectedAttribute<Source, Projected: Equatable>(
        of source: Attribute<Source>,
        project: @escaping (Source) -> Projected
    ) -> Attribute<Projected> {
        makeProjectedAttribute(of: source, project: project, isEqual: ==)
    }

    /// Creates an indirect attribute with `(offset, size)` metadata for native-style edge-level range comparison.
    ///
    /// - Note: Returns `Attribute<Source>` (the full value), while downstream consumers are only dirtied when bytes
    ///   in `[offset, offset + size)` change (`size == 0` never marks changed; `offset == 0 && size == MemoryLayout<Source>.size`
    ///   always marks changed).
    public func makeOffsetIndirect<Source: BitwiseCopyable>(
        of source: Attribute<Source>,
        offset: Int,
        size: Int
    ) -> Attribute<Source> {
        assertOwnThread()
        let sourceSize = MemoryLayout<Source>.size
        precondition(offset >= 0 && offset < 0x3fff_ffff, "invalid offset: \(offset)")
        precondition(size >= 0, "invalid negative size: \(size)")
        let (end, overflow) = offset.addingReportingOverflow(size)
        precondition(!overflow && end <= sourceSize, "offset range [\(offset), +\(size)) exceeds \(sourceSize)")
        let indirect = makeIndirect(source)
        offsetIndirects[indirect.id.index] = (offset, size)
        return indirect
    }

    /// Creates a typed `Attribute<Field>` projecting `keyPath` from `source` as a true indirect attribute (no
    /// intermediate rule), so consumers only read `Field` while the edge to it uses `(offset, size)` range comparison
    /// and sticky `changed` semantics.
    public func makeOffsetFieldAttribute<Source: BitwiseCopyable, Field: BitwiseCopyable>(
        of source: Attribute<Source>,
        keyPath: KeyPath<Source, Field>
    ) -> Attribute<Field> {
        assertOwnThread()
        guard let offset = MemoryLayout<Source>.offset(of: keyPath) else {
            preconditionFailure("makeOffsetFieldAttribute: keyPath must refer to a stored property")
        }
        let s = Int(source.id.index)
        precondition(table.isLive(source.id), "makeOffsetFieldAttribute: the source attribute is dead")
        let initialState: UInt16 = NodeState.hasValue | NodeState.indirect | (table.state[s] & NodeState.dirty)
        let seenVersion = table.state[s] & NodeState.hasValue != 0 ? table.versions[s] : 0
        let id = allocate(IndirectNode<Field>(source: source.id, sourceSeenVersion: seenVersion), state: initialState)
        offsetIndirects[id.index] = (offset, MemoryLayout<Field>.size)
        offsetFieldReaders[id.index] = {
            let prev = self.evaluatingNode
            self.evaluatingNode = Graph.noNode
            defer { self.evaluatingNode = prev }
            return self.read(source)[keyPath: keyPath]
        }
        rebuildIndirectEdges(for: id.index)
        return Attribute<Field>(id: id)
    }
}
