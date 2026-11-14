extension Graph {
    @usableFromInline
    func inputChanged<Value>(of node: UInt32, attribute: Attribute<Value>) -> Bool {
        guard let changed = inputChanged(of: node, source: attribute.id.index) else { return false }
        if changed || table.state[Int(attribute.id.index)] & NodeState.indirect == 0 { return changed }
        let source = resolveIndirect(attribute, tracking: false)
        return inputChanged(of: node, source: source.id.index) ?? false
    }

    /// Resolves redirects iteratively, preserving dependencies on every live alias when reading inside a rule.
    @usableFromInline
    func resolveIndirect<Value>(_ attribute: Attribute<Value>, tracking: Bool) -> Attribute<Value> {
        var current = attribute
        while true {
            precondition(table.isLive(current.id), "the indirect attribute or its source is dead")
            let index = current.id.index
            if table.state[Int(index)] & NodeState.indirect == 0 { return current }
            if tracking { recordRead(of: index) }
            let box = table.box(at: index) as! IndirectNode<Value>
            current = Attribute(id: box.source)
        }
    }
}
