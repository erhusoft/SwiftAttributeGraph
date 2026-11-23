/// Slot table of the nodes of a graph, as parallel arrays indexed by slot.
///
/// The common part of a node (state bits, version, edges, owner) is not generic and holds no reference counting, which
/// is what made propagation 3.8× faster in the storage study (G1–G3). Only `boxes` holds a reference.
struct NodeTable {
    private(set) var generations: [UInt32] = []
    /// The graph tag in the top 16 bits of every generation of this table (see `GraphRegistry`).
    var generationBase: UInt32 = 0
    var state: [UInt16] = []
    var flags: [UInt8] = []
    var versions: [UInt32] = []
    var inputs: [[InputEdge]] = []
    var outputs: [[UInt32]] = []
    private(set) var owners: [UInt32] = []
    private(set) var boxes: [NodeBox?] = []
    private var freeList: [UInt32] = []
    private(set) var liveCount = 0
    /// Live and ever-created nodes that carry `NodeState.indirect`, which native `AGGraphGetCounter` leaves out of
    /// `nodes` and `createdNodes`.
    private(set) var liveIndirectCount = 0
    private(set) var createdIndirectCount = 0

    /// Number of slots ever created (live or free).
    var slotCount: Int { generations.count }

    /// Number of free slots waiting to be reused.
    var freeListCount: Int { freeList.count }

    /// Reserves a slot (reusing a freed one if any) and stores the node in it.
    mutating func allocate(owner: UInt32, box: NodeBox, state initialState: UInt16, version: UInt32) -> AttributeID {
        liveCount += 1
        if initialState & NodeState.indirect != 0 {
            liveIndirectCount += 1
            createdIndirectCount += 1
        }
        if let index = freeList.popLast() {
            let i = Int(index)
            state[i] = initialState
            flags[i] = 0
            versions[i] = version
            owners[i] = owner
            boxes[i] = box
            return AttributeID(index: index, generation: generations[i])
        }
        generations.append(generationBase | 1)
        state.append(initialState)
        flags.append(0)
        versions.append(version)
        inputs.append([])
        outputs.append([])
        owners.append(owner)
        boxes.append(box)
        return AttributeID(index: UInt32(generations.count - 1), generation: generations[generations.count - 1])
    }

    /// Whether the ID names a live node.
    func isLive(_ id: AttributeID) -> Bool {
        let index = Int(id.index)
        return index < generations.count && generations[index] == id.generation && boxes[index] != nil
    }

    func isLive(index: UInt32) -> Bool { boxes[Int(index)] != nil }

    func box(at index: UInt32) -> NodeBox { boxes[Int(index)].unsafelyUnwrapped }

    func owner(at index: UInt32) -> UInt32 { owners[Int(index)] }

    /// Frees a slot: drops the node, bumps the generation (so old IDs stop resolving) and queues the slot for reuse.
    mutating func free(index: UInt32) {
        let i = Int(index)
        if state[i] & NodeState.indirect != 0 { liveIndirectCount -= 1 }
        boxes[i] = nil
        state[i] = 0
        flags[i] = 0
        inputs[i] = []
        outputs[i] = []
        // The low 16 bits count the reuses of the slot. When they are used up the slot is retired instead of wrapping, so
        // the tag in the top bits is never disturbed and an old ID never matches a later node.
        let generation = generations[i]
        if generation & 0xFFFF != 0xFFFF {
            generations[i] = generation + 1
            freeList.append(index)
        } else {
            generations[i] = generation & 0xFFFF_0000       // counter 0 is never handed out: no ID matches the slot again
        }
        liveCount -= 1
    }
}
