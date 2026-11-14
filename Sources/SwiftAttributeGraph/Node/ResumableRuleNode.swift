final class ResumableRuleNode<R: ResumableRule>: TypedNode<R.Value> {
    var rule: R
    var evaluation: ResumableEvaluation<R.Value>?

    init(rule: R, isEqual: @escaping (R.Value, R.Value) -> Bool) {
        self.rule = rule
        super.init(value: nil, isEqual: isEqual)
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
            return (.finished, evaluation.written ? store(result) : false)
        }
    }
}
