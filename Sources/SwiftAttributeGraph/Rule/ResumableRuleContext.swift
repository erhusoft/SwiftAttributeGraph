/// The previous value, proposed value and input changes of a resumable rule.
///
/// A proposed write survives suspension and is published only on ``RuleStep/finished``. A context is valid only
/// during the step that received it; keeping a copy never keeps the graph alive, and later use is a programming error.
public struct ResumableRuleContext<Value> {
    @usableFromInline let evaluation: ResumableEvaluation<Value>
    @usableFromInline let token: UInt64

    init(_ evaluation: ResumableEvaluation<Value>) {
        self.evaluation = evaluation
        token = evaluation.token
    }

    @inlinable
    func checkedGraph() -> Graph {
        let graph = evaluation.graph
        graph.assertOwnThread()
        precondition(evaluation.active && evaluation.token == token && graph.evaluatingNode == evaluation.node.index,
                     "a resumable context is only valid during its own step")
        return graph
    }

    /// Whether this is the first step of the current evaluation, including subsequent evaluations of the same node.
    @inlinable public var isFirstStep: Bool { _ = checkedGraph(); return evaluation.firstStep }

    /// Whether there is an initial, previous or proposed value to read.
    @inlinable public var hasValue: Bool { _ = checkedGraph(); return evaluation.proposed != nil }

    /// The proposed value, initially the previous value. Writing does not publish it until the evaluation finishes.
    @inlinable public var value: Value {
        get {
            _ = checkedGraph()
            guard let value = evaluation.proposed else { preconditionFailure("the resumable rule has no value yet") }
            return value
        }
        nonmutating set {
            _ = checkedGraph()
            evaluation.proposed = newValue
            evaluation.written = true
        }
    }

    /// Reads a current attribute and records a dependency, or reports that an input update must be requested first.
    @inlinable public func poll<T>(_ attribute: Attribute<T>) -> ReadResult<T> {
        let graph = checkedGraph()
        if graph.resumableInputIsDirty(attribute.id) { return .pending }
        let resolved = graph.resolveIndirect(attribute)
        if graph.resumableInputIsDirty(resolved.id) { return .pending }
        graph.recordRead(of: attribute.id.index)
        return .ready(graph.typedNode(resolved).value.unsafelyUnwrapped)
    }

    /// Whether an input changed since the previous evaluation. Asking does not create a dependency.
    @inlinable public func hasChanged<T>(_ attribute: Attribute<T>) -> Bool {
        let graph = checkedGraph()
        precondition(graph.contains(attribute.id), "hasChanged: the attribute is dead")
        return graph.inputChanged(of: evaluation.node.index, attribute: attribute)
    }

    /// Whether any previous or newly read input changed, except the attributes listed. True on the first evaluation.
    @inlinable public func anyInputsChanged(excluding excluded: [AnyAttribute] = []) -> Bool {
        checkedGraph().anyInputChanged(of: evaluation.node.index, excluding: excluded.map { $0.id.index })
    }
}
