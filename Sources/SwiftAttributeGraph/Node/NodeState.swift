/// Bits of the per-slot state word.
enum NodeState {
    /// The node is a rule (it computes its value from other attributes).
    static let isRule: UInt16 = 1 << 0
    /// The node may be out of date: a source changed since it last ran.
    static let dirty: UInt16 = 1 << 1
    /// Somebody observes the node and wants to be told when it becomes dirty.
    static let observed: UInt16 = 1 << 2
    /// The node already has a value (rules do not until their first run).
    static let hasValue: UInt16 = 1 << 3
    /// The node is on the update stack or running: reaching it again is a cycle.
    static let evaluating: UInt16 = 1 << 4
    /// A notification for the node is queued and not yet delivered.
    static let notifyQueued: UInt16 = 1 << 5
    /// The rule must run on its next update even if no input version changed (an input edge was removed under it).
    static let pending: UInt16 = 1 << 6
    /// The rule is a ``StatefulRule``: it verifies all its inputs before running and sees which of them changed.
    static let stateful: UInt16 = 1 << 7
    /// The rule yields to the explicit update stack when it needs a dirty input.
    static let resumable: UInt16 = 1 << 8
    /// The node is an indirect attribute: it redirects to another attribute and has no value of its own.
    static let indirect: UInt16 = 1 << 9
    /// The node is managed by a subgraph's ``SubgraphNodeCache`` and can be parked/collected when unreferenced.
    static let cached: UInt16 = 1 << 10
    /// Set by `invalidateValue(of:)` and cleared after the rule's evaluation finishes (`AGValueState.selfModified`).
    static let selfModified: UInt16 = 1 << 11
}
