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

// Characterization of `Subgraph.isDirty(flags:)`: after each operation, records `isDirty` for every probed flag and
// subgraph, plus which rules ran, so the trace shows when the answer becomes true and which operation clears it. It
// asserts nothing about the expected result. Run with `Probe isdirty <scenario|all>` (one process per scenario).

/// Accumulates `step:flags` entries and rule executions for one scenario.
final class IsDirtyTrace {
    let d: Driver
    var steps: [String] = []
    var runs: [String] = []
    init(_ d: Driver) { self.d = d }

    /// Records `isDirty` of each `(label, subgraph, flags)` probe after the operation named `step`, and the rules that
    /// ran since the previous step.
    func record(_ step: String, _ probes: [(String, SubgraphHandle, UInt8)]) {
        let states = probes.map { "\($0.0)=\(d.isDirty($0.1, flags: $0.2) ? 1 : 0)" }.joined(separator: ",")
        let ran = runs.isEmpty ? "" : ";ran=\(runs.joined(separator: "+"))"
        steps.append("\(step):\(states)\(ran)")
        runs.removeAll()
    }

    func line(_ name: String) -> String { "is-dirty-\(name)|\(steps.joined(separator: "|"))" }
}

/// Write, plain read, second write, partial and full `update(flags:)`.
func isDirtyWriteThenRead() {
    let d = Driver()
    defer { d.close() }
    let t = IsDirtyTrace(d)
    let x = d.input(1)
    let r = d.rule { () -> Int in t.runs.append("r"); return d.read(x) }
    d.setFlags(1, for: r)
    let probes: [(String, SubgraphHandle, UInt8)] = [("f1", d.scope, 1)]
    t.record("created", probes)
    _ = d.read(r)
    t.record("read", probes)
    d.update(d.scope, flags: 1)
    t.record("updateFlags1", probes)
    d.write(2, to: x)
    t.record("write", probes)
    _ = d.read(r)
    t.record("read", probes)
    _ = d.read(r)
    t.record("readAgain", probes)
    d.write(3, to: x)
    t.record("write", probes)
    d.update(d.scope, flags: 1)
    t.record("updateFlags1WhileDirty", probes)
    _ = d.read(r)
    t.record("read", probes)
    print(t.line("write-then-read"))
}

/// `invalidateValue` on a clean rule, then a read, then `update(flags:)`.
func isDirtyInvalidateValueThenRead() {
    let d = Driver()
    defer { d.close() }
    let t = IsDirtyTrace(d)
    let x = d.input(1)
    let r = d.rule { () -> Int in t.runs.append("r"); return d.read(x) }
    let reader = d.rule { () -> Int in t.runs.append("reader"); return d.read(r) + 1 }
    d.setFlags(1, for: r)
    d.setFlags(2, for: reader)
    let probes: [(String, SubgraphHandle, UInt8)] = [("f1", d.scope, 1), ("f2", d.scope, 2)]
    _ = d.read(reader)
    d.update(d.scope, flags: 3)
    t.record("cleared", probes)
    d.invalidateValue(of: r)
    t.record("invalidateValue", probes)
    _ = d.read(reader)
    t.record("readReader", probes)
    d.update(d.scope, flags: 3)
    t.record("updateFlags3", probes)
    d.invalidateValue(of: r)
    t.record("invalidateValue", probes)
    d.update(d.scope, flags: 1)
    t.record("updateFlags1", probes)
    print(t.line("invalidate-value-then-read"))
}

/// A dirty rule that recomputes the same value, then a different one; its reader carries another flag.
func isDirtySameAndDifferentValue() {
    let d = Driver()
    defer { d.close() }
    let t = IsDirtyTrace(d)
    let x = d.input(1)
    let parity = d.rule { () -> Int in t.runs.append("parity"); return d.read(x) % 2 }
    let reader = d.rule { () -> Int in t.runs.append("reader"); return d.read(parity) * 10 }
    d.setFlags(1, for: parity)
    d.setFlags(2, for: reader)
    let probes: [(String, SubgraphHandle, UInt8)] = [("f1", d.scope, 1), ("f2", d.scope, 2)]
    _ = d.read(reader)
    d.update(d.scope, flags: 3)
    t.record("cleared", probes)
    d.write(3, to: x)
    t.record("writeSameParity", probes)
    _ = d.read(reader)
    t.record("readReader", probes)
    d.update(d.scope, flags: 3)
    t.record("updateFlags3", probes)
    d.write(4, to: x)
    t.record("writeOtherParity", probes)
    _ = d.read(reader)
    t.record("readReader", probes)
    d.update(d.scope, flags: 3)
    t.record("updateFlags3", probes)
    print(t.line("same-and-different-value"))
}

