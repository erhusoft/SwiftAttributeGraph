/// Storage of the subgraphs of a graph: a slot table with generations, the list of attribute slots each one owns, and
/// the tree (parent and child links in arrays, so linking and unlinking a child take constant time).
struct SubgraphTable {
    /// Marks "no subgraph" in the tree links.
    static let none = UInt32.max

    private(set) var generations: [UInt32] = []
    private(set) var members: [[UInt32]] = []
    private(set) var parents: [UInt32] = []
    private var firstChild: [UInt32] = []
    private var lastChild: [UInt32] = []
    private var nextSibling: [UInt32] = []
    private var previousSibling: [UInt32] = []
    /// Set on a subgraph that is being invalidated or waits for the end of the update that asked for it: nothing can be
    /// created in it, but what it owns can still be read until it is freed.
    private var falling: [Bool] = []
    private var freeList: [UInt32] = []
    private(set) var liveCount = 0

    /// Number of slots ever created (live or free).
    var slotCount: Int { generations.count }

    mutating func allocate(parent: SubgraphID?) -> SubgraphID {
        liveCount += 1
        let index: UInt32
        if let reused = freeList.popLast() {
            index = reused
        } else {
            generations.append(1)
            members.append([])
            parents.append(SubgraphTable.none)
            firstChild.append(SubgraphTable.none)
            lastChild.append(SubgraphTable.none)
            nextSibling.append(SubgraphTable.none)
            previousSibling.append(SubgraphTable.none)
            falling.append(false)
            index = UInt32(generations.count - 1)
        }
        let i = Int(index)
        parents[i] = parent?.index ?? SubgraphTable.none
        if let parent {
            let p = Int(parent.index)
            let tail = lastChild[p]
            previousSibling[i] = tail
            if tail == SubgraphTable.none { firstChild[p] = index } else { nextSibling[Int(tail)] = index }
            lastChild[p] = index
        }
        return SubgraphID(index: index, generation: generations[i])
    }

    func isLive(_ id: SubgraphID) -> Bool {
        let index = Int(id.index)
        return index < generations.count && generations[index] == id.generation
    }

    func isFalling(index: UInt32) -> Bool { falling[Int(index)] }
    mutating func setFalling(index: UInt32, _ value: Bool) { falling[Int(index)] = value }

    /// The ID of the live subgraph in a slot.
    func id(at index: UInt32) -> SubgraphID { SubgraphID(index: index, generation: generations[Int(index)]) }

    func parent(of id: SubgraphID) -> SubgraphID? {
        let parent = parents[Int(id.index)]
        return parent == SubgraphTable.none ? nil : self.id(at: parent)
    }

    /// The children of a subgraph, in the order they were created.
    func children(of index: UInt32) -> [UInt32] {
        var result: [UInt32] = []
        var child = firstChild[Int(index)]
        while child != SubgraphTable.none {
            result.append(child)
            child = nextSibling[Int(child)]
        }
        return result
    }

    mutating func add(member: UInt32, to id: SubgraphID) { members[Int(id.index)].append(member) }

    /// The subgraph and all its descendants with every child before its parent, siblings in creation order. Uses an
    /// explicit stack: the depth of the tree is data.
    func postOrder(from root: UInt32) -> [UInt32] {
        var result: [UInt32] = []
        var stack: [(index: UInt32, expanded: Bool)] = [(root, false)]
        while let (index, expanded) = stack.popLast() {
            if expanded { result.append(index); continue }
            stack.append((index, true))
            var child = lastChild[Int(index)]                   // last to first, so the first child is popped first
            while child != SubgraphTable.none {
                stack.append((child, false))
                child = previousSibling[Int(child)]
            }
        }
        return result
    }

    /// Takes the attribute slots a subgraph owned (the subgraph itself is released with ``release(_:)``).
    mutating func takeMembers(of index: UInt32) -> [UInt32] {
        let owned = members[Int(index)]
        members[Int(index)] = []
        return owned
    }

    /// Releases a subgraph whose attributes were already freed: unlinks it from its parent (if the parent is still
    /// linked), bumps the generation and queues the slot for reuse.
    mutating func release(index: UInt32) {
        let i = Int(index)
        let previous = previousSibling[i], next = nextSibling[i], parent = parents[i]
        if parent != SubgraphTable.none {
            let p = Int(parent)
            if previous == SubgraphTable.none { firstChild[p] = next } else { nextSibling[Int(previous)] = next }
            if next == SubgraphTable.none { lastChild[p] = previous } else { previousSibling[Int(next)] = previous }
        }
        parents[i] = SubgraphTable.none
        firstChild[i] = SubgraphTable.none
        lastChild[i] = SubgraphTable.none
        nextSibling[i] = SubgraphTable.none
        previousSibling[i] = SubgraphTable.none
        falling[i] = false
        members[i] = []
        var nextGeneration = generations[i] &+ 1
        if nextGeneration == 0 { nextGeneration = 1 }
        generations[i] = nextGeneration
        freeList.append(index)
        liveCount -= 1
    }
}
