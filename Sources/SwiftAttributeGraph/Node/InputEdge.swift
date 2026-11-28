/// An input edge of a rule: which attribute it read and the version of that attribute it saw.
///
/// Edges are kept sorted by ascending `source` slot index, matching native AttributeGraph.
struct InputEdge {
    var source: UInt32
    var seenVersion: UInt32
    /// Set while the rule runs when the edge has been read in the current run; the rest are pruned afterwards.
    var read: Bool = false
    /// Set by `Graph.inputValue(of:for:)` so an edge recorded outside a rule survives one evaluation before pruning.
    var keepForNextPrune: Bool = false
    /// For stateful rules: whether the source's version differed from `seenVersion` when the rule's run began.
    /// A new edge counts as changed.
    var changed: Bool = true
    /// Set by `addInput` when the consumer is dirty at that moment: the next run sees the edge as changed whatever the version says (native flags the
    /// edge with the dirty bit of the node, decompiled `Graph::add_input`).
    var forcedChanged: Bool = false
    /// The position of this node (the consumer) in `outputs[source]`. Kept up to date by `removeOutput`
    /// (swap-with-last) so edge removal is O(1) instead of O(degree). Set by `recordRead`.
    var positionInOutputs: UInt32 = Graph.noNode
}