/// Two dirty rules with different flags: partial `update(flags:)` with one flag, then the full one.
func isDirtyPartialAndFullUpdate() {
    let d = Driver()
    defer { d.close() }
    let t = IsDirtyTrace(d)
    let x = d.input(1)
    let a = d.rule { () -> Int in t.runs.append("a"); return d.read(x) + 1 }
    let b = d.rule { () -> Int in t.runs.append("b"); return d.read(x) + 2 }
    d.setFlags(1, for: a)
    d.setFlags(2, for: b)
    let probes: [(String, SubgraphHandle, UInt8)] = [("f1", d.scope, 1), ("f2", d.scope, 2), ("f3", d.scope, 3)]
    _ = d.read(a)
    _ = d.read(b)
    d.update(d.scope, flags: 3)
    t.record("cleared", probes)
    d.write(5, to: x)
    t.record("write", probes)
    d.update(d.scope, flags: 1)
    t.record("updateFlags1", probes)
    d.update(d.scope, flags: 2)
    t.record("updateFlags2", probes)
    d.write(6, to: x)
    t.record("write", probes)
    d.update(d.scope, flags: 3)
    t.record("updateFlags3", probes)
    print(t.line("partial-and-full-update"))
}

/// Flags changed while the attribute is dirty, and set to zero.
func isDirtyFlagsChangedWhileDirty() {
    let d = Driver()
    defer { d.close() }
    let t = IsDirtyTrace(d)
    let x = d.input(1)
    let r = d.rule { () -> Int in t.runs.append("r"); return d.read(x) }
    d.setFlags(1, for: r)
    let probes: [(String, SubgraphHandle, UInt8)] = [("f1", d.scope, 1), ("f2", d.scope, 2)]
    _ = d.read(r)
    d.update(d.scope, flags: 3)
    t.record("cleared", probes)
    d.write(2, to: x)
    t.record("writeWithFlag1", probes)
    d.setFlags(2, for: r)
    t.record("setFlags2WhileDirty", probes)
    d.update(d.scope, flags: 1)
    t.record("updateFlags1", probes)
    d.update(d.scope, flags: 2)
    t.record("updateFlags2", probes)
    d.write(3, to: x)
    t.record("writeWithFlag2", probes)
    d.setFlags(0, for: r)
    t.record("setFlags0WhileDirty", probes)
    _ = d.read(r)
    t.record("read", probes)
    d.update(d.scope, flags: 3)
    t.record("updateFlags3", probes)
    print(t.line("flags-changed-while-dirty"))
}

/// A flagged rule in a child subgraph reading an input of the parent: `isDirty` and `update(flags:)` on the parent and
/// on the child.
func isDirtyDescendantSubgraph() {
    let d = Driver()
    defer { d.close() }
    let t = IsDirtyTrace(d)
    let x = d.input(1)
    let child = d.makeSubgraph()
    let rc = d.withSubgraph(child) { d.rule { () -> Int in t.runs.append("rc"); return d.read(x) } }
    d.setFlags(1, for: rc)
    let probes: [(String, SubgraphHandle, UInt8)] = [("parent", d.scope, 1), ("child", child, 1)]
    t.record("created", probes)
    _ = d.read(rc)
    t.record("read", probes)
    d.update(d.scope, flags: 1)
    t.record("updateParent", probes)
    d.write(2, to: x)
    t.record("write", probes)
    _ = d.read(rc)
    t.record("read", probes)
    d.update(child, flags: 1)
    t.record("updateChild", probes)
    d.update(d.scope, flags: 1)
    t.record("updateParent", probes)
    d.write(3, to: x)
    t.record("write", probes)
    d.update(child, flags: 1)
    t.record("updateChildWhileDirty", probes)
    print(t.line("descendant-subgraph"))
}

/// A typed rule whose body can be mutated: `source + offset`, logging its runs under `name`.
private struct IsDirtyOffsetRule: Rule {
    var source: Handle<Int>
    var offset: Int
    let name: String
    let trace: IsDirtyTrace
    var value: Int {
        trace.runs.append(name)
        return source.value + offset
    }
}

