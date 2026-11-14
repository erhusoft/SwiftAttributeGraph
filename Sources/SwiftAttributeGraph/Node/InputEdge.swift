/// An input edge of a rule: which attribute it read and the version of that attribute it saw.
///
/// Edges are kept in the order the rule read them, so verification can stop at the first source that changed
/// (all four studied engines agree on this).
struct InputEdge {
    var source: UInt32
    var seenVersion: UInt32
    /// Set while the rule runs when the edge has been read in the current run; the rest are pruned afterwards.
    var read: Bool = false
}
