extension Graph {
    /// Marks as dirty everything that reads `source`, directly or not, without running any rule.
    ///
    /// The traversal is iterative and does not descend through a node that is already dirty: all its readers are
    /// already dirty too, because a node can only be brought up to date after its inputs.
    func propagateDirty(from source: UInt32) {
        dirtyStack.removeAll(keepingCapacity: true)
        dirtyStack.append(contentsOf: table.outputs[Int(source)])
        drainDirtyStack()
    }

    /// Marks the given nodes themselves dirty (unless they already are) and everything that reads them.
    func markDirty(roots: [UInt32]) {
        dirtyStack.removeAll(keepingCapacity: true)
        dirtyStack.append(contentsOf: roots)
        drainDirtyStack()
    }

    private func drainDirtyStack() {
        while let node = dirtyStack.popLast() {
            let n = Int(node)
            if table.state[n] & NodeState.dirty != 0 { continue }
            table.state[n] |= NodeState.dirty
            if table.state[n] & NodeState.observed != 0 { queueNotification(node) }
            dirtyStack.append(contentsOf: table.outputs[n])
        }
    }
}
