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
    /// - Note: `size == 0` never marks downstream consumers changed; `offset == 0 && size == MemoryLayout<Source>.size`
    ///   always falls back to marking changed; otherwise `[offset, offset + size)` is compared on `old + offset` vs
    ///   `new + offset`.
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
}
