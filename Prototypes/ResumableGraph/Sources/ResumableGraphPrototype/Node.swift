class Node {
    struct Edge {
        let source: Int
        let version: UInt64
    }

    let owner: Int
    var inputs: [Edge] = []
    var outputs: Set<Int> = []
    var reads: [Edge] = []
    var readSet: Set<Int> = []
    var changes: [Int: Bool] = [:]
    var version: UInt64 = 1
    var dirty = false
    var evaluating = false
    var hasRun = false
    var forceRun = false

    init(owner: Int) { self.owner = owner }
    func begin(in graph: PrototypeGraph, index: Int) { preconditionFailure("an input cannot run") }
    func step() -> RuleStep { preconditionFailure("an input cannot run") }
    func finish() -> Bool { preconditionFailure("an input cannot run") }
}
