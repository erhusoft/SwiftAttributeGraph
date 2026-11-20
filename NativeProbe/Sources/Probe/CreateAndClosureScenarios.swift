#if NATIVE_ATTRIBUTE_GRAPH
import AttributeGraph
#else
import SwiftAttributeGraph
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// Two questions about a graph engine, asked to native AttributeGraph and to the local engine with the same code:
// 1. Attributes created while a rule is being evaluated: does the creation work, where are they owned, does the creator
//    depend on what it read from them, and are they freed with their owner?
// 2. Values that contain closures: when does a rule's new value count as unchanged (equality cut), for closures that are
//    recreated, reused, or reused while the state they capture changes; plus `-0.0` and `NaN` doubles.
// Run with `Probe cc <scenario|a,b,...|all>`, one process per scenario. Every line is flushed before the driver closes,
// so a trap while closing still leaves the trace. Native-only diagnostics go to standard error and are not compared.

#if NATIVE_ATTRIBUTE_GRAPH
private struct CCRule<Value>: AttributeGraph.Rule {
    let body: () -> Value
    var value: Value { body() }
}

/// Creates an input with the engine's default placement (native: `Subgraph.current`), not the driver's scope.
func ccRawInput<V>(_ d: Driver, _ value: V) -> Handle<V> { Handle(value: value) }
/// Creates a rule with the engine's default placement and default comparison.
func ccRawRule<V>(_ d: Driver, _ body: @escaping () -> V) -> Handle<V> { Handle(CCRule(body: body)) }

/// Native-only: whether `Subgraph.current` is `subgraph` (identity of the subgraph object).
func ccCurrentIs(_ subgraph: SubgraphHandle) -> String {
    guard let current = AttributeGraph.Subgraph.current else { return "nil" }
    return current === subgraph ? "yes" : "other"
}

/// Native-only: the comparison mode of the probe's rule body for `V`.
func ccComparisonMode<V>(_: V.Type) -> String { "\(CCRule<V>.comparisonMode.rawValue)" }

/// Runs `body` with `subgraph` as the engine's current subgraph (native `Subgraph.apply`).
func ccWithCurrent<T>(_ d: Driver, _ subgraph: SubgraphHandle, _ body: () -> T) -> T { subgraph.apply(body) }
#else
/// Runs `body` with `subgraph` as the engine's current subgraph (`Graph.withCurrent`).
func ccWithCurrent<T>(_ d: Driver, _ subgraph: SubgraphHandle, _ body: () -> T) -> T { d.graph.withCurrent(subgraph, body) }
func ccRawInput<V>(_ d: Driver, _ value: V) -> Handle<V> { d.graph.makeInput(value) }
func ccRawRule<V>(_ d: Driver, _ body: @escaping () -> V) -> Handle<V> { d.graph.makeRule(body) }
func ccCurrentIs(_ subgraph: SubgraphHandle) -> String { "n/a" }
func ccComparisonMode<V>(_: V.Type) -> String { "viewValue" }
#endif

func ccEmit(_ line: String) {
    print(line)
    fflush(stdout)
}

func ccDiagnostic(_ line: String) {
    fputs(line + "\n", stderr)
}

// MARK: - 1. Creation during evaluation

/// When set (`-scoped` scenario variants), the top-level reads and `update(flags:)` calls of the creation scenarios run
/// with the driver's scope as the current subgraph, so native creation has a subgraph to use.
nonisolated(unsafe) var ccScopedReads = false

/// Reads `attribute` at top level, inside the driver's scope when `ccScopedReads` is set.
func ccRead<V>(_ d: Driver, _ attribute: Handle<V>) -> V {
    ccScopedReads ? ccWithCurrent(d, d.scope) { d.read(attribute) } : d.read(attribute)
}

/// Runs `update(flags:)` at top level, inside the driver's scope when `ccScopedReads` is set.
func ccUpdate(_ d: Driver, _ subgraph: SubgraphHandle, flags: UInt8) {
    if ccScopedReads { ccWithCurrent(d, d.scope) { d.update(subgraph, flags: flags) } } else { d.update(subgraph, flags: flags) }
}

/// Suffix of the scenario name for the scoped variant.
var ccSuffix: String { ccScopedReads ? "-scoped" : "" }