/// Attributes dirtied while `update(flags:)` runs: rule `a` (flag 1) mutates, invalidating, the bodies of `b` (flag 1)
/// and `c` (flag 2), which do not depend on the written input. `bFirst` creates `b` before `a`, so the reverse-creation
/// walk of `update(flags:)` visits `a` first; otherwise `b` is visited (clean) before `a` dirties it.
func isDirtyDirtiedDuringUpdate(bFirst: Bool) {
    let d = Driver()
    defer { d.close() }
    let t = IsDirtyTrace(d)
    let x = d.input(1)
    let y = d.input(100)
    var armed = false
    var b: Handle<Int>? = nil
    var c: Handle<Int>? = nil
    if bFirst { b = d.typedRule(IsDirtyOffsetRule(source: y, offset: 0, name: "b", trace: t)) }
    let a = d.rule { () -> Int in
        t.runs.append("a")
        let v = d.read(x)
        if armed {
            armed = false
            d.mutateBody(of: b!, as: IsDirtyOffsetRule.self, invalidating: true) { $0.offset = 10 }
            d.mutateBody(of: c!, as: IsDirtyOffsetRule.self, invalidating: true) { $0.offset = 20 }
        }
        return v
    }
    if !bFirst { b = d.typedRule(IsDirtyOffsetRule(source: y, offset: 0, name: "b", trace: t)) }
    c = d.typedRule(IsDirtyOffsetRule(source: y, offset: 0, name: "c", trace: t))
    d.setFlags(1, for: a)
    d.setFlags(1, for: b!)
    d.setFlags(2, for: c!)
    let probes: [(String, SubgraphHandle, UInt8)] = [("f1", d.scope, 1), ("f2", d.scope, 2)]
    _ = d.read(a)
    _ = d.read(b!)
    _ = d.read(c!)
    d.update(d.scope, flags: 3)
    t.record("cleared", probes)
    d.write(2, to: x)
    armed = true
    t.record("write", probes)
    d.update(d.scope, flags: 1)
    t.record("updateFlags1", probes)
    d.update(d.scope, flags: 1)
    t.record("updateFlags1Again", probes)
    let bValue = d.read(b!)
    let cValue = d.read(c!)
    t.record("readBC(b=\(bValue),c=\(cValue))", probes)
    d.update(d.scope, flags: 3)
    t.record("updateFlags3", probes)
    print(t.line("dirtied-during-update-\(bFirst ? "b-first" : "b-last")"))
}

/// A child subgraph with a pending mark is invalidated; the parent also owns a dirty flagged rule (flag 4) and a second
/// child keeps a clean rule (flag 2).
func isDirtyInvalidatedSubgraphWithMarks() {
    let d = Driver()
    defer { d.close() }
    let t = IsDirtyTrace(d)
    let x = d.input(1)
    let doomed = d.makeSubgraph()
    let kept = d.makeSubgraph()
    let rd = d.withSubgraph(doomed) { d.rule { () -> Int in t.runs.append("rd"); return d.read(x) } }
    let rk = d.withSubgraph(kept) { d.rule { () -> Int in t.runs.append("rk"); return 7 } }
    let rp = d.rule { () -> Int in t.runs.append("rp"); return d.read(x) * 2 }
    d.setFlags(1, for: rd)
    d.setFlags(2, for: rk)
    d.setFlags(4, for: rp)
    let probes: [(String, SubgraphHandle, UInt8)] = [("p1", d.scope, 1), ("p2", d.scope, 2), ("p4", d.scope, 4),
                                                     ("k2", kept, 2)]
    _ = d.read(rd)
    _ = d.read(rk)
    _ = d.read(rp)
    d.update(d.scope, flags: 7)
    t.record("cleared", probes)
    d.write(2, to: x)
    t.record("write", probes)
    d.invalidate(doomed)
    t.record("invalidateChild", probes)
    d.update(d.scope, flags: 1)
    t.record("updateFlags1", probes)
    d.update(d.scope, flags: 4)
    t.record("updateFlags4", probes)
    print(t.line("invalidated-subgraph-with-marks"))
}

/// Flags set on a dirty rule that never ran, then on a clean one, then after a read.
func isDirtyFlagsBeforeAndAfterRead() {
    let d = Driver()
    defer { d.close() }
    let t = IsDirtyTrace(d)
    let x = d.input(1)
    let r = d.rule { () -> Int in t.runs.append("r"); return d.read(x) }
    let probes: [(String, SubgraphHandle, UInt8)] = [("f1", d.scope, 1), ("f2", d.scope, 2), ("f4", d.scope, 4)]
    // In native AttributeGraph a new graph's subgraph can start with marks left by an earlier graph of the same
    // process (observed after `write-then-read` and `invalidated-subgraph-with-marks`); clear them first so the trace
    // does not depend on what ran before. `r` has no flags yet, so nothing is evaluated.
    d.update(d.scope, flags: 0xFF)
    t.record("createdNoFlags", probes)
    d.setFlags(1, for: r)
    t.record("setFlags1BeforeFirstRead", probes)
    _ = d.read(r)
    t.record("read", probes)
    d.update(d.scope, flags: 7)
    t.record("updateFlags7", probes)
    d.setFlags(2, for: r)
    t.record("setFlags2WhileClean", probes)
    d.write(2, to: x)
    t.record("write", probes)
    _ = d.read(r)
    t.record("read", probes)
    d.setFlags(4, for: r)
    t.record("setFlags4AfterRead", probes)
    d.update(d.scope, flags: 7)
    t.record("updateFlags7", probes)
    print(t.line("flags-before-and-after-read"))
}

