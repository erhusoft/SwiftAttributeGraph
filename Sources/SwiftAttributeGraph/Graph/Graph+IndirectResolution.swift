extension Graph {
    /// Connects an indirect attribute `indirect` to `source` via a single input/output edge so dirty propagation and
    /// update verification flow through the indirection while readers only record an edge to `indirect`.
    func attachIndirectEdge(from indirect: UInt32, to source: UInt32) {
        let s = Int(source)
        table.outputs[s].append(indirect)
        let position = UInt32(table.outputs[s].count - 1)
        let seenVersion = table.state[s] & NodeState.hasValue != 0 ? table.versions[s] : 0
        table.inputs[Int(indirect)] = [
            InputEdge(source: source, seenVersion: seenVersion, read: true, positionInOutputs: position)
        ]
    }

    @usableFromInline
    func inputChanged<Value>(of node: UInt32, attribute: Attribute<Value>) -> Bool {
        guard let changed = inputChanged(of: node, source: attribute.id.index) else { return false }
        if changed || table.state[Int(attribute.id.index)] & NodeState.indirect == 0 { return changed }
        let source = resolveIndirect(attribute)
        return inputChanged(of: node, source: source.id.index) ?? false
    }

    /// Resolves a chain of indirect attributes iteratively to its terminal non-indirect source.
    @usableFromInline
    func resolveIndirect<Value>(_ attribute: Attribute<Value>) -> Attribute<Value> {
        var current = attribute
        while true {
            precondition(table.isLive(current.id), "the indirect attribute or its source is dead")
            let index = current.id.index
            if table.state[Int(index)] & NodeState.indirect == 0 { return current }
            let box = table.box(at: index) as! IndirectNode<Value>
            current = Attribute(id: box.source)
        }
    }
}