/// The creator rule (owned by a child subgraph `owner`) creates an input on its first run, reads it with a scope input,
/// and returns the sum. Then the created input and the scope input are written, and `owner` is invalidated.
func ccCreateInputInRule() {
    let d = Driver()
    defer { d.close() }
    var log: [String] = []
    let x = d.input(1)
    let owner = d.makeSubgraph()
    var created: Handle<Int>? = nil
    var currentDuringRun = "-"
    let creator = d.withSubgraph(owner) {
        d.rule { () -> Int in
            log.append("creator")
            if created == nil {
                currentDuringRun = ccCurrentIs(owner)
                created = ccRawInput(d, 10)
                log.append("create-input")
            }
            return d.read(x) + d.read(created!)
        }
    }
    let base = d.nodeCount
    var values = [ccRead(d, creator)]
    let afterCreate = d.nodeCount - base
    let weakCreated = d.weak(created!)
    var steps = ["first:\(log)"]
    log.removeAll()
    d.write(20, to: created!)
    values.append(ccRead(d, creator))
    steps.append("writeCreated:\(log)")
    log.removeAll()
    d.write(2, to: x)
    values.append(ccRead(d, creator))
    steps.append("writeScope:\(log)")
    d.invalidate(owner)
    let freed = d.attribute(of: weakCreated) == nil
    ccDiagnostic("cc-create-input-in-rule\(ccSuffix)|native Subgraph.current during run is owner: \(currentDuringRun)")
    ccEmit("cc-create-input-in-rule\(ccSuffix)|values=\(values)|nodesAddedByFirstRead=\(afterCreate)|\(steps.joined(separator: "|"))|createdFreedWithOwner=\(freed)|nodesAfterOwnerInvalidated=\(d.nodeCount - base + afterCreate)")
}

/// The creator rule creates a rule on its first run (the created rule reads a scope input `y`), reads it and returns it.
/// Then `y` is written: does the created rule run, and does the creator run again?
func ccCreateRuleInRule() {
    let d = Driver()
    defer { d.close() }
    var log: [String] = []
    let y = d.input(5)
    let owner = d.makeSubgraph()
    var created: Handle<Int>? = nil
    let creator = d.withSubgraph(owner) {
        d.rule { () -> Int in
            log.append("creator")
            if created == nil {
                created = ccRawRule(d) { () -> Int in log.append("created"); return d.read(y) * 10 }
                log.append("create-rule")
            }
            return d.read(created!) + 1
        }
    }
    let base = d.nodeCount
    var values = [ccRead(d, creator)]
    let afterCreate = d.nodeCount - base
    let weakCreated = d.weak(created!)
    var steps = ["first:\(log)"]
    log.removeAll()
    d.write(6, to: y)
    values.append(ccRead(d, creator))
    steps.append("writeY:\(log)")
    log.removeAll()
    values.append(ccRead(d, created!))
    steps.append("readCreatedDirectly:\(log)")
    d.invalidate(owner)
    let freed = d.attribute(of: weakCreated) == nil
    ccEmit("cc-create-rule-in-rule\(ccSuffix)|values=\(values)|nodesAddedByFirstRead=\(afterCreate)|\(steps.joined(separator: "|"))|createdFreedWithOwner=\(freed)|nodesAfterOwnerInvalidated=\(d.nodeCount - base + afterCreate)")
}

/// The creator rule creates a new rule on every run and reads it. After three runs, how many created rules stay alive,
/// and are they all freed with the owner?
func ccCreateRuleEveryRun() {
    let d = Driver()
    defer { d.close() }
    var log: [String] = []
    let tick = d.input(0)
    let owner = d.makeSubgraph()
    var createdCount = 0
    var weakCreated: [WeakHandle<Int>] = []
    let creator = d.withSubgraph(owner) {
        d.rule { () -> Int in
            log.append("creator")
            let t = d.read(tick)
            createdCount += 1
            let fresh = ccRawRule(d) { () -> Int in log.append("created\(t)"); return t * 100 }
            weakCreated.append(d.weak(fresh))
            return d.read(fresh) + 1
        }
    }
    let base = d.nodeCount
    var values = [ccRead(d, creator)]
    for t in 1...2 {
        d.write(t, to: tick)
        values.append(ccRead(d, creator))
    }
    let nodesAfterRuns = d.nodeCount - base
    let aliveBefore = weakCreated.filter { d.attribute(of: $0) != nil }.count
    d.invalidate(owner)
    let aliveAfter = weakCreated.filter { d.attribute(of: $0) != nil }.count
    ccEmit("cc-create-rule-every-run\(ccSuffix)|values=\(values)|created=\(createdCount)|order=\(log)|nodesAfterRuns=\(nodesAfterRuns)|aliveBeforeInvalidate=\(aliveBefore)|aliveAfterOwnerInvalidated=\(aliveAfter)")
}