/// Two children and a grandchild, each with a dirty flag-1 rule: `update(flags:)` on the grandchild, each child and the
/// parent, in that order.
func isDirtyChildVersusParentUpdate() {
    let d = Driver()
    defer { d.close() }
    let t = IsDirtyTrace(d)
    let x = d.input(1)
    let c1 = d.makeSubgraph()
    let c2 = d.makeSubgraph()
    let g = d.withSubgraph(c1) { d.makeSubgraph() }
    let r1 = d.withSubgraph(c1) { d.rule { () -> Int in t.runs.append("r1"); return d.read(x) } }
    let r2 = d.withSubgraph(c2) { d.rule { () -> Int in t.runs.append("r2"); return d.read(x) } }
    let rg = d.withSubgraph(g) { d.rule { () -> Int in t.runs.append("rg"); return d.read(x) } }
    for rule in [r1, r2, rg] { d.setFlags(1, for: rule) }
    let probes: [(String, SubgraphHandle, UInt8)] = [("parent", d.scope, 1), ("c1", c1, 1), ("c2", c2, 1),
                                                     ("g", g, 1)]
    _ = d.read(r1)
    _ = d.read(r2)
    _ = d.read(rg)
    d.update(d.scope, flags: 1)
    t.record("cleared", probes)
    d.write(2, to: x)
    t.record("write", probes)
    d.update(g, flags: 1)
    t.record("updateGrandchild", probes)
    d.update(c1, flags: 1)
    t.record("updateC1", probes)
    d.update(c2, flags: 1)
    t.record("updateC2", probes)
    d.update(d.scope, flags: 1)
    t.record("updateParent", probes)
    d.write(3, to: x)
    t.record("write", probes)
    d.update(d.scope, flags: 1)
    t.record("updateParent", probes)
    print(t.line("child-versus-parent-update"))
}

/// Every `isDirty(flags:)` characterization scenario, by name.
let isDirtyScenarios: [(String, @Sendable () -> Void)] = [
    ("dirtied-during-update-b-first", { isDirtyDirtiedDuringUpdate(bFirst: true) }),
    ("dirtied-during-update-b-last", { isDirtyDirtiedDuringUpdate(bFirst: false) }),
    ("invalidated-subgraph-with-marks", { isDirtyInvalidatedSubgraphWithMarks() }),
    ("flags-before-and-after-read", { isDirtyFlagsBeforeAndAfterRead() }),
    ("child-versus-parent-update", { isDirtyChildVersusParentUpdate() }),
    ("write-then-read", { isDirtyWriteThenRead() }),
    ("invalidate-value-then-read", { isDirtyInvalidateValueThenRead() }),
    ("same-and-different-value", { isDirtySameAndDifferentValue() }),
    ("partial-and-full-update", { isDirtyPartialAndFullUpdate() }),
    ("flags-changed-while-dirty", { isDirtyFlagsChangedWhileDirty() }),
    ("descendant-subgraph", { isDirtyDescendantSubgraph() }),
]

/// When launched as `Probe isdirty <name|all|name,name,...>`, runs those `isDirty(flags:)` scenarios in the given
/// order in one process (to observe state carried between graphs of the same process) and exits.
func runIsDirtyScenariosIfRequested() {
    let arguments = CommandLine.arguments
    guard arguments.count > 2, arguments[1] == "isdirty" else { return }
    let names = arguments[2].split(separator: ",").map(String.init)
    let selected = arguments[2] == "all"
        ? isDirtyScenarios
        : names.compactMap { name in isDirtyScenarios.first { $0.0 == name } }
    if selected.count != (arguments[2] == "all" ? isDirtyScenarios.count : names.count) {
        print("unknown-isdirty-scenario|\(arguments[2])")
        exit(2)
    }
    if selected.isEmpty {
        print("unknown-isdirty-scenario|\(arguments[2])")
        exit(2)
    }
    for (_, run) in selected { run() }
    exit(0)
}
