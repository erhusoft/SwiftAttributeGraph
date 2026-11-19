extension Graph {
    /// Reads `attribute` inside a rule and registers a typed partial comparator on the resulting input edge.
    ///
    /// When `attribute` is written later, the comparator runs during propagation (`setValue`) while both old and new
    /// values are known. If the projected slice changed, the edge is marked sticky-changed until the consumer's next
    /// update processes it; subsequent writes before that update do not clear the sticky bit.
    public func read<Value, Projected>(
        _ attribute: Attribute<Value>,
        project: @escaping (Value) -> Projected,
        isEqual: @escaping (Projected, Projected) -> Bool
    ) -> Projected {
        assertOwnThread()
        let current = value(of: attribute)
        if evaluatingNode != Graph.noNode {
            let consumer = evaluatingNode
            let source = attribute.id.index
            stickyChangedEdges[consumer]?.remove(source)
            edgeComparators[consumer, default: [:]][source] = { oldAny, newAny in
                guard let oldVal = oldAny as? Value, let newVal = newAny as? Value else { return false }
                return isEqual(project(oldVal), project(newVal))
            }
        }
        return project(current)
    }

    /// Reads `attribute` inside a rule and registers an `Equatable` partial comparator on the resulting input edge.
    public func read<Value, Projected: Equatable>(
        _ attribute: Attribute<Value>,
        project: @escaping (Value) -> Projected
    ) -> Projected {
        read(attribute, project: project, isEqual: ==)
    }

    func evaluateEdgeComparators(for source: UInt32, oldValue: Any, newValue: Any) {
        for dependent in table.outputs[Int(source)] {
            guard let comparator = edgeComparators[dependent]?[source] else { continue }
            if stickyChangedEdges[dependent]?.contains(source) == true {
                continue
            }
            if !comparator(oldValue, newValue) {
                stickyChangedEdges[dependent, default: []].insert(source)
            }
        }
    }
}
