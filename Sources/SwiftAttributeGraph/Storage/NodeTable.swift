/// Slot table of the nodes of a graph, as parallel arrays indexed by slot.
///
/// The common part of a node (state bits, version, edges, owner) is not generic and holds no reference counting, which
/// is what made propagation 3.8× faster in the SwiftGraph storage study (G1–G3). Only `boxes` holds a reference.
struct NodeTable {
    private(set) var generations: [UInt32] = []
    var state: [UInt16] = []
    var versions: [UInt32] = []
    var inputs: [[InputEdge]] = []
    var outputs: [[UInt32]] = []
    private(set) var owners: [UInt32] = []
    private(set) var boxes: [NodeBox?] = []
    private var freeList: [UInt32] = []
    private(set) var liveCount = 0

    /// Number of slots ever created (live or free).
    var slotCount: Int { generations.count }

    /// Reserves a slot (reusing a freed one if any) and stores the node in it.
    mutating func allocate(owner: UInt32, box: NodeBox, state initialState: UInt16, version: UInt32) -> AttributeID {
        liveCount += 1
        if let index = freeList.popLast() {
            let i = Int(index)
            state[i] = initialState
            versions[i] = version
            owners[i] = owner
            boxes[i] = box
            return AttributeID(index: index, generation: generations[i])
        }
        generations.append(1)
        state.append(initialState)
        versions.append(version)
        inputs.append([])
        outputs.append([])
        owners.append(owner)
        boxes.append(box)
        return AttributeID(index: UInt32(generations.count - 1), generation: 1)
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
        boxes[i] = nil
        state[i] = 0
        inputs[i] = []
        outputs[i] = []
        var next = generations[i] &+ 1
        if next == 0 { next = 1 }
        generations[i] = next
        freeList.append(index)
        liveCount -= 1
    }
}
