/// A rule that returns control before a dynamic input needs an update, then resumes on the graph's original thread.
///
/// Store the current phase and any consumed values in the rule's properties. `resume` can be called several times
/// per evaluation; guard effects with the phase or ``ResumableRuleContext/isFirstStep``. The graph does not replay
/// a completed step. A rule must not write inputs, and must poll dirty inputs rather than read them synchronously.
public protocol ResumableRule {
    /// The value held by the attribute.
    associatedtype Value
    /// The initial value, resolved lazily once on the first evaluation; `nil` means that evaluation must produce one.
    static var initialValue: Value? { get }
    /// Performs one step and asks for an input update or finishes the evaluation.
    mutating func resume(_ context: inout ResumableRuleContext<Value>) -> RuleStep
}

extension ResumableRule {
    /// No initial value; the first evaluation must write one before finishing.
    public static var initialValue: Value? { nil }
}
