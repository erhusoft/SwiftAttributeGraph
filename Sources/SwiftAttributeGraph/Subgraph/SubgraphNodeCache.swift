/// Per-subgraph cache of reusable attributes keyed by `(typeID, key)`, supporting parking and age-based collection
/// (matching `AG::NodeCache` in native AttributeGraph).
struct SubgraphNodeCache {
    struct Key: Hashable {
        let typeID: ObjectIdentifier
        let key: AnyHashable
    }

    struct Entry {
        let node: UInt32
        let generation: UInt32
        var age: UInt8
        /// Order in which the entry was parked: the smallest one is the oldest parked entry.
        var parkedAt: UInt64 = 0
    }

    private(set) var entries: [Key: Entry] = [:]
    private(set) var keyByNode: [UInt32: Key] = [:]
    private var parkCounter: UInt64 = 0
    /// The inner `update` closure of the first `_cachedValue` call per key type: native asks for it once per type and subgraph, and
    /// the entries that follow reuse it (oracle scenario `c13`).
    var updaters: [ObjectIdentifier: (UnsafeMutableRawPointer, AnyAttribute) -> Void] = [:]
    /// Whether a pass ever aged an entry to 2 or more; until then no entry can be taken over, so creating one skips the scan.
    private var mayHaveAged = false

    mutating func insert(key: Key, node: UInt32, generation: UInt32, age: UInt8 = 0) {
        parkCounter += 1
        entries[key] = Entry(node: node, generation: generation, age: age, parkedAt: age > 0 ? parkCounter : 0)
        keyByNode[node] = key
    }

    mutating func lookup(key: Key) -> Entry? {
        guard var entry = entries[key] else { return nil }
        entry.age = 0
        entries[key] = entry
        return entry
    }

    mutating func park(node: UInt32) {
        guard let key = keyByNode[node], var entry = entries[key] else { return }
        if entry.age == 0 {
            entry.age = 1
            parkCounter += 1
            entry.parkedAt = parkCounter
            entries[key] = entry
        }
    }

    mutating func collect(maxAge: UInt8) -> [UInt32] {
        var expired: [UInt32] = []
        for (key, var entry) in entries where entry.age > 0 {
            entry.age &+= 1
            if entry.age >= 2 { mayHaveAged = true }
            if entry.age >= maxAge {
                entries.removeValue(forKey: key)
                keyByNode.removeValue(forKey: entry.node)
                expired.append(entry.node)
            } else {
                entries[key] = entry
            }
        }
        return expired
    }

    /// Removes and returns the node of the oldest parked entry of `typeID` whose age is 2 or more, which a new key takes
    /// over (`cache_fetch` in native AttributeGraph; measured with oracle scenario `m3`).
    mutating func takeOldestRecyclable(typeID: ObjectIdentifier) -> UInt32? {
        guard mayHaveAged else { return nil }
        var best: (key: Key, entry: Entry)?
        for (key, entry) in entries where key.typeID == typeID && entry.age >= 2 {
            if best == nil || entry.parkedAt < best!.entry.parkedAt { best = (key, entry) }
        }
        guard let best else { return nil }
        entries.removeValue(forKey: best.key)
        keyByNode.removeValue(forKey: best.entry.node)
        return best.entry.node
    }

    mutating func remove(node: UInt32) {
        if let key = keyByNode.removeValue(forKey: node) {
            entries.removeValue(forKey: key)
        }
    }
}
