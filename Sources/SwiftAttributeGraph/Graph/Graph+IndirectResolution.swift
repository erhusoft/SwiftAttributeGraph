extension Graph {
    /// Rebuilds the input edges of an indirect attribute (`box.source` and optional `box.dependency`) in ascending
    /// `source` index order so dirty propagation and update verification flow through the indirection while readers
    /// only record an edge to the indirect attribute.
    func rebuildIndirectEdges(for indirect: UInt32) {
        let n = Int(indirect)
        for edge in table.inputs[n] {
            removeOutput(indirect, from: edge.source, at: edge.positionInOutputs)
        }
        table.inputs[n].removeAll(keepingCapacity: true)

        guard let box = table.box(at: indirect) as? AnyIndirectNode else { return }
        var sources: [UInt32] = []
        if table.isLive(box.source) {
            sources.append(box.source.index)
        }
        if let dep = box.dependency, table.isLive(dep), dep.index != box.source.index {
            sources.append(dep.index)
        }
        sources.sort()
        for src in sources {
            let s = Int(src)
            table.outputs[s].append(indirect)
            let position = UInt32(table.outputs[s].count - 1)
            let seenVersion: UInt32
            if src == box.source.index {
                seenVersion = box.sourceSeenVersion
            } else {
                seenVersion = table.state[s] & NodeState.hasValue != 0 ? table.versions[s] : 0
            }
            table.inputs[n].append(
                InputEdge(source: src, seenVersion: seenVersion, read: true, positionInOutputs: position)
            )
            if subgraphs.context(of: table.owner(at: indirect)) != subgraphs.context(of: table.owner(at: src)) {
                table.state[n] |= NodeState.hasCrossContextInput
            }
        }
    }

    @usableFromInline
    func inputChanged<Value>(of node: UInt32, attribute: Attribute<Value>) -> Bool {
        guard let changed = inputChanged(of: node, source: attribute.id.index) else { return false }
        if changed || table.state[Int(attribute.id.index)] & NodeState.indirect == 0 { return changed }
        let source = resolveIndirect(attribute)
        return inputChanged(of: node, source: source.id.index) ?? false
    }

    /// Resolves a chain of indirect attributes iteratively to its terminal non-indirect source (untyped).
    func resolveIndirectNode(_ id: AttributeID) -> UInt32 {
        var current = id
        while true {
            precondition(table.isLive(current), "the indirect attribute or its source is dead")
            let index = current.index
            if table.state[Int(index)] & NodeState.indirect == 0 { return index }
            if offsetFieldReaders[index] != nil { return index }
            guard let box = table.box(at: index) as? AnyIndirectNode else {
                return index
            }
            current = box.source
        }
    }
    @usableFromInline
    func resolveIndirect<Value>(_ attribute: Attribute<Value>) -> Attribute<Value> {
        var current = attribute
        while true {
            precondition(table.isLive(current.id), "the indirect attribute or its source is dead")
            let index = current.id.index
            if table.state[Int(index)] & NodeState.indirect == 0 { return current }
            if offsetFieldReaders[index] != nil { return current }
            guard let box = table.box(at: index) as? IndirectNode<Value> else {
                preconditionFailure("resolveIndirect: type mismatch at indirect node \(index)")
            }
            current = Attribute(id: box.source)
        }
    }
}
