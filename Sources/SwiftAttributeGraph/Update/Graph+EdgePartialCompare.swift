extension Graph {
    /// Reads `attribute` inside a rule and registers a typed partial comparator on the resulting input edge.
    ///
    /// - Note: This is a Swift-typed adaptation without a direct native analogue (native `AttributeGraph` only compares
    ///   raw `(offset, size)` ranges on `IndirectNode` edges).
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
        var queue: [UInt32] = [source]
        var visited: Set<UInt32> = [source]
        var newlySticky: [UInt32] = []
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            for dependent in table.outputs[Int(current)] {
                if table.state[Int(dependent)] & NodeState.indirect != 0 {
                    if visited.insert(dependent).inserted {
                        queue.append(dependent)
                    }
                    continue
                }
                if let range = offsetIndirects[current] {
                    if stickyChangedEdges[dependent]?.contains(current) == true {
                        continue
                    }
                    if !compareOffsetRange(oldValue: oldValue, newValue: newValue, offset: range.offset, size: range.size) {
                        stickyChangedEdges[dependent, default: []].insert(current)
                        newlySticky.append(dependent)
                    }
                    continue
                }
                guard let comparator = edgeComparators[dependent]?[current] else { continue }
                if stickyChangedEdges[dependent]?.contains(current) == true {
                    continue
                }
                if !comparator(oldValue, newValue) {
                    stickyChangedEdges[dependent, default: []].insert(current)
                    newlySticky.append(dependent)
                }
            }
        }
        if !newlySticky.isEmpty {
            markDirty(roots: newlySticky)
        }
    }

    func markStickyEdgesThroughIndirects(from source: UInt32) {
        var queue: [UInt32] = [source]
        var visited: Set<UInt32> = [source]
        var newlySticky: [UInt32] = []
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            for dependent in table.outputs[Int(current)] {
                if table.state[Int(dependent)] & NodeState.indirect != 0 {
                    if visited.insert(dependent).inserted {
                        queue.append(dependent)
                    }
                    continue
                }
                if edgeComparators[dependent]?[current] != nil {
                    stickyChangedEdges[dependent, default: []].insert(current)
                    newlySticky.append(dependent)
                }
            }
        }
        if !newlySticky.isEmpty {
            markDirty(roots: newlySticky)
        }
    }

    private func compareOffsetRange(oldValue: Any, newValue: Any, offset: Int, size: Int) -> Bool {
        if size == 0 { return true }
        var oldBytes = [UInt8]()
        var newBytes = [UInt8]()
        var fullSize = 0
        func extract<T>(_ v: T) -> [UInt8] {
            fullSize = MemoryLayout<T>.size
            return withUnsafeBytes(of: v) { raw in
                guard let base = raw.baseAddress, offset + size <= raw.count else { return [] }
                return Array(UnsafeBufferPointer(start: base.assumingMemoryBound(to: UInt8.self).advanced(by: offset), count: size))
            }
        }
        oldBytes = _openExistential(oldValue, do: extract)
        newBytes = _openExistential(newValue, do: extract)
        if offset == 0 && size == fullSize { return false }
        guard oldBytes.count == size && newBytes.count == size else { return false }
        return oldBytes == newBytes
    }
}
