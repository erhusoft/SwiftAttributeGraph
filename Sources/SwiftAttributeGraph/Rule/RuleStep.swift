/// The action a resumable rule asks the graph to perform after its current step returns.
public enum RuleStep {
    /// Updates this dirty input on the graph's explicit stack, records the read, and resumes the rule.
    case needsInput(AnyAttribute)
    /// Finishes the evaluation and publishes its proposed value through the attribute's comparison policy.
    case finished
}
