@usableFromInline
class Node {
    @usableFromInline struct Edge {
        @usableFromInline let source: Int
        @usableFromInline let version: UInt64
        @usableFromInline init(source: Int, version: UInt64) {
            self.source = source
            self.version = version
        }
    }

    let owner: Int
    var inputs: [Edge] = []
    var outputs: Set<Int> = []
    @usableFromInline var reads: [Edge] = []
    @usableFromInline var readSet: Set<Int> = []
    @usableFromInline var changes: [Int: Bool] = [:]
    @usableFromInline var version: UInt64 = 1
    @usableFromInline var dirty = false
    var evaluating = false
    @usableFromInline var hasRun = false
    var forceRun = false

    init(owner: Int) { self.owner = owner }
    func begin(in graph: PrototypeGraph, index: Int) { preconditionFailure("an input cannot run") }
    func step() -> RuleStep { preconditionFailure("an input cannot run") }
    func finish() -> Bool { preconditionFailure("an input cannot run") }
}
