struct RuleContext<Value: Equatable> {
    private let evaluation: Evaluation<Value>
    private let token: UInt64

    init(_ evaluation: Evaluation<Value>) {
        self.evaluation = evaluation
        token = evaluation.token
    }

    private func checkedGraph() -> PrototypeGraph {
        guard let graph = evaluation.graph else { preconditionFailure("the evaluation graph was released") }
        graph.checkThread()
        precondition(evaluation.active && evaluation.token == token && graph.runningNode == evaluation.node,
                     "the context is only valid during its own step")
        return graph
    }

    var isFirstStep: Bool { _ = checkedGraph(); return evaluation.firstStep }
    var hasValue: Bool { _ = checkedGraph(); return evaluation.proposed != nil }
    var value: Value {
        get {
            _ = checkedGraph()
            guard let value = evaluation.proposed else { preconditionFailure("the rule has no previous value") }
            return value
        }
        nonmutating set {
            _ = checkedGraph()
            evaluation.proposed = newValue
            evaluation.written = true
        }
    }

    func poll<T>(_ attribute: Attribute<T>) -> ReadResult<T> {
        let graph = checkedGraph()
        let source = graph.checkedNode(attribute.erased)
        if source.dirty { return .pending }
        graph.recordRead(attribute.index, into: evaluation.node)
        return .ready(graph.typedNode(attribute).value!)
    }

    func hasChanged<T>(_ attribute: Attribute<T>) -> Bool {
        let graph = checkedGraph()
        _ = graph.checkedNode(attribute.erased)
        let node = graph.nodes[evaluation.node]!
        return node.changes[attribute.index] ?? node.readSet.contains(attribute.index)
    }

    func anyInputsChanged() -> Bool {
        let graph = checkedGraph()
        let node = graph.nodes[evaluation.node]!
        return !node.hasRun || node.changes.values.contains(true)
            || node.reads.contains { node.changes[$0.source] == nil }
    }
}
