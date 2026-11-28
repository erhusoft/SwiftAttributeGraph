/// What `AnyAttribute.unsafeOffset(at:)` makes: an offset into `source` whose member type is not known yet. It holds no value; casting it
/// (`AnyAttribute.unsafeCast(to:)`) makes the typed attribute that reads the bytes at `offset` as that type, once per type.
final class ErasedOffsetNode: NodeBox {
    let source: AttributeID
    let offset: Int
    /// The typed attribute made for each type it was cast to.
    var casts: [ObjectIdentifier: AttributeID] = [:]

    init(source: AttributeID, offset: Int) {
        self.source = source
        self.offset = offset
        super.init()
    }

    override var isOffsetAttribute: Bool { true }
}

/// How many erased offsets were ever made in this process. While it is zero `unsafeCast(to:)` skips looking for one, so the cast stays free
/// for everybody who never calls `unsafeOffset(at:)`.
@usableFromInline nonisolated(unsafe) var erasedOffsetsMade = 0

extension AnyAttribute {
    /// The attribute of an erased offset cast to `Value`, or `nil` if this is not an erased offset.
    @usableFromInline
    func castOfErasedOffset<Value>(to _: Value.Type) -> AttributeID? {
        guard let graph = GraphRegistry.graph(forTag: id.graphTag), graph.table.isLive(id),
              let node = graph.table.box(at: id.index) as? ErasedOffsetNode else { return nil }
        if let known = node.casts[ObjectIdentifier(Value.self)], graph.table.isLive(known) { return known }
        precondition(graph.table.isLive(node.source), "unsafeOffset(at:): the attribute it offsets is dead")
        let owner = Subgraph(id: graph.subgraphs.id(at: graph.table.owner(at: id.index)))
        guard let made = graph.withCurrent(owner, { graph.table.box(at: node.source.index).offsetAttribute(of: node.source, at: node.offset, as: Value.self) }) else {
            preconditionFailure("unsafeOffset(at:): the attribute it offsets holds no value of its own")
        }
        node.casts[ObjectIdentifier(Value.self)] = made
        return made
    }
}