/// Same creation as `cc-create-rule-in-rule`, but the creator (flag 1) is first evaluated by `update(flags:)` on its
/// owner instead of a read.
func ccCreateRuleDuringUpdateFlags() {
    let d = Driver()
    defer { d.close() }
    var log: [String] = []
    let y = d.input(5)
    let owner = d.makeSubgraph()
    var created: Handle<Int>? = nil
    let creator = d.withSubgraph(owner) {
        d.rule { () -> Int in
            log.append("creator")
            if created == nil {
                created = ccRawRule(d) { () -> Int in log.append("created"); return d.read(y) * 10 }
                log.append("create-rule")
            }
            return d.read(created!) + 1
        }
    }
    d.setFlags(1, for: creator)
    let base = d.nodeCount
    ccUpdate(d, owner, flags: 1)
    let afterUpdate = d.nodeCount - base
    let firstSteps = log
    log.removeAll()
    let v1 = ccRead(d, creator)
    let readSteps = log
    log.removeAll()
    d.write(6, to: y)
    ccUpdate(d, owner, flags: 1)
    let updateSteps = log
    let weakCreated = d.weak(created!)
    d.invalidate(owner)
    let freed = d.attribute(of: weakCreated) == nil
    ccEmit("cc-create-rule-during-update-flags\(ccSuffix)|nodesAddedByUpdate=\(afterUpdate)|update:\(firstSteps)|thenRead(v=\(v1)):\(readSteps)|writeYThenUpdate:\(updateSteps)|createdFreedWithOwner=\(freed)")
}

/// Where an attribute created during evaluation is placed when the caller has a current subgraph: the creator (owned by
/// `owner`) is read from inside `scope` (`placement` = `caller-scope`), or it creates explicitly inside `owner`
/// (`explicit-owner`). Records which invalidation frees the created input and whether writing it re-runs the creator.
func ccCreatePlacement(placement: String) {
    let d = Driver()
    defer { d.close() }
    var log: [String] = []
    let x = d.input(1)
    let owner = d.makeSubgraph()
    let sibling = d.makeSubgraph()
    var created: Handle<Int>? = nil
    var currentDuringRun = "-"
    let creator = d.withSubgraph(owner) {
        d.rule { () -> Int in
            log.append("creator")
            if created == nil {
                currentDuringRun = "owner:\(ccCurrentIs(owner)),scope:\(ccCurrentIs(d.scope))"
                created = placement == "explicit-owner"
                    ? ccWithCurrent(d, owner) { ccRawInput(d, 10) }
                    : ccRawInput(d, 10)
                log.append("create-input")
            }
            return d.read(x) + d.read(created!)
        }
    }
    _ = sibling
    let base = d.nodeCount
    var values = [ccWithCurrent(d, d.scope) { d.read(creator) }]
    let added = d.nodeCount - base
    let weakCreated = d.weak(created!)
    let steps = ["first:\(log)"]
    log.removeAll()
    d.write(20, to: created!)
    values.append(d.read(creator))
    let rerun = log
    d.invalidate(owner)
    let freedWithOwner = d.attribute(of: weakCreated) == nil
    ccDiagnostic("cc-create-placement-\(placement)|native Subgraph.current during run: \(currentDuringRun)")
    ccEmit("cc-create-placement-\(placement)|values=\(values)|nodesAdded=\(added)|\(steps.joined(separator: "|"))|writeCreated:\(rerun)|createdFreedWithOwner=\(freedWithOwner)")
}

// MARK: - 2. Values that contain closures

