@usableFromInline
struct AnyAttribute: Equatable {
    @usableFromInline let index: Int
    @usableFromInline let graph: GraphIdentity
    @usableFromInline init(index: Int, graph: GraphIdentity) {
        self.index = index
        self.graph = graph
    }
}
