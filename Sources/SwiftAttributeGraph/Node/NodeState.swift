/// Bits of the per-slot state byte.
enum NodeState {
    /// The node is a rule (it computes its value from other attributes).
    static let isRule: UInt8 = 1 << 0
    /// The node may be out of date: a source changed since it last ran.
    static let dirty: UInt8 = 1 << 1
    /// Somebody observes the node and wants to be told when it becomes dirty.
    static let observed: UInt8 = 1 << 2
    /// The node already has a value (rules do not until their first run).
    static let hasValue: UInt8 = 1 << 3
    /// The node is on the update stack or running: reaching it again is a cycle.
    static let evaluating: UInt8 = 1 << 4
    /// A notification for the node is queued and not yet delivered.
    static let notifyQueued: UInt8 = 1 << 5
    /// The rule must run on its next update even if no input version changed (an input edge was removed under it).
    static let pending: UInt8 = 1 << 6
    /// The rule is a ``StatefulRule``: it verifies all its inputs before running and sees which of them changed.
    static let stateful: UInt8 = 1 << 7
}