/// A value holding a closure and a tag; not `Equatable`.
struct CCClosureBox {
    let tag: Int
    let fn: () -> Int
}

/// The same shape, `Equatable` by `tag` only (the closure is ignored).
struct CCEquatableClosureBox: Equatable {
    let tag: Int
    let fn: () -> Int
    static func == (lhs: CCEquatableClosureBox, rhs: CCEquatableClosureBox) -> Bool { lhs.tag == rhs.tag }
}

/// Mutable state captured by a reused closure.
final class CCCapturedState {
    var value: Int
    init(_ value: Int) { self.value = value }
}

/// A producer rule returns a box built from a closure; a stateful reader records, on each run, whether the producer's
/// value counted as changed (`changedValue(of:).changed`) and the closure's result. The producer is forced to run by an
/// input it reads (`tick`) without using it in the box. `kind`:
/// - `recreated`: a new closure capturing a constant on every run.
/// - `stable`: the same closure object on every run.
/// - `captured-state`: the same closure object, capturing a reference whose state changes between runs.
/// - `thin`: a closure with no captures.
func ccClosureCut(kind: String, equatable: Bool) {
    let d = Driver()
    defer { d.close() }
    let tick = d.input(0)
    var producerRuns = 0
    let constant = 7
    let state = CCCapturedState(1)
    let stableFn: () -> Int = { constant }
    let capturedFn: () -> Int = { state.value }
    func makeFn() -> () -> Int {
        switch kind {
        case "recreated": return { constant }
        case "stable": return stableFn
        case "captured-state": return capturedFn
        default: return { 7 }
        }
    }
    var readerRuns: [String] = []
    let name = "cc-closure-\(kind)-\(equatable ? "equatable" : "plain")"
    if equatable {
        let producer = d.rule { () -> CCEquatableClosureBox in
            producerRuns += 1
            _ = d.read(tick)
            return CCEquatableClosureBox(tag: 1, fn: makeFn())
        }
        let reader = d.statefulRule(initialValue: 0) { (ctx: StatefulHandleContext<Int>) in
            let (box, changed) = ctx.changedValue(of: producer)
            readerRuns.append("changed=\(changed),fn=\(box.fn())")
            ctx.value = box.fn()
        }
        _ = d.read(reader)
        for t in 1...2 {
            state.value += 10
            d.write(t, to: tick)
            _ = d.read(reader)
        }
        ccDiagnostic("\(name)|native comparisonMode=\(ccComparisonMode(CCEquatableClosureBox.self))")
    } else {
        let producer = d.rule { () -> CCClosureBox in
            producerRuns += 1
            _ = d.read(tick)
            return CCClosureBox(tag: 1, fn: makeFn())
        }
        let reader = d.statefulRule(initialValue: 0) { (ctx: StatefulHandleContext<Int>) in
            let (box, changed) = ctx.changedValue(of: producer)
            readerRuns.append("changed=\(changed),fn=\(box.fn())")
            ctx.value = box.fn()
        }
        _ = d.read(reader)
        for t in 1...2 {
            state.value += 10
            d.write(t, to: tick)
            _ = d.read(reader)
        }
        ccDiagnostic("\(name)|native comparisonMode=\(ccComparisonMode(CCClosureBox.self))")
    }
    ccEmit("\(name)|producerRuns=\(producerRuns)|readerRuns=\(readerRuns)")
}

/// The `Equatable` box with a recreated closure over many evaluations, with pauses: records, per evaluation, whether
/// the new value counted as changed, to see whether native comparison switches from bytes to `==` after a while.
func ccClosureEquatableManyEvaluations() {
    let d = Driver()
    defer { d.close() }
    let tick = d.input(0)
    let constant = 7
    let producer = d.rule { () -> CCEquatableClosureBox in
        _ = d.read(tick)
        return CCEquatableClosureBox(tag: 1, fn: { constant })
    }
    var changes: [Int] = []
    let reader = d.statefulRule(initialValue: 0) { (ctx: StatefulHandleContext<Int>) in
        let (box, changed) = ctx.changedValue(of: producer)
        changes.append(changed ? 1 : 0)
        ctx.value = box.fn()
    }
    _ = d.read(reader)
    for t in 1...30 {
        usleep(2_000)
        d.write(t, to: tick)
        _ = d.read(reader)
    }
    ccEmit("cc-closure-recreated-equatable-many|readerRuns=\(changes.count)|changedPerRun=\(changes.map(String.init).joined())")
}

