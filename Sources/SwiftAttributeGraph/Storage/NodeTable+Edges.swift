// The hot loops over the input edges of one node, written as `NodeTable` methods so each takes the node's edge array
// once (`withUnsafe(Mutable)BufferPointer`) instead of going through `inputs[n][i]` on every step. Going through the
// nested array cost a retain/release, bounds checks and, for writes, two copy-on-write uniqueness checks per edge: about
// half of the `batch-writes` profile after the read path was specialized [O]. Inside a `NodeTable` method the edge
// array and the `state`/`versions` columns are disjoint stored properties of `self`, so reading the columns while the
// edges are borrowed is a static, checked access, not an overlapping one.
//
// The buffer pointers never escape their closure, and no closure calls user code or changes the length of any column.
// The mutating helpers return early on an empty edge array: taking a mutable buffer of the shared empty array would
// allocate a buffer of its own.

extension NodeTable {
    /// Scans the input edges of node `n` from `start` for the update stack, for a node with no partial edge comparator
    /// and a graph with no offset attribute (so a changed version always means "must run").
    ///
    /// Returns the index of the first edge whose source is dirty (or the edge count when there is none) and whether an
    /// edge before it saw a different version of its source.
    func scanInputs(of n: Int, from start: Int) -> (stop: Int, changed: Bool) {
        inputs[n].withUnsafeBufferPointer { edges in
            var changed = false
            var i = start
            while i < edges.count {
                let edge = edges[i]
                let source = Int(edge.source)
                if state[source] & NodeState.dirty != 0 { return (i, changed) }
                if versions[source] != edge.seenVersion { changed = true }
                i += 1
            }
            return (i, changed)
        }
    }

    /// Prepares the input edges of node `n` for a run of its rule: an edge counts as read only if it was kept for this
    /// prune, and remembers whether its source changed since the last run.
    mutating func beginRun(of n: Int) {
        if inputs[n].isEmpty { return }
        inputs[n].withUnsafeMutableBufferPointer { edges in
            for i in edges.indices {
                let edge = edges[i]
                edges[i].read = edge.keepForNextPrune
                edges[i].keepForNextPrune = false
                edges[i].changed = versions[Int(edge.source)] != edge.seenVersion
            }
        }
    }

    /// Marks the edge from `source` into node `consumer` as read, with the current version of `source`.
    ///
    /// Returns `nil` when the edge existed, or the index (ascending `source` order) where the new edge goes.
    mutating func markRead(of source: UInt32, by consumer: Int) -> Int? {
        // Appending at the end is the common case for a new edge: rules usually read in ascending slot order.
        let count = inputs[consumer].count
        if count == 0 || inputs[consumer][count - 1].source < source { return count }
        let version = versions[Int(source)]
        return inputs[consumer].withUnsafeMutableBufferPointer { edges -> Int? in
            var low = 0
            var high = count
            while low < high {
                let mid = (low + high) >> 1
                if edges[mid].source < source { low = mid + 1 } else { high = mid }
            }
            if low < count, edges[low].source == source {
                edges[low].read = true
                edges[low].seenVersion = version
                return nil
            }
            return low
        }
    }

    /// When every input edge of node `n` was read in the run that just ended, clears their `changed` bit and returns
    /// `true`. Otherwise changes nothing and returns `false`, so the caller prunes edge by edge.
    mutating func keepAllInputsIfAllRead(of n: Int) -> Bool {
        if inputs[n].isEmpty { return true }
        return inputs[n].withUnsafeMutableBufferPointer { edges in
            for edge in edges where !edge.read { return false }
            for i in edges.indices { edges[i].changed = false }
            return true
        }
    }

    /// Capacity of the edge array that the first input edge of a node allocates.
    ///
    /// The array grew one slot at a time: a rule that read two inputs reallocated and copied it on its first run, 14 %
    /// of the `diamond-layers` profile [O]. Two, not four: every edge array of a one-input rule grows from 48 to 64
    /// bytes (96 with four), and the longer arrays made a 20,000-rule verification walk 3 % (6 % with four) slower [O].
    static let firstInputCapacity = 2

    /// Adds a new input edge to node `n` at `index` (the position that keeps ascending `source` order).
    mutating func addInput(_ edge: InputEdge, at index: Int, of n: Int) {
        if inputs[n].isEmpty { inputs[n].reserveCapacity(NodeTable.firstInputCapacity) }
        if index == inputs[n].count {
            inputs[n].append(edge)
        } else {
            inputs[n].insert(edge, at: index)
        }
    }
}
