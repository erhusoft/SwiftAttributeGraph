extension Graph {
    @usableFromInline
    func resumableInputIsDirty(_ id: AttributeID) -> Bool {
        precondition(table.isLive(id), "poll: the attribute is dead")
        return table.state[Int(id.index)] & NodeState.dirty != 0
    }

    /// Creates a lazy rule that yields when a dynamic input needs updating and resumes on this graph's thread.
    ///
    /// Other rule APIs keep their existing behavior. Only a chain whose dirty dynamic reads use resumable rules
    /// avoids native recursion throughout; a legacy synchronous dependency still has its documented depth limit.
    public func makeResumableRule<R: ResumableRule>(_ rule: R,
                                                  comparison: Comparison = .viewValue) -> Attribute<R.Value> {
        assertOwnThread()
        let box = ResumableRuleNode(rule: rule, isEqual: comparators.comparator(comparison, for: R.Value.self))
        let id = allocate(box, state: NodeState.isRule | NodeState.dirty | NodeState.stateful | NodeState.resumable)
        return Attribute(id: id)
    }
}