/// A producer returns a `Double` from an input that is written with `0.0 → -0.0 → -0.0` and `NaN → NaN` (the same bit
/// pattern); the stateful reader records whether each new value counted as changed.
func ccDoubleCut() {
    let d = Driver()
    defer { d.close() }
    let source = d.input(0.0)
    var producerRuns = 0
    let producer = d.rule { () -> Double in producerRuns += 1; return d.read(source) }
    var readerRuns: [String] = []
    let reader = d.statefulRule(initialValue: 0.0) { (ctx: StatefulHandleContext<Double>) in
        let (value, changed) = ctx.changedValue(of: producer)
        readerRuns.append("changed=\(changed),sign=\(value.sign == .minus ? "-" : "+"),nan=\(value.isNaN)")
        ctx.value = value
    }
    _ = d.read(reader)
    var steps: [String] = []
    for (label, next) in [("0.0->-0.0", -0.0), ("-0.0->-0.0", -0.0), ("->NaN", Double.nan), ("NaN->NaN", Double.nan)] {
        readerRuns.removeAll()
        let before = producerRuns
        d.write(next, to: source)
        _ = d.read(reader)
        steps.append("\(label):producerRan=\(producerRuns - before),reader=\(readerRuns)")
    }
    ccDiagnostic("cc-double-cut|native comparisonMode=\(ccComparisonMode(Double.self))")
    ccEmit("cc-double-cut|\(steps.joined(separator: "|"))")
}

// MARK: - 1b. Creation and the caller's subgraph lifetime

/// The creator rule `r` (owned by `owner`) creates an input (`kind` = `input`) or a rule reading scope input `y`
/// (`kind` = `rule`) on its first run. An outer rule (owned by the scope) is read with the caller subgraph `caller` as
/// current. With `fallingCaller`, the outer rule invalidates `caller` (deferred: it is still alive during the update)
/// before reading `r`, so the creation happens while the caller subgraph is being invalidated. Otherwise `caller` is
/// invalidated after the update. Records whether the created attribute survives each step, the values and the order.
func ccCallerLifetime(kind: String, fallingCaller: Bool) {
    let d = Driver()
    defer { d.close() }
    var log: [String] = []
    let y = d.input(5)
    let caller = d.makeSubgraph()
    let owner = d.makeSubgraph()
    var created: Handle<Int>? = nil
    var callerValidAtCreation = "-"
    let r = d.withSubgraph(owner) {
        d.rule { () -> Int in
            log.append("r")
            if created == nil {
                callerValidAtCreation = "\(d.isValid(caller))"
                if kind == "input" {
                    created = ccRawInput(d, 10)
                    log.append("create-input")
                } else {
                    created = ccRawRule(d) { () -> Int in log.append("created"); return d.read(y) * 10 }
                    log.append("create-rule")
                }
            }
            return d.read(created!) + 1
        }
    }
    var invalidateArmed = fallingCaller
    let outer = d.rule { () -> Int in
        log.append("outer")
        // Only on the first run: invalidating an already invalidated subgraph is accepted natively but traps in the
        // local engine, which would hide the rest of the trace (see `cc-invalidate-twice`).
        if invalidateArmed {
            invalidateArmed = false
            d.invalidate(caller)
            log.append("invalidate-caller")
        }
        return d.read(r) + 100
    }
    let v1 = ccWithCurrent(d, caller) { d.read(outer) }
    let weakCreated = d.weak(created!)
    let aliveAfterUpdate = d.attribute(of: weakCreated) != nil
    let callerValidAfterUpdate = d.isValid(caller)
    var steps = ["first(v=\(v1)):\(log)", "callerValidAtCreation=\(callerValidAtCreation)",
                 "aliveAfterUpdate=\(aliveAfterUpdate)", "callerValidAfterUpdate=\(callerValidAfterUpdate)"]
    if aliveAfterUpdate && kind == "rule" {
        log.removeAll()
        d.write(6, to: y)
        let v2 = d.read(outer)
        steps.append("writeY(v=\(v2)):\(log)")
    }
    if !fallingCaller {
        d.invalidate(caller)
        steps.append("aliveAfterCallerInvalidated=\(d.attribute(of: weakCreated) != nil)")
        log.removeAll()
        let v3 = d.read(outer)
        steps.append("readAfterCallerInvalidated(v=\(v3)):\(log)")
    }
    d.invalidate(owner)
    steps.append("aliveAfterOwnerInvalidated=\(d.attribute(of: weakCreated) != nil)")
    ccEmit("cc-caller-\(fallingCaller ? "falling" : "invalidated-after")-\(kind)|\(steps.joined(separator: "|"))")
}

