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

    // MARK: Counters

    /// Number of input edges of an attribute: how many attributes it reads.
    public func inputCount(of id: AttributeID) -> Int {
        precondition(table.isLive(id), "inputCount(of:): the attribute is dead")
        return table.inputs[Int(id.index)].count
    }

    /// Number of output edges of an attribute: how many attributes read it.
    public func outputCount(of id: AttributeID) -> Int {
        precondition(table.isLive(id), "outputCount(of:): the attribute is dead")
        return table.outputs[Int(id.index)].count
    }

    /// Total number of edges in the graph (sum of all input edges).
    public var edgeCount: Int {
        table.inputs.reduce(0) { $0 + $1.count }
    }

    // MARK: Dump

    /// A text dump of the whole graph: every live attribute with its state, version, owner subgraph and edges.
    ///
    /// Intended for debugging and tests; not part of the hot path.
    public func dump() -> String {
        var lines: [String] = []
        lines.append("Graph dump: \(nodeCount) attributes, \(liveSubgraphCount) subgraphs, \(edgeCount) edges, \(recalculationCount) recalculations")
        lines.append("")
        for index in 0..<table.slotCount {
            guard table.isLive(index: UInt32(index)) else { continue }
            let state = table.state[index]
            let version = table.versions[index]
            let owner = table.owner(at: UInt32(index))
            let isRule = state & NodeState.isRule != 0
            let isIndirect = state & NodeState.indirect != 0
            let isDirty = state & NodeState.dirty != 0
            let hasValue = state & NodeState.hasValue != 0
            let inputs = table.inputs[index].map { $0.source }
            let outputs = table.outputs[index]
            lines.append("  [\(index)] gen=\(table.generations[index]) v=\(version) "
                         + (isRule ? "rule" : "input")
                         + (isIndirect ? ",indirect" : "")
                         + (isDirty ? ",dirty" : "")
                         + (hasValue ? ",hasValue" : "")
                         + " owner=\(owner)")
            if !inputs.isEmpty {
                lines.append("    inputs: \(inputs.map(String.init).joined(separator: ", "))")
            }
            if !outputs.isEmpty {
                lines.append("    outputs: \(outputs.map(String.init).joined(separator: ", "))")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Memory

    /// An estimated memory footprint of the node and subgraph tables, in bytes.
    ///
    /// This is an estimate: it accounts for the parallel arrays in `NodeTable` and `SubgraphTable` (including their
    /// element arrays), but treats each `NodeBox` as a single object of unknown size. It is useful for spotting
    /// regressions, not for exact accounting.
    public var estimatedMemoryFootprint: Int {
        let slotCount = table.slotCount
        let subgraphSlotCount = subgraphs.slotCount

        // NodeTable parallel arrays (one element per slot).
        var bytes = 0
        bytes += slotCount * MemoryLayout<UInt32>.size        // generations
        bytes += slotCount * MemoryLayout<UInt16>.size        // state
        bytes += slotCount * MemoryLayout<UInt32>.size        // versions
        bytes += slotCount * MemoryLayout<UInt32>.size        // lastVerified
        bytes += slotCount * MemoryLayout<UInt32>.size        // owners
        bytes += slotCount * MemoryLayout<Optional<NodeBox>>.size  // boxes (references)
        bytes += table.freeListCount * MemoryLayout<UInt32>.size

        // Edge arrays: inputs and outputs.
        for edges in table.inputs {
            bytes += edges.count * MemoryLayout<InputEdge>.size
        }
        for edges in table.outputs {
            bytes += edges.count * MemoryLayout<UInt32>.size
        }

        // SubgraphTable arrays.
        bytes += subgraphSlotCount * MemoryLayout<UInt32>.size        // generations
        bytes += subgraphSlotCount * MemoryLayout<UInt32>.size        // parents
        bytes += subgraphSlotCount * MemoryLayout<UInt32>.size        // firstChild
        bytes += subgraphSlotCount * MemoryLayout<UInt32>.size        // lastChild
        bytes += subgraphSlotCount * MemoryLayout<UInt32>.size        // nextSibling
        bytes += subgraphSlotCount * MemoryLayout<UInt32>.size        // previousSibling
        bytes += subgraphSlotCount * MemoryLayout<Bool>.size          // falling
        bytes += subgraphs.freeListCount * MemoryLayout<UInt32>.size

        // Subgraph member arrays.
        for members in subgraphs.members {
            bytes += members.count * MemoryLayout<UInt32>.size
        }

        return bytes
    }
}
