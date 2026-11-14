final class RuleNode<R: ResumableRule>: TypedNode<R.Value> {
    var rule: R
    var evaluation: Evaluation<R.Value>?

    init(owner: Int, rule: R) {
        self.rule = rule
        super.init(owner: owner, value: R.initialValue)
        dirty = true
    }

    override func begin(in graph: PrototypeGraph, index: Int) {
        if let evaluation {
            // The monotonically increasing token keeps all earlier contexts invalid when storage is reused.
            evaluation.proposed = value
            evaluation.written = false
            evaluation.firstStep = true
        } else {
            evaluation = Evaluation(graph: graph, node: index, value: value)
        }
    }

    override func step() -> RuleStep {
        let evaluation = evaluation!
        evaluation.token += 1
        evaluation.active = true
        defer { evaluation.active = false; evaluation.firstStep = false }
        var context = RuleContext(evaluation)
        return rule.resume(&context)
    }

    override func finish() -> Bool {
        let evaluation = evaluation!
        // Keep the owned storage, but do not retain a proposed value after the evaluation ends.
        defer { evaluation.proposed = nil }
        guard let result = evaluation.proposed else { preconditionFailure("the first evaluation must produce a value") }
        return evaluation.written ? store(result) : false
    }
}