/// Invalidating a subgraph twice: first from outside an update, then again after it was freed.
func ccInvalidateTwice() {
    let d = Driver()
    defer { d.close() }
    let child = d.makeSubgraph()
    _ = d.withSubgraph(child) { d.input(1) }
    d.invalidate(child)
    ccEmit("cc-invalidate-twice|afterFirst:valid=\(d.isValid(child))")
    d.invalidate(child)
    ccEmit("cc-invalidate-twice|afterSecond:valid=\(d.isValid(child))")
}

/// Every scenario of this file, by name.
let ccScenarios: [(String, @Sendable () -> Void)] = [
    ("invalidate-twice", { ccInvalidateTwice() }),
    ("caller-invalidated-after-input", { ccCallerLifetime(kind: "input", fallingCaller: false) }),
    ("caller-invalidated-after-rule", { ccCallerLifetime(kind: "rule", fallingCaller: false) }),
    ("caller-falling-input", { ccCallerLifetime(kind: "input", fallingCaller: true) }),
    ("caller-falling-rule", { ccCallerLifetime(kind: "rule", fallingCaller: true) }),
    ("create-input-in-rule", { ccCreateInputInRule() }),
    ("create-rule-in-rule", { ccCreateRuleInRule() }),
    ("create-rule-every-run", { ccCreateRuleEveryRun() }),
    ("create-rule-during-update-flags", { ccCreateRuleDuringUpdateFlags() }),
    ("create-input-in-rule-scoped", { ccScopedReads = true; ccCreateInputInRule() }),
    ("create-rule-in-rule-scoped", { ccScopedReads = true; ccCreateRuleInRule() }),
    ("create-rule-every-run-scoped", { ccScopedReads = true; ccCreateRuleEveryRun() }),
    ("create-rule-during-update-flags-scoped", { ccScopedReads = true; ccCreateRuleDuringUpdateFlags() }),
    ("create-placement-caller-scope", { ccCreatePlacement(placement: "caller-scope") }),
    ("create-placement-explicit-owner", { ccCreatePlacement(placement: "explicit-owner") }),
    ("closure-recreated-equatable-many", { ccClosureEquatableManyEvaluations() }),
    ("closure-recreated-plain", { ccClosureCut(kind: "recreated", equatable: false) }),
    ("closure-stable-plain", { ccClosureCut(kind: "stable", equatable: false) }),
    ("closure-captured-state-plain", { ccClosureCut(kind: "captured-state", equatable: false) }),
    ("closure-thin-plain", { ccClosureCut(kind: "thin", equatable: false) }),
    ("closure-recreated-equatable", { ccClosureCut(kind: "recreated", equatable: true) }),
    ("closure-stable-equatable", { ccClosureCut(kind: "stable", equatable: true) }),
    ("closure-captured-state-equatable", { ccClosureCut(kind: "captured-state", equatable: true) }),
    ("double-cut", { ccDoubleCut() }),
]

/// When launched as `Probe cc <name|a,b,...|all>`, runs those scenarios in order in one process and exits.
func runCreateAndClosureScenariosIfRequested() {
    let arguments = CommandLine.arguments
    guard arguments.count > 2, arguments[1] == "cc" else { return }
    let names = arguments[2].split(separator: ",").map(String.init)
    let selected = arguments[2] == "all" ? ccScenarios : names.compactMap { n in ccScenarios.first { $0.0 == n } }
    if selected.count != (arguments[2] == "all" ? ccScenarios.count : names.count) {
        ccEmit("unknown-cc-scenario|\(arguments[2])")
        exit(2)
    }
    for (_, run) in selected { run() }
    exit(0)
}
