/// Storage owned by a resumable node, reused without reviving contexts from earlier steps or evaluations.
@usableFromInline
final class ResumableEvaluation<Value> {
    // Checked unowned access never retains the graph and traps if a caller uses it after graph destruction.
    @usableFromInline unowned let graph: Graph
    @usableFromInline let node: AttributeID
    @usableFromInline var proposed: Value?
    @usableFromInline var written = false
    @usableFromInline var firstStep = true
    @usableFromInline var active = false
    @usableFromInline var token: UInt64 = 0

    init(graph: Graph, node: AttributeID) {
        self.graph = graph
        self.node = node
    }
}
