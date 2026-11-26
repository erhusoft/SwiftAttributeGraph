final class ResumableRuleNode<R: ResumableRule>: TypedNode<R.Value> {
    var rule: R
    var evaluation: ResumableEvaluation<R.Value>?

    init(rule: R, type: NodeType<R.Value>) {
        self.rule = rule
        super.init(value: nil, type: type)
    }

    override func mutateRuleBody<Target>(as type: Target.Type, _ body: (inout Target) -> Void) -> Bool {
        guard R.self == Target.self else { return false }
        return withUnsafeMutablePointer(to: &rule) { ptr in
            ptr.withMemoryRebound(to: Target.self, capacity: 1) { targetPtr in
                body(&targetPtr.pointee)
                return true
            }
        }
    }

    override func resume(in graph: Graph, node: AttributeID, firstStep: Bool) -> (step: RuleStep, changed: Bool) {
        if firstStep {
            if evaluation == nil {
                value = R.initialValue
                evaluation = ResumableEvaluation(graph: graph, node: node)
            }
            evaluation!.proposed = value
            evaluation!.written = false
            evaluation!.firstStep = true
        }
        let evaluation = evaluation!
        evaluation.token += 1
        evaluation.active = true
        var context = ResumableRuleContext(evaluation)
        let step = rule.resume(&context)
        evaluation.active = false
        evaluation.firstStep = false
        switch step {
        case .needsInput:
            return (step, false)
        case .finished:
            defer { evaluation.proposed = nil }
            guard let result = evaluation.proposed else {
                preconditionFailure("a resumable rule must produce a value before finishing its first evaluation")
            }
            if graph.isCurrentFrameCancelled && graph.table.state[Int(node.index)] & NodeState.hasValue != 0 {
                return (.finished, false)
            }
            return (.finished, evaluation.written ? store(result) : false)
        }
    }
}
