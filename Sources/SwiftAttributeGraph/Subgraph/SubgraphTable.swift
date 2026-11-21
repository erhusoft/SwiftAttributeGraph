/// Storage of the subgraphs of a graph: a slot table with generations, the list of attribute slots each one owns,
/// their invalidation context, and the DAG (parent and child adjacency lists per slot).
struct SubgraphTable {
    /// Marks "no subgraph" in legacy index helpers.
    static let none = UInt32.max
    /// Default context ID for the root subgraph and its descendants unless overridden.
    static let defaultContext: UInt32 = 1

    private(set) var generations: [UInt32] = []
    /// The graph tag in the top 16 bits of every generation of this table (see `GraphRegistry`).
    var generationBase: UInt32 = 0
    private(set) var members: [[UInt32]] = []
    private(set) var parents: [[UInt32]] = []
    /// Raw child adjacency list per slot, in link order. Entries equal to ``none`` are tombstones left by O(1)
    /// removals in ``removeChild(_:from:)`` and ``release(index:)`` so that sibling order is preserved without O(N)
    /// array shifts (`multi-observer-tree-order-and-cancel`, `subgraph-flags-forEach-and-update` [O]).
    private var rawChildren: [[UInt32]] = []
    /// The child tag of each entry of `rawChildren`, in the same position: two bits (`AGSubgraphAddChild2`), zero when linked
    /// without a tag.
    private var rawTags: [[UInt8]] = []
    /// For each slot `c`, `positionInParents[c][k]` is the index of `c` inside `rawChildren[parents[c][k]]`, enabling
    /// O(1) tombstoning when `c` is unlinked or released.
    private var positionInParents: [[UInt32]] = []
    /// Number of ``none`` tombstones currently in `rawChildren[p]`; compacted when tombstones reach half of
    /// `rawChildren[p].count`.
    private var childTombstoneCount: [UInt32] = []
    private(set) var contexts: [UInt32] = []
    /// Set on a subgraph that is being invalidated or waits for the end of the update that asked for it: nothing can be
    /// created in it, but what it owns can still be read until it is freed.
    private var falling: [Bool] = []
    var dirtyOwnFlags: [UInt8] = []
    var dirtyDescendantFlags: [UInt8] = []
    private var visitedEpoch: [UInt32] = []
    private var currentEpoch: UInt32 = 0
    private var freeList: [UInt32] = []
    private(set) var liveCount = 0
    /// Number of subgraphs ever allocated, the root included.
    private(set) var createdCount = 0

    /// Number of slots ever created (live or free).
    var slotCount: Int { generations.count }

    /// Number of free slots waiting to be reused.
    var freeListCount: Int { freeList.count }

    mutating func allocate(parent: SubgraphID?, context: UInt32? = nil) -> SubgraphID {
        liveCount += 1
        createdCount += 1
        let index: UInt32
        if let reused = freeList.popLast() {
            index = reused
        } else {
            generations.append(generationBase | 1)
            members.append([])
            parents.append([])
            rawChildren.append([])
            rawTags.append([])
            positionInParents.append([])
            childTombstoneCount.append(0)
            contexts.append(SubgraphTable.defaultContext)
            falling.append(false)
            dirtyOwnFlags.append(0)
            dirtyDescendantFlags.append(0)
            visitedEpoch.append(0)
            index = UInt32(generations.count - 1)
        }
        let i = Int(index)
        let resolvedContext = context ?? parent.map { contexts[Int($0.index)] } ?? SubgraphTable.defaultContext
        contexts[i] = resolvedContext
        if let parent {
            let p = Int(parent.index)
            let pos = UInt32(rawChildren[p].count)
            rawChildren[p].append(index)
            rawTags[p].append(0)
            parents[i].append(parent.index)
            positionInParents[i].append(pos)
        }
        return SubgraphID(index: index, generation: generations[i])
    }

    func isLive(_ id: SubgraphID) -> Bool {
        let index = Int(id.index)
        return index < generations.count && generations[index] == id.generation
    }

    func isFalling(index: UInt32) -> Bool { falling[Int(index)] }
    mutating func setFalling(index: UInt32, _ value: Bool) { falling[Int(index)] = value }
    func context(of index: UInt32) -> UInt32 { contexts[Int(index)] }

    /// The ID of the live subgraph in a slot.
    func id(at index: UInt32) -> SubgraphID { SubgraphID(index: index, generation: generations[Int(index)]) }

    /// The first parent of a subgraph, if any.
    func parent(of id: SubgraphID) -> SubgraphID? {
        guard let first = parents[Int(id.index)].first else { return nil }
        return self.id(at: first)
    }

    /// All living parent indices of a subgraph.
    func parents(of index: UInt32) -> [UInt32] {
        parents[Int(index)]
    }

    /// The children of a subgraph, in the order they were linked.
    func children(of index: UInt32) -> [UInt32] {
        let p = Int(index)
        if childTombstoneCount[p] == 0 {
            return rawChildren[p]
        }
        return rawChildren[p].filter { $0 != SubgraphTable.none }
    }

