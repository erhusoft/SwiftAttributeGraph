/// A read that either has a value or needs the resumable rule to yield first.
public enum ReadResult<Value> {
    /// The input is current; the associated value can itself be an optional `nil`.
    case ready(Value)
    /// The input needs an update. Return ``RuleStep/needsInput(_:)`` before consuming it.
    case pending
}
