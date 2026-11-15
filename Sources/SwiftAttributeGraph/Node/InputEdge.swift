/// An input edge of a rule: which attribute it read and the version of that attribute it saw.
///
/// Edges are kept sorted by ascending `source` slot index, matching native AttributeGraph.
struct InputEdge {
    var source: UInt32
    var seenVersion: UInt32
    /// Set while the rule runs when the edge has been read in the current run; the rest are pruned afterwards.
    var read: Bool = false
    /// For stateful rules: whether the source's version differed from `seenVersion` when the rule's run began.
    /// A new edge counts as changed.
    var changed: Bool = true
    /// The position of this node (the consumer) in `outputs[source]`. Kept up to date by `removeOutput`
    /// (swap-with-last) so edge removal is O(1) instead of O(degree). Set by `recordRead`.
    var positionInOutputs: UInt32 = Graph.noNode
}
