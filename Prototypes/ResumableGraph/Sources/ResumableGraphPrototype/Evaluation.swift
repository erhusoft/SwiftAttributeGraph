@usableFromInline
final class Evaluation<Value: Equatable> {
    @usableFromInline weak var graph: PrototypeGraph?
    @usableFromInline let node: Int
    @usableFromInline var proposed: Value?
    @usableFromInline var written = false
    @usableFromInline var firstStep = true
    @usableFromInline var active = false
    @usableFromInline var token: UInt64 = 0

    init(graph: PrototypeGraph, node: Int, value: Value?) {
        graph.evaluationAllocationCount += 1
        self.graph = graph
        self.node = node
        proposed = value
    }
}
