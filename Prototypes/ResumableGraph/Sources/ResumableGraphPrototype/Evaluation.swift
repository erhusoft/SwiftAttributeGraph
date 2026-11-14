final class Evaluation<Value: Equatable> {
    weak var graph: PrototypeGraph?
    let node: Int
    var proposed: Value?
    var written = false
    var firstStep = true
    var active = false
    var token: UInt64 = 0

    init(graph: PrototypeGraph, node: Int, value: Value?) {
        self.graph = graph
        self.node = node
        proposed = value
    }
}
