final class PrototypeGraph {
    private struct Owner {
        var live = true
        var falling = false
        var members: [Int] = []
    }
    private struct Frame {
        let node: Int
        var nextInput = 0
        var changed = false
        var started = false
        var waiting: Int?
    }

    var nodes: [Node?] = []
    private let identity = GraphIdentity()
    private var owners: [Owner] = [Owner()]
    private var currentOwner = 0
    private var deferredOwners: [Int] = []
    private var frames: [Frame] = []
    let owningThread = threadIdentity()
    private(set) var runningNode: Int?
    private var activeSteps = 0
    private(set) var maximumActiveSteps = 0
    private(set) var maximumFrameCount = 0
    private(set) var maximumFrameCapacity = 0
    private(set) var nodeCount = 0
    var liveOwnerCount: Int { owners.filter(\.live).count }
    var frameCount: Int { frames.count }
    var frameStorageBytes: Int { maximumFrameCapacity * MemoryLayout<Frame>.stride }

    func checkThread() { precondition(threadIdentity() == owningThread, "the graph must stay on its original thread") }

    func makeOwner() -> Int {
        checkThread()
        owners.append(Owner())
        return owners.count - 1
    }

    func withOwner<T>(_ owner: Int, _ body: () -> T) -> T {
        checkThread()
        precondition(owners[owner].live && !owners[owner].falling)
        let previous = currentOwner
        currentOwner = owner
        defer { currentOwner = previous }
        return body()
    }

    func makeInput<T>(_ value: T) -> Attribute<T> {
        allocate(TypedNode(owner: currentOwner, value: value))
    }

    func makeRule<R: ResumableRule>(_ rule: R) -> Attribute<R.Value> {
        allocate(RuleNode(owner: currentOwner, rule: rule))
    }

    private func allocate<T>(_ node: TypedNode<T>) -> Attribute<T> {
        checkThread()
        precondition(owners[currentOwner].live && !owners[currentOwner].falling)
        let index = nodes.count
        nodes.append(node)
        owners[currentOwner].members.append(index)
        nodeCount += 1
        return Attribute(index: index, graph: identity)
    }

    func checkedNode(_ attribute: AnyAttribute) -> Node {
        precondition(attribute.graph === identity, "an attribute belongs to another graph")
        precondition(nodes.indices.contains(attribute.index), "invalid attribute")
        guard let node = nodes[attribute.index] else { preconditionFailure("the attribute is dead") }
        return node
    }

    func typedNode<T>(_ attribute: Attribute<T>) -> TypedNode<T> {
        guard let node = checkedNode(attribute.erased) as? TypedNode<T> else { preconditionFailure("wrong attribute type") }
        return node
    }

    func value<T>(of attribute: Attribute<T>) -> T {
        checkThread()
        precondition(frames.isEmpty, "a rule must poll instead of nesting a synchronous read")
        let node = typedNode(attribute)
        if node.dirty { update(attribute.index) }
        let result = node.value!
        let pending = deferredOwners
        deferredOwners.removeAll(keepingCapacity: true)
        for owner in pending where owners[owner].live { free(owner) }
        return result
    }

    func setValue<T>(_ value: T, for attribute: Attribute<T>) {
        checkThread()
        precondition(frames.isEmpty, "a rule cannot write inputs")
        let node = typedNode(attribute)
        precondition(node.hasRun == false && !node.dirty, "only an input can be written")
        if node.store(value) {
            node.version += 1
            markDirty(Array(node.outputs))
        }
    }

    private func markDirty(_ roots: [Int]) {
        var stack = roots
        while let index = stack.popLast() {
            guard let node = nodes[index], !node.dirty else { continue }
            node.dirty = true
            stack.append(contentsOf: node.outputs)
        }
    }

    private func push(_ index: Int) {
        let node = nodes[index]!
        precondition(!node.evaluating, "cycle detected")
        node.evaluating = true
        frames.append(Frame(node: index))
        maximumFrameCount = max(maximumFrameCount, frames.count)
        maximumFrameCapacity = max(maximumFrameCapacity, frames.capacity)
    }

