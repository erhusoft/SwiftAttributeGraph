extension Graph {
    /// The version of an attribute: it rises only when its value changed under the attribute's comparison policy.
    func version(of id: AttributeID) -> UInt32 {
        precondition(table.isLive(id), "version(of:): the attribute is dead")
        return table.versions[Int(id.index)]
    }

    /// Whether the attribute may be out of date.
    func isDirty(_ id: AttributeID) -> Bool {
        precondition(table.isLive(id), "isDirty: the attribute is dead")
        return table.state[Int(id.index)] & NodeState.dirty != 0
    }

    /// The attributes a rule read in its last run, in the order it read them.
    func inputs(of id: AttributeID) -> [AttributeID] {
        precondition(table.isLive(id), "inputs(of:): the attribute is dead")
        return table.inputs[Int(id.index)].map {
            AttributeID(index: $0.source, generation: table.generations[Int($0.source)])
        }
    }
}
