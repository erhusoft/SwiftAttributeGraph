@usableFromInline
struct RuleContext<Value: Equatable> {
    @usableFromInline let evaluation: Evaluation<Value>
    @usableFromInline let token: UInt64

    init(_ evaluation: Evaluation<Value>) {
        self.evaluation = evaluation
        token = evaluation.token
    }

    @inlinable
    func checkedGraph() -> PrototypeGraph {
        guard let graph = evaluation.graph else { preconditionFailure("the evaluation graph was released") }
        graph.checkThread()
        precondition(evaluation.active && evaluation.token == token && graph.runningNode == evaluation.node,
                     "the context is only valid during its own step")
        return graph
    }

    @inlinable var isFirstStep: Bool { _ = checkedGraph(); return evaluation.firstStep }
    @inlinable var hasValue: Bool { _ = checkedGraph(); return evaluation.proposed != nil }
    @inlinable var value: Value {
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

    @inlinable
    func poll<T>(_ attribute: Attribute<T>) -> ReadResult<T> {
        let graph = checkedGraph()
        let source = graph.checkedNode(attribute.erased)
        if source.dirty { return .pending }
        guard let typed = source as? TypedNode<T> else { preconditionFailure("wrong attribute type") }
        graph.recordRead(attribute.index, into: evaluation.node)
        return .ready(typed.value!)
    }

    @inlinable
    func hasChanged<T>(_ attribute: Attribute<T>) -> Bool {
        let graph = checkedGraph()
        _ = graph.checkedNode(attribute.erased)
        let node = graph.nodes[evaluation.node]!
        return node.changes[attribute.index] ?? node.readSet.contains(attribute.index)
    }

    @inlinable
    func anyInputsChanged() -> Bool {
        let graph = checkedGraph()
        let node = graph.nodes[evaluation.node]!
        return !node.hasRun || node.changes.values.contains(true)
            || node.reads.contains { node.changes[$0.source] == nil }
    }
}
