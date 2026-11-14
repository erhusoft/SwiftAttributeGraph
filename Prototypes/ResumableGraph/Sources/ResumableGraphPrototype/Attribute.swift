@usableFromInline
struct Attribute<Value: Equatable> {
    @usableFromInline let index: Int
    @usableFromInline let graph: GraphIdentity
    @inlinable var erased: AnyAttribute { AnyAttribute(index: index, graph: graph) }
}