    /// The live children of a subgraph with their tags, in the order they were linked.
    func childrenWithTags(of index: UInt32) -> [(child: UInt32, tag: UInt8)] {
        let p = Int(index)
        var result: [(child: UInt32, tag: UInt8)] = []
        for (position, child) in rawChildren[p].enumerated() where child != SubgraphTable.none {
            result.append((child, rawTags[p][position]))
        }
        return result
    }

    /// Compacts `rawChildren[p]` in place when its tombstone count reaches at least half of its buffer length (minimum
    /// 64), updating `positionInParents` of each surviving child in O(surviving) so amortized removal is O(1) while
    /// preserving exact creation/link order.
    private mutating func compactChildrenIfNeeded(of parent: UInt32) {
        let p = Int(parent)
        let dead = Int(childTombstoneCount[p])
        let total = rawChildren[p].count
        guard dead >= 64 && dead * 2 >= total else { return }
        var write = 0
        var keptTags: [UInt8] = []
        for read in 0..<total {
            let child = rawChildren[p][read]
            guard child != SubgraphTable.none else { continue }
            keptTags.append(rawTags[p][read])
            if write != read {
                rawChildren[p][write] = child
                let c = Int(child)
                if let k = parents[c].firstIndex(of: parent) {
                    positionInParents[c][k] = UInt32(write)
                }
            }
            write += 1
        }
        rawChildren[p].removeSubrange(write..<total)
        rawTags[p] = keptTags
        childTombstoneCount[p] = 0
    }

    /// Marks `child` as a tombstone at `pos` inside `rawChildren[parent]`.
    private mutating func markChildTombstone(in parent: UInt32, at pos: UInt32) {
        let p = Int(parent)
        let idx = Int(pos)
        if idx < rawChildren[p].count && rawChildren[p][idx] != SubgraphTable.none {
            rawChildren[p][idx] = SubgraphTable.none
            childTombstoneCount[p] &+= 1
            compactChildrenIfNeeded(of: parent)
        }
    }

    /// Links `child` under `parent` in the DAG. Rejects self-links and cycles.
    ///
    /// The cycle check walks the ancestors of `parent` (O(depth)), so it only runs when `child` already has children:
    /// a childless `child` cannot be an ancestor of `parent`, so linking it cannot close a cycle. That keeps building a
    /// chain top-down (the usual host pattern) O(1) per call instead of O(depth) [measured here; see
    /// `SubgraphChainPerformanceTests`]. Native `Subgraph::add_child` checks only the graph and a duplicate parent and
    /// does no ancestor walk apart from flag propagation [O, PHASE12 disassembly]; native timing for 20,000 links was
    /// 52 ms [O]. The cycle rejection itself is this engine's own addition (native behaviour on a cycle is [?]).
    mutating func addChild(_ child: UInt32, to parent: UInt32, tag: UInt8 = 0) {
        precondition(child != parent, "addChild: a subgraph cannot be its own parent")
        let p = Int(parent)
        let c = Int(child)
        let childHasLiveChildren = rawChildren[c].count > Int(childTombstoneCount[c])
        precondition(!childHasLiveChildren || !isAncestor(child, of: parent),
                     "addChild: cycle detected in subgraph DAG")
        if !parents[c].contains(parent) {
            let pos = UInt32(rawChildren[p].count)
            rawChildren[p].append(child)
            rawTags[p].append(tag & 0x3)
            parents[c].append(parent)
            positionInParents[c].append(pos)
        }
    }

    /// Unlinks `child` from `parent` without invalidating `child`.
    mutating func removeChild(_ child: UInt32, from parent: UInt32) {
        let c = Int(child)
        guard let k = parents[c].firstIndex(of: parent) else { return }
        let pos = positionInParents[c][k]
        parents[c].remove(at: k)
        positionInParents[c].remove(at: k)
        markChildTombstone(in: parent, at: pos)
    }

    private mutating func nextEpoch() -> UInt32 {
        currentEpoch &+= 1
        if currentEpoch == 0 {
            visitedEpoch.replaceSubrange(0..<visitedEpoch.count, with: repeatElement(0, count: visitedEpoch.count))
            currentEpoch = 1
        }
        return currentEpoch
    }

    /// Whether `ancestor` is `node` or an ancestor of `node` in the subgraph DAG. Iterative with epoch deduplication.
    mutating func isAncestor(_ ancestor: UInt32, of node: UInt32) -> Bool {
        if ancestor == node { return true }
        let epoch = nextEpoch()
        var stack: [UInt32] = [node]
        visitedEpoch[Int(node)] = epoch
        while let current = stack.popLast() {
            for p in parents[Int(current)] {
                if p == ancestor { return true }
                if visitedEpoch[Int(p)] != epoch {
                    visitedEpoch[Int(p)] = epoch
                    stack.append(p)
                }
            }
        }
        return false
    }