    private func update(_ root: Int) {
        push(root)
        while !frames.isEmpty {
            let top = frames.count - 1
            let index = frames[top].node
            let node = nodes[index]!
            if !frames[top].started {
                if frames[top].nextInput < node.inputs.count {
                    let edge = node.inputs[frames[top].nextInput]
                    if nodes[edge.source]!.dirty { push(edge.source); continue }
                    frames[top].changed = frames[top].changed || nodes[edge.source]!.version != edge.version
                    frames[top].nextInput += 1
                    continue
                }
                if node.hasRun && !node.forceRun && !frames[top].changed {
                    node.dirty = false
                    node.evaluating = false
                    frames.removeLast()
                    continue
                }
                node.reads.removeAll(keepingCapacity: true)
                node.readSet.removeAll(keepingCapacity: true)
                node.changes = Dictionary(uniqueKeysWithValues: node.inputs.map {
                    ($0.source, nodes[$0.source]!.version != $0.version)
                })
                node.begin(in: self, index: index)
                frames[top].started = true
            }
            if let source = frames[top].waiting {
                recordRead(source, into: index)
                frames[top].waiting = nil
            }
            let step = runStep(of: index)
            switch step {
            case .needsInput(let attribute):
                let source = checkedNode(attribute)
                precondition(source.dirty, "a step must poll a ready input rather than repeatedly request it")
                frames[top].waiting = attribute.index
                push(attribute.index)
            case .finished:
                let changed = node.finish()
                for edge in node.inputs where !node.readSet.contains(edge.source) {
                    nodes[edge.source]!.outputs.remove(index)
                }
                for edge in node.reads { nodes[edge.source]!.outputs.insert(index) }
                node.inputs = node.reads
                node.reads = []
                node.readSet.removeAll(keepingCapacity: true)
                node.changes.removeAll(keepingCapacity: true)
                node.hasRun = true
                node.forceRun = false
                node.dirty = false
                node.evaluating = false
                if changed { node.version += 1 }
                frames.removeLast()
            }
        }
    }

    private func runStep(of index: Int) -> RuleStep {
        checkThread()
        let previousOwner = currentOwner
        let owner = nodes[index]!.owner
        currentOwner = owners[owner].falling ? 0 : owner
        runningNode = index
        activeSteps += 1
        maximumActiveSteps = max(maximumActiveSteps, activeSteps)
        defer { activeSteps -= 1; runningNode = nil; currentOwner = previousOwner }
        return nodes[index]!.step()
    }

    func recordRead(_ source: Int, into consumer: Int) {
        let node = nodes[consumer]!
        if node.readSet.insert(source).inserted {
            node.reads.append(Node.Edge(source: source, version: nodes[source]!.version))
        }
    }

    func inputs(of attribute: AnyAttribute) -> [AnyAttribute] {
        checkedNode(attribute).inputs.map { AnyAttribute(index: $0.source, graph: identity) }
    }
    func isDirty(_ attribute: AnyAttribute) -> Bool { checkedNode(attribute).dirty }
    func version(of attribute: AnyAttribute) -> UInt64 { checkedNode(attribute).version }

    func invalidate(_ owner: Int) {
        checkThread()
        precondition(owner != 0 && owners[owner].live)
        if owners[owner].falling { return }
        owners[owner].falling = true
        if frames.isEmpty { free(owner) } else { deferredOwners.append(owner) }
    }

    private func free(_ owner: Int) {
        let doomed = Set(owners[owner].members)
        var affected: [Int] = []
        for index in doomed {
            let node = nodes[index]!
            for edge in node.inputs where !doomed.contains(edge.source) { nodes[edge.source]!.outputs.remove(index) }
            for output in node.outputs where !doomed.contains(output) {
                nodes[output]!.inputs.removeAll { $0.source == index }
                nodes[output]!.forceRun = true
                affected.append(output)
            }
        }
        for index in doomed { nodes[index] = nil; nodeCount -= 1 }
        owners[owner].members = []
        owners[owner].live = false
        markDirty(affected)
    }
}
