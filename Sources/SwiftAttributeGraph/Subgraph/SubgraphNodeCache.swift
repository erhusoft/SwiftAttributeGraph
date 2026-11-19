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
    }

    private(set) var entries: [Key: Entry] = [:]
    private(set) var keyByNode: [UInt32: Key] = [:]

    mutating func insert(key: Key, node: UInt32, generation: UInt32, age: UInt8 = 0) {
        entries[key] = Entry(node: node, generation: generation, age: age)
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
            entries[key] = entry
        }
    }

    mutating func collect(maxAge: UInt8) -> [UInt32] {
        var expired: [UInt32] = []
        for (key, var entry) in entries where entry.age > 0 {
            entry.age &+= 1
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

    mutating func remove(node: UInt32) {
        if let key = keyByNode.removeValue(forKey: node) {
            entries.removeValue(forKey: key)
        }
    }
}