    /// The subgraph and all its non-falling descendants in pre-order where child subgraphs are visited in reverse
    /// creation order, matching `Subgraph.forEach` and `Subgraph.update(flags:)` in native AttributeGraph.
    /// Deduplicates DAG diamonds with `visitedEpoch` and uses an explicit stack.
    mutating func reverseCreationSubgraphOrder(from root: UInt32) -> [UInt32] {
        guard !falling[Int(root)] else { return [] }
        let epoch = nextEpoch()
        var result: [UInt32] = []
        var stack: [UInt32] = [root]
        while let current = stack.popLast() {
            let c = Int(current)
            if falling[c] || visitedEpoch[c] == epoch { continue }
            visitedEpoch[c] = epoch
            result.append(current)
            for child in rawChildren[c] where child != SubgraphTable.none {
                let ci = Int(child)
                if !falling[ci] && visitedEpoch[ci] != epoch {
                    stack.append(child)
                }
            }
        }
        return result
    }

    mutating func add(member: UInt32, to id: SubgraphID) { members[Int(id.index)].append(member) }

    /// Computes the context-aware invalidation closure from `root`:
    /// - Children sharing `contexts[root]` are invalidated (deduplicated) and returned in parent-before-child LIFO order.
    /// - Children in a different context are NOT invalidated; their `(parent, child)` edges are returned in `detachedEdges`.
    mutating func invalidationPlan(from root: UInt32) -> (toInvalidate: [UInt32], detachedEdges: [(parent: UInt32, child: UInt32)]) {
        let rootContext = contexts[Int(root)]
        let epoch = nextEpoch()
        var toInvalidate: [UInt32] = []
        var detachedEdges: [(parent: UInt32, child: UInt32)] = []
        var stack: [UInt32] = [root]
        visitedEpoch[Int(root)] = epoch

        while let current = stack.popLast() {
            toInvalidate.append(current)
            for child in rawChildren[Int(current)] where child != SubgraphTable.none {
                let ci = Int(child)
                if contexts[ci] == rootContext {
                    if visitedEpoch[ci] != epoch {
                        visitedEpoch[ci] = epoch
                        stack.append(child)
                    }
                } else {
                    detachedEdges.append((current, child))
                }
            }
        }
        return (toInvalidate, detachedEdges)
    }

    /// Takes the attribute slots a subgraph owned (the subgraph itself is released with ``release(_:)``).
    mutating func takeMembers(of index: UInt32) -> [UInt32] {
        let owned = members[Int(index)]
        members[Int(index)] = []
        return owned
    }

    /// Releases a subgraph whose attributes were already freed: unlinks it from all living parents and children,
    /// bumps the generation and queues the slot for reuse.
    mutating func release(index: UInt32) {
        let i = Int(index)
        for k in 0..<parents[i].count {
            let p = parents[i][k]
            let pos = positionInParents[i][k]
            markChildTombstone(in: p, at: pos)
        }
        for c in rawChildren[i] where c != SubgraphTable.none {
            let ci = Int(c)
            if let k = parents[ci].firstIndex(of: index) {
                parents[ci].remove(at: k)
                positionInParents[ci].remove(at: k)
            }
        }
        parents[i] = []
        positionInParents[i] = []
        rawChildren[i] = []
        rawTags[i] = []
        childTombstoneCount[i] = 0
        falling[i] = false
        members[i] = []
        contexts[i] = SubgraphTable.defaultContext
        // Same rule as `NodeTable.free(index:)`: a slot whose 16 reuse bits are used up is retired.
        let generation = generations[i]
        dirtyOwnFlags[i] = 0
        dirtyDescendantFlags[i] = 0
        if generation & 0xFFFF != 0xFFFF {
            generations[i] = generation + 1
            freeList.append(index)
        } else {
            generations[i] = generation & 0xFFFF_0000       // counter 0 is never handed out: no ID matches the slot again
        }
        liveCount -= 1
    }

    mutating func markDirtyFlags(_ flags: UInt8, on sgIndex: UInt32) {
        guard flags != 0 else { return }
        let start = Int(sgIndex)
        guard start < dirtyOwnFlags.count else { return }
        if (dirtyOwnFlags[start] & flags) == flags { return }
        dirtyOwnFlags[start] |= flags

        var queue = parents[start]
        var head = 0
        while head < queue.count {
            let p = Int(queue[head])
            head += 1
            if (dirtyDescendantFlags[p] & flags) == flags { continue }
            dirtyDescendantFlags[p] |= flags
            queue.append(contentsOf: parents[p])
        }
    }

    mutating func clearDirtyFlags(_ flags: UInt8, on sgIndex: UInt32) {
        let i = Int(sgIndex)
        guard i < dirtyOwnFlags.count else { return }
        dirtyOwnFlags[i] &= ~flags
        dirtyDescendantFlags[i] &= ~flags
    }
}
