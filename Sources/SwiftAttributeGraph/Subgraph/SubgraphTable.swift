/// Storage of the subgraphs of a graph: slot table with generations and the list of attribute slots each one owns.
struct SubgraphTable {
    private(set) var generations: [UInt32] = []
    private(set) var members: [[UInt32]] = []
    private var freeList: [UInt32] = []

    mutating func allocate() -> SubgraphID {
        if let index = freeList.popLast() {
            return SubgraphID(index: index, generation: generations[Int(index)])
        }
        generations.append(1)
        members.append([])
        return SubgraphID(index: UInt32(generations.count - 1), generation: 1)
    }

    func isLive(_ id: SubgraphID) -> Bool {
        let index = Int(id.index)
        return index < generations.count && generations[index] == id.generation
    }

    mutating func add(member: UInt32, to id: SubgraphID) { members[Int(id.index)].append(member) }

    /// Releases the subgraph and returns the slots of the attributes it owned.
    mutating func release(_ id: SubgraphID) -> [UInt32] {
        let index = Int(id.index)
        let owned = members[index]
        members[index] = []
        var next = generations[index] &+ 1
        if next == 0 { next = 1 }
        generations[index] = next
        freeList.append(UInt32(index))
        return owned
    }
}
