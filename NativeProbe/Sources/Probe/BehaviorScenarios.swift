func statefulNoWriteCut() {
    let d = Driver()
    defer { d.close() }
    let input = d.input(10)
    var statefulRuns = 0
    var outputRuns = 0
    let stateful = d.statefulRule { (ctx: StatefulHandleContext<Int>) in
        statefulRuns += 1
        let v = d.read(input)
        if !ctx.hasValue || v > 20 {
            ctx.value = v
        }
    }
    let output = d.rule {
        outputRuns += 1
        return d.read(stateful) * 2
    }
    var values = [d.read(output)]
    var sRuns = [statefulRuns], oRuns = [outputRuns]
    for next in [15, 25, 18] {
        d.write(next, to: input)
        values.append(d.read(output))
        sRuns.append(statefulRuns)
        oRuns.append(outputRuns)
    }
    precondition(values == [20, 20, 50, 50])
    precondition(sRuns == [1, 2, 3, 4] && oRuns == [1, 1, 2, 2])
    print("stateful-no-write-cut|values=\(values)|statefulRuns=\(sRuns)|outputRuns=\(oRuns)")
}

func statefulUnreadInput() {
    let d = Driver()
    defer { d.close() }
    let selector = d.input(true)
    let a = d.input(1)
    let b = d.input(100)
    var runs = 0
    let stateful = d.statefulRule { (ctx: StatefulHandleContext<Int>) in
        runs += 1
        ctx.value = d.read(selector) ? d.read(a) : d.read(b)
    }
    var values = [d.read(stateful)], runHistory = [runs]
    d.write(200, to: b)
    values.append(d.read(stateful)); runHistory.append(runs)
    d.write(false, to: selector)
    values.append(d.read(stateful)); runHistory.append(runs)
    d.write(2, to: a)
    values.append(d.read(stateful)); runHistory.append(runs)
    precondition(values == [1, 1, 200, 200])
    precondition(runHistory == [1, 1, 2, 2])
    print("stateful-unread-input|values=\(values)|runs=\(runHistory)")
}

func statefulHasValueAndRevert() {
    let d = Driver()
    defer { d.close() }
    let input = d.input(5)
    var runs = 0
    var seenHasValue: [Bool] = []
    var seenPrev: [Int] = []
    var seenChanged: [Bool] = []
    let stateful = d.statefulRule { (ctx: StatefulHandleContext<Int>) in
        runs += 1
        seenHasValue.append(ctx.hasValue)
        if ctx.hasValue { seenPrev.append(ctx.value) }
        let cv = ctx.changedValue(of: input)
        seenChanged.append(cv.changed)
        ctx.value = cv.value * 10
    }
    let v1 = d.read(stateful)
    d.write(6, to: input)
    d.write(5, to: input)
    let v2 = d.read(stateful)
    precondition(v1 == 50 && v2 == 50 && runs == 2)
    precondition(seenHasValue == [false, true] && seenPrev == [50] && seenChanged == [true, true])
    print("stateful-has-value-and-revert|runs=\(runs)|hasValue=\(seenHasValue)|prev=\(seenPrev)|changed=\(seenChanged)")
}

func selectorInputOrder() {
    let d = Driver()
    defer { d.close() }
    let raw = d.input(1)
    let flag = d.input(true)
    var aRuns = 0, bRuns = 0, cRuns = 0
    let a = d.rule { aRuns += 1; return d.read(raw) % 2 }
    let b = d.rule { bRuns += 1; return d.read(raw) + 10 }
    let c = d.rule {
        cRuns += 1
        if d.read(flag) {
            return d.read(a) + d.read(b)
        } else {
            return d.read(b) + d.read(a)
        }
    }
    let v1 = d.read(c)
    d.write(3, to: raw)
    let v2 = d.read(c)
    let counts1 = [aRuns, bRuns, cRuns]

    let raw2 = d.input(1)
    let flag2 = d.input(false)
    var a2Runs = 0, b2Runs = 0, c2Runs = 0
    let a2 = d.rule { a2Runs += 1; return d.read(raw2) % 2 }
    let b2 = d.rule { b2Runs += 1; return d.read(raw2) + 10 }
    let c2 = d.rule {
        c2Runs += 1
        if d.read(flag2) {
            return d.read(a2) + d.read(b2)
        } else {
            return d.read(b2) + d.read(a2)
        }
    }
    let u1 = d.read(c2)
    d.write(3, to: raw2)
    let u2 = d.read(c2)
    let counts2 = [a2Runs, b2Runs, c2Runs]

    precondition(v1 == 12 && v2 == 14 && u1 == 12 && u2 == 14)
    precondition(counts1 == [2, 2, 2] && counts2 == [2, 2, 2])
    print("selector-input-order|ab=\(counts1)|ba=\(counts2)")
}

func invalidateInRule() {
    let d = Driver()
    defer { d.close() }
    let child = d.makeSubgraph()
    let childInput = d.withSubgraph(child) { d.input(42) }
    let weakChild = d.weak(childInput)
    let trigger = d.input(false)
    var validDuringInvalidate = true
    var weakDuringInvalidate: Int? = nil
    let rule = d.rule { () -> Int in
        if d.read(trigger) {
            d.invalidate(child)
            validDuringInvalidate = d.isValid(child)
            weakDuringInvalidate = d.readWeak(weakChild)
            return d.read(childInput) + 1
        }
        return d.read(childInput)
    }
    let v1 = d.read(rule)
    let validBefore = d.isValid(child)
    d.write(true, to: trigger)
    let v2 = d.read(rule)
    let validAfter = d.isValid(child)
    precondition(v1 == 42 && validBefore && v2 == 43)
    precondition(!validDuringInvalidate && weakDuringInvalidate == 42)
    precondition(!validAfter)
    print("invalidate-in-rule|v1=\(v1)|v2=\(v2)|validDuring=\(validDuringInvalidate)|weakDuring=\(String(describing: weakDuringInvalidate))|validAfter=\(validAfter)")
}

func weakAttributeInRule() {
    let d = Driver()
    defer { d.close() }
    let child = d.makeSubgraph()
    let childInput = d.withSubgraph(child) { d.input(10) }
    let weakRef = d.weak(childInput)
    let tick = d.input(0)
    var ruleRuns = 0
    var statefulRuns = 0
    let reader = d.rule { () -> Int in
        ruleRuns += 1
        _ = d.read(tick)
        return d.readWeak(weakRef) ?? -1
    }
    let statefulReader = d.statefulRule { (ctx: StatefulHandleContext<Int>) in
        statefulRuns += 1
        _ = d.read(tick)
        if let cv = ctx.changedValue(of: weakRef) {
            ctx.value = cv.value + (cv.changed ? 100 : 0)
        } else {
            ctx.value = -999
        }
    }
    var rVals = [d.read(reader)], sVals = [d.read(statefulReader)]
    d.write(20, to: childInput)
    rVals.append(d.read(reader)); sVals.append(d.read(statefulReader))
    d.invalidate(child)
    rVals.append(d.read(reader)); sVals.append(d.read(statefulReader))
    let runsBeforeTick = [ruleRuns, statefulRuns]
    d.write(1, to: tick)
    rVals.append(d.read(reader)); sVals.append(d.read(statefulReader))
    let runsAfterTick = [ruleRuns, statefulRuns]
    precondition(rVals == [10, 20, 20, -1] && sVals == [110, 120, 120, -999])
    precondition(runsBeforeTick == [2, 2] && runsAfterTick == [3, 3])
    print("weak-attribute-in-rule|reader=\(rVals)|stateful=\(sVals)|runsBeforeTick=\(runsBeforeTick)|runsAfterTick=\(runsAfterTick)")
}

func indirectRuleAndRedirect() {
    let d = Driver()
    defer { d.close() }
    let a = d.input(10)
    let b = d.input(10)
    let c = d.input(7)
    let cRule = d.rule { d.read(c) * 3 }
    let ind = d.indirect(a)
    let indAttr = d.attribute(of: ind)
    var runs = 0
    let reader = d.rule {
        runs += 1
        return d.read(indAttr) + 1
    }
    var values = [d.read(reader)], runHistory = [runs]
    d.setSource(a, for: ind)
    values.append(d.read(reader)); runHistory.append(runs)
    d.setSource(b, for: ind)
    values.append(d.read(reader)); runHistory.append(runs)
    d.write(99, to: a)
    values.append(d.read(reader)); runHistory.append(runs)
    d.write(25, to: b)
    values.append(d.read(reader)); runHistory.append(runs)
    d.setSource(cRule, for: ind)
    values.append(d.read(reader)); runHistory.append(runs)
    d.write(8, to: c)
    values.append(d.read(reader)); runHistory.append(runs)
    precondition(d.source(of: ind) == cRule)
    precondition(values == [11, 11, 11, 11, 26, 22, 25])
    precondition(runHistory == [1, 1, 2, 2, 3, 4, 5])
    print("indirect-rule-and-redirect|values=\(values)|runs=\(runHistory)")
}

#if NATIVE_ATTRIBUTE_GRAPH
import AttributeGraph
#else
import SwiftAttributeGraph
#endif

private struct ProbePair {
    var left: Int
    var right: Int
}

private struct WrapperProbeRule: Rule {
    @Attribute var primary: Int
    @WeakAttribute var secondary: Int?
    @OptionalAttribute var overrideValue: Int?

    init(primary: Handle<Int>, secondary: WeakHandle<Int>, overrideValue: OptionalHandle<Int>) {
        self._primary = primary
        self._secondary = secondary
        self._overrideValue = overrideValue
    }

    var value: Int {
        if let overrideValue { return overrideValue }
        return primary + (secondary ?? -10)
    }
}

func focusKeyPathCut() {
    let d = Driver()
    defer { d.close() }
    let root = d.input(ProbePair(left: 2, right: 100))
    let leftAttr = d.focus(root, keyPath: \.left)
    var runs = 0
    let reader = d.rule {
        runs += 1
        return d.read(leftAttr) * 10
    }
    var values = [d.read(reader)], runHistory = [runs]
    d.write(ProbePair(left: 2, right: 200), to: root)
    values.append(d.read(reader)); runHistory.append(runs)
    d.write(ProbePair(left: 5, right: 200), to: root)
    values.append(d.read(reader)); runHistory.append(runs)
    d.write(ProbePair(left: 5, right: 300), to: root)
    values.append(d.read(reader)); runHistory.append(runs)
    precondition(values == [20, 20, 50, 50])
    precondition(runHistory == [1, 1, 2, 2])
    print("focus-keypath-cut|values=\(values)|runs=\(runHistory)")
}

func slotReuseAndInputOrder() {
    let d = Driver()
    defer { d.close() }
    let sub1 = d.makeSubgraph()
    let raw = d.input(1)
    let rFirst = d.withSubgraph(sub1) { d.rule { d.read(raw) + 1 } }
    var secondRuns = 0
    let rSecond = d.rule { secondRuns += 1; return d.read(raw) * 10 }
    _ = d.read(rFirst)
    _ = d.read(rSecond)
    d.invalidate(sub1)

    let sub2 = d.makeSubgraph()
    var reusedRuns = 0
    let rReused = d.withSubgraph(sub2) { d.rule { reusedRuns += 1; return d.read(raw) + 100 } }
    var joinRuns = 0
    var evalOrder: [String] = []
    let rTrackedSecond = d.rule {
        evalOrder.append("second")
        return d.read(rSecond)
    }
    let rTrackedReused = d.rule {
        evalOrder.append("reused")
        return d.read(rReused)
    }
    let join = d.rule {
        joinRuns += 1
        // Read `rTrackedSecond` first, then `rTrackedReused` (which reused the earlier slot/page).
        return d.read(rTrackedSecond) + d.read(rTrackedReused)
    }
    let v1 = d.read(join)
    evalOrder.removeAll()
    d.write(2, to: raw)
    let v2 = d.read(join)
    precondition(v1 == 111 && v2 == 122 && joinRuns == 2)
    print("slot-reuse-input-order|v1=\(v1)|v2=\(v2)|joinRuns=\(joinRuns)|evalOrder=\(evalOrder)")
}

func duplicateWritesBeforeRead() {
    let d = Driver()
    defer { d.close() }
    let x1 = d.input(1)
    let x2 = d.input(1)
    var runs1 = 0, runs2 = 0
    let r1 = d.rule { runs1 += 1; return d.read(x1) * 3 }
    let r2 = d.rule { runs2 += 1; return d.read(x2) * 3 }
    _ = d.read(r1)
    _ = d.read(r2)
    // Single write on x1 vs duplicate identical writes on x2
    d.write(5, to: x1)
    d.write(5, to: x2)
    d.write(5, to: x2)
    let v1 = d.read(r1), v2 = d.read(r2)
    // Mutate and write twice before reading vs once
    d.write(7, to: x1); d.write(8, to: x1)
    d.write(7, to: x2); d.write(7, to: x2); d.write(8, to: x2); d.write(8, to: x2)
    let u1 = d.read(r1), u2 = d.read(r2)
    precondition(v1 == 15 && v2 == 15 && u1 == 24 && u2 == 24)
    precondition(runs1 == 3 && runs2 == 3)
    print("duplicate-writes-before-read|v=[\(v1), \(v2)]|u=[\(u1), \(u2)]|runs=[\(runs1), \(runs2)]")
}

func doubleReadAndPrune() {
    let d = Driver()
    defer { d.close() }
    let sel = d.input(true)
    let x = d.input(10)
    let y = d.input(100)
    var runs = 0
    let rule = d.rule {
        runs += 1
        if d.read(sel) {
            // Read `x` twice in the same evaluation
            return d.read(x) + d.read(y) + d.read(x)
        } else {
            return d.read(y)
        }
    }
    var values = [d.read(rule)], runHistory = [runs]
    // Mutating `x` once runs `rule` once even though `x` was read twice
    d.write(20, to: x)
    values.append(d.read(rule)); runHistory.append(runs)
    // Switch selector so `x` is no longer read
    d.write(false, to: sel)
    values.append(d.read(rule)); runHistory.append(runs)
    // Mutating `x` now must not run `rule` (both reads of `x` were deduplicated into a single edge and pruned)
    d.write(30, to: x)
    values.append(d.read(rule)); runHistory.append(runs)
    precondition(values == [120, 140, 100, 100])
    precondition(runHistory == [1, 2, 3, 3])
    print("double-read-and-prune|values=\(values)|runs=\(runHistory)")
}

func indirectSourceInvalidated() {
    let d = Driver()
    defer { d.close() }
    let initial = d.input(10)
    let child = d.makeSubgraph()
    let target = d.withSubgraph(child) { d.input(77) }
    let ind = d.indirect(initial)
    let indAttr = d.attribute(of: ind)
    var runs = 0
    let reader = d.rule {
        runs += 1
        return d.read(indAttr) + 1
    }
    let v0 = d.read(reader)
    d.setSource(target, for: ind)
    let v1 = d.read(reader)
    let runs1 = runs
    // Invalidating `child` resets `ind.source` back to `initial` without dirtying `reader`
    d.invalidate(child)
    let resetToInitial = d.source(of: ind) == initial
    let v2 = d.read(reader)
    let runs2 = runs
    // Mutating `initial` propagates through the restored `ind <- initial` edge
    d.write(99, to: initial)
    let v3 = d.read(reader)
    let runs3 = runs
    precondition(v0 == 11 && v1 == 78 && v2 == 78 && v3 == 100 && resetToInitial)
    precondition(runs1 == 2 && runs2 == 2 && runs3 == 3)
    print("indirect-source-invalidated|values=[\(v0), \(v1), \(v2), \(v3)]|runs=[\(runs1), \(runs2), \(runs3)]|resetToInitial=\(resetToInitial)")
}

private struct ProbeRNG {
    var state: UInt64
    mutating func next(_ bound: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 32) % UInt64(bound))
    }
}

private struct ProbeSpec {
    let selector: Int
    let left: Int
    let right: Int
    let bias: Int
}

func randomGraphOracle() {
    let inputCount = 6, ruleCount = 24
    var totalRunsSummary: [Int] = []
    var checksums: [Int] = []
    for seed in 1...6 {
        let d = Driver()
        var rng = ProbeRNG(state: UInt64(seed) &* 104729)
        let totalNodes = inputCount + ruleCount
        var counts = Array(repeating: 0, count: totalNodes)
        var nodes: [Handle<Int>] = []
        for _ in 0..<inputCount {
            let v = rng.next(41) - 20
            nodes.append(d.input(v))
        }
        for k in 0..<ruleCount {
            let index = inputCount + k
            let spec = ProbeSpec(
                selector: rng.next(index),
                left: rng.next(index),
                right: rng.next(index),
                bias: rng.next(11) - 5
            )
            if index % 3 == 0 {
                nodes.append(d.statefulRule { (ctx: StatefulHandleContext<Int>) in
                    counts[index] += 1
                    let sel = d.read(nodes[spec.selector])
                    let picked = sel % 2 == 0 ? d.read(nodes[spec.left]) : d.read(nodes[spec.right])
                    ctx.value = sel &+ picked &+ spec.bias
                })
            } else {
                nodes.append(d.rule {
                    counts[index] += 1
                    let sel = d.read(nodes[spec.selector])
                    let picked = sel % 2 == 0 ? d.read(nodes[spec.left]) : d.read(nodes[spec.right])
                    return sel &+ picked &+ spec.bias
                })
            }
        }
        var checksum = 0
        var stepTraces: [String] = []
        var prevCounts = counts
        for step in 0..<50 {
            if rng.next(4) != 0 {
                let inp = rng.next(inputCount)
                let val = rng.next(15) - 7
                d.write(val, to: nodes[inp])
            }
            let target = inputCount + rng.next(ruleCount)
            let v = d.read(nodes[target])
            var deltas: [String] = []
            for idx in inputCount..<totalNodes {
                let diff = counts[idx] - prevCounts[idx]
                if diff != 0 {
                    deltas.append("\(idx)+\(diff)")
                    prevCounts[idx] = counts[idx]
                }
            }
            stepTraces.append("\(step):\(v){\(deltas.joined(separator: ","))}")
            checksum = (checksum &* 31) &+ v
        }
        totalRunsSummary.append(counts.reduce(0, +))
        checksums.append(checksum)
        print("random-graph-oracle-trace|seed=\(seed)|\(stepTraces.joined(separator: ";"))")
        d.close()
    }
    print("random-graph-oracle|runs=\(totalRunsSummary)|checksums=\(checksums)")
}

private struct ChildSlot {
    let sub: SubgraphHandle
    let input: Handle<Int>
    let rule: Handle<Int>
    let weakRule: WeakHandle<Int>
    var alive: Bool
}

func randomSubgraphWeakIndirectOracle() {
    var totalRunsSummary: [Int] = []
    var checksums: [Int] = []
    for seed in 1...6 {
        let d = Driver()
        var rng = ProbeRNG(state: UInt64(seed) &* 314159)
        var rootCounts = Array(repeating: 0, count: 12)
        var childCounts: [Int] = []
        var rootInputs: [Handle<Int>] = []
        for _ in 0..<4 {
            rootInputs.append(d.input(rng.next(31) - 15))
        }
        let ind0 = d.indirect(rootInputs[0])
        let ind1 = d.indirect(rootInputs[1])
        let ind0Attr = d.attribute(of: ind0)
        let ind1Attr = d.attribute(of: ind1)

        var children: [ChildSlot] = []
        func spawnChild() {
            let childIndex = childCounts.count
            childCounts.append(0)
            let sub = d.makeSubgraph()
            let rIdx = rng.next(rootInputs.count)
            let existingWeak: WeakHandle<Int>? = children.isEmpty ? nil : children[rng.next(children.count)].weakRule
            let initVal = rng.next(21) - 10
            var cInput: Handle<Int>!
            var cRule: Handle<Int>!
            d.withSubgraph(sub) {
                cInput = d.input(initVal)
                cRule = d.rule {
                    childCounts[childIndex] += 1
                    let base = d.read(cInput) &+ d.read(rootInputs[rIdx])
                    let viaWeak = existingWeak.map { d.readWeak($0) ?? -50 } ?? 0
                    return base &+ viaWeak
                }
            }
            children.append(ChildSlot(
                sub: sub,
                input: cInput,
                rule: cRule,
                weakRule: d.weak(cRule),
                alive: true
            ))
        }

        for _ in 0..<3 {
            spawnChild()
        }

        var rootRules: [Handle<Int>] = []
        for k in 0..<12 {
            let selInput = rng.next(rootInputs.count)
            let altInput = rng.next(rootInputs.count)
            let wIdx0 = rng.next(children.count)
            let wIdx1 = rng.next(children.count)
            let w0 = children[wIdx0].weakRule
            let w1 = children[wIdx1].weakRule
            let bias = rng.next(13) - 6
            if k % 3 == 0 {
                rootRules.append(d.statefulRule { (ctx: StatefulHandleContext<Int>) in
                    rootCounts[k] += 1
                    let s = d.read(rootInputs[selInput])
                    let branch = (s & 1) == 0
                        ? (d.read(ind0Attr) &+ (d.readWeak(w0) ?? -100))
                        : (d.read(ind1Attr) &+ (d.readWeak(w1) ?? -200) &+ d.read(rootInputs[altInput]))
                    ctx.value = s &+ branch &+ bias
                })
            } else {
                rootRules.append(d.rule {
                    rootCounts[k] += 1
                    let s = d.read(rootInputs[selInput])
                    let branch = (s & 1) == 0
                        ? (d.read(ind0Attr) &+ (d.readWeak(w0) ?? -100))
                        : (d.read(ind1Attr) &+ (d.readWeak(w1) ?? -200) &+ d.read(rootInputs[altInput]))
                    return s &+ branch &+ bias
                })
            }
        }

        var checksum = 0
        var prevRoot = rootCounts
        var prevChild: [Int] = Array(repeating: 0, count: childCounts.count)
        var stepTraces: [String] = []
        for step in 0..<45 {
            let action = rng.next(6)
            switch action {
            case 0, 1:
                let idx = rng.next(rootInputs.count)
                d.write(rng.next(19) - 9, to: rootInputs[idx])
            case 2:
                let liveIndices = children.indices.filter { children[$0].alive }
                if !liveIndices.isEmpty {
                    let pick = liveIndices[rng.next(liveIndices.count)]
                    d.write(rng.next(19) - 9, to: children[pick].input)
                }
            case 3:
                let targetInd = rng.next(2) == 0 ? ind0 : ind1
                let liveIndices = children.indices.filter { children[$0].alive }
                if !liveIndices.isEmpty && rng.next(2) == 0 {
                    let pick = liveIndices[rng.next(liveIndices.count)]
                    d.setSource(children[pick].rule, for: targetInd)
                } else {
                    let idx = rng.next(rootInputs.count)
                    d.setSource(rootInputs[idx], for: targetInd)
                }
            case 4:
                let liveIndices = children.indices.filter { children[$0].alive }
                if !liveIndices.isEmpty {
                    let pick = liveIndices[rng.next(liveIndices.count)]
                    d.invalidate(children[pick].sub)
                    children[pick].alive = false
                }
            default:
                spawnChild()
                prevChild.append(0)
                if let newest = children.last {
                    let targetInd = rng.next(2) == 0 ? ind0 : ind1
                    d.setSource(newest.rule, for: targetInd)
                }
            }

            let r0 = d.read(rootRules[rng.next(rootRules.count)])
            let r1 = d.read(rootRules[rng.next(rootRules.count)])
            let cIdx = rng.next(children.count)
            let validBit = d.isValid(children[cIdx].sub) ? 1 : 0
            let weakVal = d.readWeak(children[cIdx].weakRule) ?? -999
            checksum = (checksum &* 31) &+ r0 &+ (r1 &* 3) &+ validBit &+ weakVal

            var deltas: [String] = []
            for k in rootCounts.indices where rootCounts[k] != prevRoot[k] {
                deltas.append("r\(k)+\(rootCounts[k] - prevRoot[k])")
                prevRoot[k] = rootCounts[k]
            }
            for j in childCounts.indices where childCounts[j] != prevChild[j] {
                deltas.append("c\(j)+\(childCounts[j] - prevChild[j])")
                prevChild[j] = childCounts[j]
            }
            stepTraces.append("\(step):[\(r0),\(r1),\(validBit),\(weakVal)]{\(deltas.joined(separator: ","))}")
        }
        totalRunsSummary.append(rootCounts.reduce(0, +) + childCounts.reduce(0, +))
        checksums.append(checksum)
        print("random-subgraph-weak-indirect-oracle-trace|seed=\(seed)|\(stepTraces.joined(separator: ";"))")
        d.close()
    }
    print("random-subgraph-weak-indirect-oracle|runs=\(totalRunsSummary)|checksums=\(checksums)")
}

func mapAndPropertyWrappers() {
    let d = Driver()
    defer { d.close() }
    let source = d.input(4)
    let mapped = d.map(source) { $0 % 2 }
    var mapReaderRuns = 0
    let mapReader = d.rule {
        mapReaderRuns += 1
        return d.read(mapped) * 100
    }
    let m1 = d.read(mapReader)
    let mr1 = mapReaderRuns
    d.write(6, to: source) // 6 % 2 == 0 -> cut!
    let m2 = d.read(mapReader)
    let mr2 = mapReaderRuns
    d.write(7, to: source) // 7 % 2 == 1 -> updates!
    let m3 = d.read(mapReader)
    let mr3 = mapReaderRuns

    let child = d.makeSubgraph()
    let sec = d.withSubgraph(child) { d.input(20) }
    let ovr = d.input(500)
    let r1 = d.typedRule(WrapperProbeRule(primary: source, secondary: d.weak(sec), overrideValue: d.optional(nil)))
    let w1 = d.read(r1) // 7 + 20 = 27
    d.invalidate(child)
    d.write(8, to: source)
    let w2 = d.read(r1) // 8 + (-10) = -2
    let r2 = d.typedRule(WrapperProbeRule(primary: source, secondary: d.weak(sec), overrideValue: d.optional(ovr)))
    let w3 = d.read(r2) // 500

    precondition([m1, m2, m3] == [0, 0, 100] && [mr1, mr2, mr3] == [1, 1, 2])
    precondition([w1, w2, w3] == [27, -2, 500])
    print("map-and-property-wrappers|map=[\(m1), \(m2), \(m3)]|mapRuns=[\(mr1), \(mr2), \(mr3)]|wrappers=[\(w1), \(w2), \(w3)]")
}

func withoutUpdateRead() {
    let d = Driver()
    defer { d.close() }
    let tracked = d.input(10)
    let rawUntracked = d.input(5)
    var untrackedRuns = 0
    let untracked = d.rule {
        untrackedRuns += 1
        return d.read(rawUntracked) * 2
    }
    var outerRuns = 0
    let outer = d.rule {
        outerRuns += 1
        let a = d.read(tracked)
        let b = d.withoutUpdate { d.read(untracked) }
        return a + b
    }
    let v1 = d.read(outer)
    let r1 = [outerRuns, untrackedRuns]

    // Mutating `rawUntracked` dirties `untracked`, NOT `outer`.
    d.write(7, to: rawUntracked)
    let v2 = d.read(outer)
    let r2 = [outerRuns, untrackedRuns]

    // Mutating `tracked` runs `outer`, which reads the updated `untracked` inside `withoutUpdate`.
    d.write(20, to: tracked)
    let v3 = d.read(outer)
    let r3 = [outerRuns, untrackedRuns]

    precondition([v1, v2, v3] == [20, 20, 34])
    precondition(r1 == [1, 1] && r2 == [1, 1] && r3 == [2, 2])
    print("without-update-read|values=[\(v1), \(v2), \(v3)]|runs=[\(r1), \(r2), \(r3)]")
}

private struct MutableScaledRule: Rule {
    var source: Handle<Int>
    var factor: Int
    var value: Int { source.value * factor }
}

func mutateBodyAndInvalidateValue() {
    let d = Driver()
    defer { d.close() }
    let input = d.input(3)
    let scaled = d.typedRule(MutableScaledRule(source: input, factor: 10))
    var downRuns = 0
    let down = d.rule {
        downRuns += 1
        return d.read(scaled) + 1
    }
    let v1 = d.read(down)
    let dr1 = downRuns

    // Mutate without invalidating: `down` stays cached until `input` changes.
    d.mutateBody(of: scaled, as: MutableScaledRule.self, invalidating: false) { $0.factor = 20 }
    let v2 = d.read(down)
    let dr2 = downRuns

    d.write(4, to: input)
    let v3 = d.read(down)
    let dr3 = downRuns

    // Mutate with `invalidating: true`: forces immediate dirtying and recalculation on next read.
    d.mutateBody(of: scaled, as: MutableScaledRule.self, invalidating: true) { $0.factor = 30 }
    let v4 = d.read(down)
    let dr4 = downRuns

    // Explicit `invalidateValue` on a closure rule whose captured external state changed.
    var externalSalt = 10
    var saltRuns = 0
    let salted = d.rule {
        saltRuns += 1
        return d.read(input) + externalSalt
    }
    let sv1 = d.read(salted)
    externalSalt = 50
    d.invalidateValue(of: salted)
    let sv2 = d.read(salted)

    precondition([v1, v2, v3, v4] == [31, 31, 81, 121] && [dr1, dr2, dr3, dr4] == [1, 1, 2, 3])
    precondition([sv1, sv2] == [14, 54] && saltRuns == 2)
    print("mutate-body-and-invalidate-value|values=[\(v1), \(v2), \(v3), \(v4)]|downRuns=[\(dr1), \(dr2), \(dr3), \(dr4)]|salted=[\(sv1), \(sv2)]|saltRuns=\(saltRuns)")
}

func indirectDependencyCutAndRedirect() {
    let d = Driver()
    defer { d.close() }
    let a = d.input(10)
    let b = d.input(100)
    let sel = d.input(0)
    let ind = d.indirect(a)
    let indAttr = d.attribute(of: ind)

    var producerRuns = 0
    let producer = d.rule { () -> Int in
        producerRuns += 1
        let s = d.read(sel)
        if s >= 0 {
            d.setSource(s == 0 ? a : b, for: ind)
        }
        return s
    }
    d.setDependency(of: ind, to: producer)
    let hasDep1 = d.hasDependency(on: ind, matching: producer)

    var readerRuns = 0
    let reader = d.rule {
        readerRuns += 1
        return d.read(indAttr) * 2
    }

    let v1 = d.read(reader)
    let p1 = producerRuns, r1 = readerRuns

    // `sel = -1`: `producer` runs without calling `setSource`, so `reader` is cut!
    d.write(-1, to: sel)
    let v2 = d.read(reader)
    let p2 = producerRuns, r2 = readerRuns

    // `sel = 1`: `producer` runs and redirects `ind` to `b` (100), so `reader` runs!
    d.write(1, to: sel)
    let v3 = d.read(reader)
    let p3 = producerRuns, r3 = readerRuns

    // Clear dependency (`nil`): changing `sel` no longer dirties `ind` or `reader`.
    let nilHandle: Handle<Int>? = nil
    d.setDependency(of: ind, to: nilHandle)
    let hasDep2 = d.hasDependency(on: ind, matching: producer)
    d.write(0, to: sel)
    let v4 = d.read(reader)
    let p4 = producerRuns, r4 = readerRuns

    precondition(hasDep1 && !hasDep2)
    precondition([v1, v2, v3, v4] == [20, 20, 200, 200])
    precondition([p1, p2, p3, p4] == [1, 2, 3, 3] && [r1, r2, r3, r4] == [1, 1, 2, 2])
    print("indirect-dependency-cut-and-redirect|values=[\(v1), \(v2), \(v3), \(v4)]|producerRuns=[\(p1), \(p2), \(p3), \(p4)]|readerRuns=[\(r1), \(r2), \(r3), \(r4)]")
}

func subgraphFlagsForEachAndUpdate() {
    let d = Driver()
    defer { d.close() }
    let root = d.scope
    let c1 = d.makeSubgraph()
    let c2 = d.makeSubgraph()
    let flag0: UInt8 = 1 << 0
    let flag1: UInt8 = 1 << 1
    var order: [String] = []

    func makeFlagged(_ sub: SubgraphHandle, _ name: String, _ flag: UInt8) -> Handle<Int> {
        d.withSubgraph(sub) {
            let r = d.rule {
                order.append(name)
                return 1
            }
            d.setFlags(flag, for: r)
            return r
        }
    }

    _ = makeFlagged(root, "a1", flag0)
    _ = makeFlagged(root, "a2", flag0)
    _ = makeFlagged(c1, "b1", flag0)
    _ = makeFlagged(c1, "b2", flag0)
    _ = makeFlagged(c2, "d1", flag0)
    _ = makeFlagged(c2, "d2", flag1)

    let inter0 = d.intersects(root, flags: flag0)
    let interC1Flag1 = d.intersects(c1, flags: flag1)
    let dirtyBefore = d.isDirty(root, flags: flag0)
    let count0 = d.countMatching(root, flags: flag0)

    d.update(root, flags: flag0)
    let dirtyAfter0 = d.isDirty(root, flags: flag0)
    let dirtyFlag1Before = d.isDirty(root, flags: flag1)
    d.update(root, flags: flag1)
    let dirtyFlag1After = d.isDirty(root, flags: flag1)

    precondition(inter0 && !interC1Flag1 && dirtyBefore && !dirtyAfter0 && dirtyFlag1Before && !dirtyFlag1After && count0 == 5)
    precondition(order == ["a2", "a1", "d1", "b2", "b1", "d2"])
    print("subgraph-flags-forEach-and-update|count0=\(count0)|order=\(order)|dirty=[\(dirtyBefore), \(dirtyAfter0), \(dirtyFlag1Before), \(dirtyFlag1After)]")
}

func hasValueValidateAndUpdateValue() {
    let d = Driver()
    defer { d.close() }
    let input = d.input(10)
    var innerRuns = 0
    let inner = d.rule {
        innerRuns += 1
        return d.read(input) * 3
    }
    let hv0 = d.hasValue(of: inner)
    // `validate` on a cold rule (`hasValue == false`) does nothing.
    d.validate(inner)
    let hv1 = d.hasValue(of: inner)
    let ir1 = innerRuns

    // `updateValue` inside an outer rule brings `inner` up to date without recording a dependency edge on `outer`.
    var outerRuns = 0
    let outer = d.rule {
        outerRuns += 1
        d.updateValue(of: inner)
        return d.read(input) + 1
    }
    let ov1 = d.read(outer)
    let hv2 = d.hasValue(of: inner)
    let ir2 = innerRuns

    // Mutate `input` -> `inner` is dirty and `hasValue == true`; `validate(inner)` checks liveness without evaluating,
    // while `updateValue(of: inner)` brings `inner` up to date!
    d.write(20, to: input)
    d.validate(inner)
    let irAfterValidate = innerRuns
    d.updateValue(of: inner)
    let ir3 = innerRuns
    let iv = d.read(inner)
    let ir4 = innerRuns

    precondition(!hv0 && !hv1 && hv2)
    precondition([ir1, ir2, irAfterValidate, ir3, ir4] == [0, 1, 1, 2, 2] && ov1 == 11 && iv == 60 && outerRuns == 1)
    print("has-value-validate-update-value|hasValue=[\(hv0), \(hv1), \(hv2)]|innerRuns=[\(ir1), \(ir2), \(irAfterValidate), \(ir3), \(ir4)]|values=[\(ov1), \(iv)]")
}

func withoutSubgraphInvalidationAndAncestor() {
    let d = Driver()
    defer { d.close() }
    let root = d.scope
    let parent = d.makeSubgraph()
    let child = d.withSubgraph(parent) { d.makeSubgraph() }
    let sibling = d.makeSubgraph()

    let anc = [
        d.isAncestor(root, of: root),
        d.isAncestor(root, of: child),
        d.isAncestor(parent, of: child),
        d.isAncestor(child, of: parent),
        d.isAncestor(parent, of: sibling)
    ]

    let target = d.withSubgraph(child) { d.input(42) }
    let weakTarget = d.weak(target)
    var validInside = true
    var weakInside: Int? = nil

    d.withoutSubgraphInvalidation {
        d.invalidate(child)
        validInside = d.isValid(child)
        weakInside = d.readWeak(weakTarget)
    }
    let validAfter = d.isValid(child)
    let weakAfter = d.readWeak(weakTarget)

    precondition(anc == [true, true, true, false, false])
    precondition(!validInside && weakInside == 42 && !validAfter && weakAfter == nil)
    print("without-subgraph-invalidation-and-ancestor|ancestor=\(anc)|validInside=\(validInside)|weakInside=\(String(describing: weakInside))|weakAfter=\(String(describing: weakAfter))")
}

func breadthFirstSearchTraversal() {
    let d = Driver()
    defer { d.close() }
    let a = d.input(1)
    let b = d.input(2)
    let r1 = d.rule { d.read(a) + d.read(b) }
    let r2 = d.rule { d.read(r1) + d.read(a) }
    _ = d.read(r2)

    let inputsCount = d.breadthFirstCountInputs(from: r2)
    let outputsCount = d.breadthFirstCountOutputs(from: a)
    let stop = d.breadthFirstStopAt(from: r2, target: r1)

    precondition(inputsCount == 4 && outputsCount == 3 && stop.found && stop.visited == 3)
    print("breadth-first-search|inputs=\(inputsCount)|outputs=\(outputsCount)|stop=\(stop.found)|visited=\(stop.visited)")
}

func attributeKeyPathDynamicMember() {
    let d = Driver()
    defer { d.close() }
    let pair = d.input(ProbePair(left: 3, right: 100))
    let leftSub = d.keyPathSubscript(pair, keyPath: \.left)
    var runs = 0
    let reader = d.rule { () -> Int in
        runs += 1
        return d.read(leftSub) * 2
    }

    let v1 = d.read(reader)
    let r1 = runs
    d.write(ProbePair(left: 3, right: 200), to: pair)
    let v2 = d.read(reader)
    let r2 = runs
    d.write(ProbePair(left: 9, right: 200), to: pair)
    let v3 = d.read(reader)
    let r3 = runs

    precondition([v1, v2, v3] == [6, 6, 18] && [r1, r2, r3] == [1, 1, 2])
    print("attribute-keypath-dynamic-member|values=[\(v1), \(v2), \(v3)]|runs=[\(r1), \(r2), \(r3)]")
}

func branchSwitchAndInvalidateBeforeRead() {
    func runOrder(switchFirst: Bool) -> (v1: Int, v2: Int, aRuns: Int, bRuns: Int, outRuns: Int) {
        let d = Driver()
        defer { d.close() }
        let subA = d.makeSubgraph()
        var aRuns = 0
        var bRuns = 0
        var outRuns = 0

        let inputA = d.withSubgraph(subA) { d.input(10) }
        let branchA = d.withSubgraph(subA) {
            d.rule { () -> Int in
                aRuns += 1
                return d.read(inputA) + 1
            }
        }
        let inputB = d.input(200)
        let branchB = d.rule { () -> Int in
            bRuns += 1
            return d.read(inputB) + 2
        }
        let useB = d.input(false)
        let out = d.rule { () -> Int in
            outRuns += 1
            return d.read(useB) ? d.read(branchB) : d.read(branchA)
        }

        let v1 = d.read(out)
        if switchFirst {
            d.write(true, to: useB)
            d.invalidate(subA)
        } else {
            d.invalidate(subA)
            d.write(true, to: useB)
        }
        let v2 = d.read(out)
        return (v1, v2, aRuns, bRuns, outRuns)
    }

    let orderA = runOrder(switchFirst: true)
    let orderB = runOrder(switchFirst: false)

    precondition(orderA == (11, 202, 1, 1, 2))
    precondition(orderB == (11, 202, 1, 1, 2))
    print("branch-switch-and-invalidate-before-read|switchFirst=\(orderA)|invalidateFirst=\(orderB)")
}

func indirectOriginalDiesWhileRedirected() {
    let d = Driver()
    defer { d.close() }
    let subA = d.makeSubgraph()
    let srcA = d.withSubgraph(subA) { d.input(10) }
    let srcB = d.input(200)
    let ind = d.indirect(srcA)
    let attr = d.attribute(of: ind)

    var readerRuns = 0
    let reader = d.rule { () -> Int in
        readerRuns += 1
        return d.read(attr) + 1
    }

    let v1 = d.read(reader)
    d.setSource(srcB, for: ind)
    let v2 = d.read(reader)
    d.invalidate(subA)
    let v3 = d.read(reader)
    d.write(205, to: srcB)
    let v4 = d.read(reader)

    precondition([v1, v2, v3, v4] == [11, 201, 201, 206] && readerRuns == 3)
    print("indirect-original-dies-while-redirected|values=[\(v1), \(v2), \(v3), \(v4)]|runs=\(readerRuns)")
}

func statefulRuleDependencyPrunedWithoutWritingNewValue() {
    let d = Driver()
    defer { d.close() }
    let a = d.input(10)
    let b = d.input(20)
    let useB = d.input(false)
    var runs = 0

    let r = d.statefulRule { (ctx: StatefulHandleContext<Int>) in
        runs += 1
        if d.read(useB) {
            _ = d.read(b)
            // Intentionally do NOT write `ctx.value`; preserve previous value (100).
        } else {
            _ = d.read(a)
            ctx.value = 100
        }
    }

    let v1 = d.read(r)
    let r1 = runs
    d.write(true, to: useB)
    let v2 = d.read(r)
    let r2 = runs
    d.write(999, to: a)
    let v3 = d.read(r)
    let r3 = runs
    d.write(222, to: b)
    let v4 = d.read(r)
    let r4 = runs

    precondition([v1, v2, v3, v4] == [100, 100, 100, 100] && [r1, r2, r3, r4] == [1, 2, 2, 3])
    print("stateful-dependency-pruned-without-write|values=[\(v1), \(v2), \(v3), \(v4)]|runs=[\(r1), \(r2), \(r3), \(r4)]")
}

func initialValueNoFirstWrite() {
    let d = Driver()
    defer { d.close() }
    let input = d.input(10)
    var rRuns = 0
    var downRuns = 0

    let r = d.statefulRule(initialValue: 77) { (ctx: StatefulHandleContext<Int>) in
        rRuns += 1
        let x = d.read(input)
        if x != 10 && x != 15 {
            ctx.value = x * 2
        }
    }
    let down = d.rule { () -> Int in
        downRuns += 1
        return d.read(r) + 1
    }

    let hvBeforeRead = d.hasValue(of: r)
    let v1 = d.read(down)
    let hvAfterFirstRead = d.hasValue(of: r)
    let s1 = (rRuns, downRuns)

    // Write `15`: `r` runs and reads `input`, still does not write `ctx.value`, keeps 77.
    d.write(15, to: input)
    let v2 = d.read(down)
    let s2 = (rRuns, downRuns)

    // Write `20`: `r` runs and writes `40`, downstream re-runs.
    d.write(20, to: input)
    let v3 = d.read(down)
    let s3 = (rRuns, downRuns)

    precondition([hvBeforeRead, hvAfterFirstRead] == [false, true])
    precondition([v1, v2, v3] == [78, 78, 41])
    precondition([s1.0, s2.0, s3.0] == [1, 2, 3] && [s1.1, s2.1, s3.1] == [1, 1, 2])
    print(
        "initial-value-no-first-write|hasValue=[\(hvBeforeRead), \(hvAfterFirstRead)]|"
            + "values=[\(v1), \(v2), \(v3)]|runs=[\(s1), \(s2), \(s3)]"
    )
}

func nestedSpecialScopesRestoreContext() {
    let d = Driver()
    defer { d.close() }

    // Part A: nested `withoutUpdate` inside a tracked rule, followed by a tracked read after exiting.
    let a = d.input(1)
    let b = d.input(100)
    let c = d.input(1000)
    var outRuns = 0
    let out = d.rule { () -> Int in
        outRuns += 1
        let va = d.read(a)
        let vb = d.withoutUpdate {
            d.withoutUpdate {
                d.read(b)
            }
        }
        let vc = d.read(c)
        return va + vb + vc
    }

    let v1 = d.read(out)
    let r1 = outRuns
    d.write(200, to: b)
    let v2 = d.read(out)
    let r2 = outRuns
    d.write(2000, to: c)
    let v3 = d.read(out)
    let r3 = outRuns

    // Part B: nested `withoutSubgraphInvalidation`.
    let sub1 = d.makeSubgraph()
    let sub2 = d.makeSubgraph()
    let x1 = d.withSubgraph(sub1) { d.input(11) }
    let x2 = d.withSubgraph(sub2) { d.input(22) }
    let w1 = d.weak(x1)
    let w2 = d.weak(x2)
    var aliveBetweenScopes: [Int?] = []

    d.withoutSubgraphInvalidation {
        d.invalidate(sub1)
        d.withoutSubgraphInvalidation {
            d.invalidate(sub2)
        }
        // After exiting the inner scope, the outer scope must still defer destruction of both sub1 and sub2.
        aliveBetweenScopes = [d.readWeak(w1), d.readWeak(w2)]
    }
    let aliveAfterOuter = [d.readWeak(w1), d.readWeak(w2)]

    precondition([v1, v2, v3] == [1101, 1101, 2201] && [r1, r2, r3] == [1, 1, 2])
    precondition(aliveBetweenScopes == [11, 22] && aliveAfterOuter == [nil, nil])
    print(
        "nested-special-scopes|values=[\(v1), \(v2), \(v3)]|runs=[\(r1), \(r2), \(r3)]|"
            + "between=\(aliveBetweenScopes.map { $0.map(String.init) ?? "nil" })|"
            + "afterOuter=\(aliveAfterOuter.map { $0.map(String.init) ?? "nil" })"
    )
}

func reentrantSubgraphInvalidationInObserver() {
    final class TrackedDeinit {
        let name: String
        let log: (String) -> Void
        init(_ name: String, log: @escaping (String) -> Void) {
            self.name = name
            self.log = log
        }
        deinit { log("deinit(\(name))") }
    }

    let d = Driver()
    defer { d.close() }
    var events: [String] = []

    let sub1 = d.makeSubgraph()
    let sub2 = d.makeSubgraph()
    let sub3 = d.makeSubgraph()

    func makeTracked(_ name: String, in sub: SubgraphHandle, value: Int) -> Handle<Int> {
        let obj = TrackedDeinit(name) { events.append($0) }
        return d.withSubgraph(sub) { d.rule { _ = obj; return value } }
    }

    let r1 = makeTracked("obj1", in: sub1, value: 1)
    let r2 = makeTracked("obj2", in: sub2, value: 2)
    let r3 = makeTracked("obj3", in: sub3, value: 3)
    _ = (d.read(r1), d.read(r2), d.read(r3))

    let t1 = d.observeSubgraph(sub1) {
        events.append("notice1-start")
        d.invalidate(sub2)
        events.append("notice1-end")
    }
    let t2 = d.observeSubgraph(sub2) {
        events.append("notice2-start")
        d.invalidate(sub3)
        events.append("notice2-end")
    }
    let t3 = d.observeSubgraph(sub3) {
        events.append("notice3")
    }
    _ = (t1, t2, t3)

    d.invalidate(sub1)
    let validAfter = [!d.isValid(sub1), !d.isValid(sub2), !d.isValid(sub3)]
    precondition(validAfter == [true, true, true] && d.nodeCount == 0)
    precondition(
        events == [
            "notice1-start", "notice1-end", "deinit(obj1)",
            "notice2-start", "notice2-end", "deinit(obj2)",
            "notice3", "deinit(obj3)",
        ]
    )
    print("reentrant-subgraph-invalidation|validAfter=\(validAfter)|nodes=\(d.nodeCount)|events=\(events)")
}

func weakAttributeNeverResurrectsAcrossReuse() {
    let d = Driver()
    defer { d.close() }

    var staleWeaks: [WeakHandle<Int>] = []
    let sub0 = d.makeSubgraph()
    let a0 = d.withSubgraph(sub0) { d.input(999) }
    let w0 = d.weak(a0)
    staleWeaks.append(w0)
    d.invalidate(sub0)

    var resurrectionCount = 0
    for i in 0..<2_000 {
        let sub = d.makeSubgraph()
        let (x, r) = d.withSubgraph(sub) { () -> (Handle<Int>, Handle<Int>) in
            let x = d.input(i)
            let r = d.rule { d.read(x) + 1 }
            return (x, r)
        }
        _ = d.read(r)
        if i % 20 == 0 {
            staleWeaks.append(d.weak(x))
        }
        d.invalidate(sub)
        if d.readWeak(w0) != nil {
            resurrectionCount += 1
        }
    }

    let nonNilAtEnd = staleWeaks.filter { d.readWeak($0) != nil }.count
    precondition(resurrectionCount == 0 && nonNilAtEnd == 0 && d.nodeCount == 0)
    print("weak-attribute-slot-reuse|staleCount=\(staleWeaks.count)|resurrectionsDuring=\(resurrectionCount)|nonNilAtEnd=\(nonNilAtEnd)|nodesAfter=\(d.nodeCount)")
}

func indirectResetSourceAfterMultipleRedirects() {
    let d = Driver()
    defer { d.close() }
    let a = d.input(10)
    let b = d.input(20)
    let c = d.input(30)
    let ind = d.indirect(a)
    let attr = d.attribute(of: ind)

    var readerRuns = 0
    let reader = d.rule { () -> Int in
        readerRuns += 1
        return d.read(attr) + 1
    }

    let v1 = d.read(reader)
    d.setSource(b, for: ind)
    let v2 = d.read(reader)
    d.setSource(c, for: ind)
    let v3 = d.read(reader)
    d.resetSource(of: ind)
    let v4 = d.read(reader)
    d.write(15, to: a)
    let v5 = d.read(reader)

    precondition([v1, v2, v3, v4, v5] == [11, 21, 31, 11, 16] && readerRuns == 5)
    print("indirect-reset-source-multi-redirect|values=[\(v1), \(v2), \(v3), \(v4), \(v5)]|runs=\(readerRuns)")
}

func indirectChainAndIntermediateDeath() {
    let d = Driver()
    defer { d.close() }
    let a = d.input(10)
    let aSame = d.input(10)
    let b = d.input(20)

    let subChild = d.makeSubgraph()
    let c = d.withSubgraph(subChild) { d.input(30) }

    var dep1Runs = 0
    let dep1 = d.rule { () -> Int in dep1Runs += 1; return d.read(a) * 10 }
    var dep2Runs = 0
    let dep2 = d.rule { () -> Int in dep2Runs += 1; return d.read(b) * 100 }

    let ind1 = d.indirect(a)
    d.setDependency(of: ind1, to: dep1)
    let ind1Attr = d.attribute(of: ind1)

    let ind2 = d.indirect(ind1Attr)
    d.setDependency(of: ind2, to: dep2)
    let ind2Attr = d.attribute(of: ind2)

    var readerRuns = 0
    let reader = d.rule { () -> Int in
        readerRuns += 1
        return d.read(ind2Attr) + 1
    }

    let v1 = d.read(reader)
    let r1 = readerRuns

    // Redirect ind1 from a(10) to aSame(10): same numeric value! Does ind2 / reader re-run?
    d.setSource(aSame, for: ind1)
    let v2 = d.read(reader)
    let r2 = readerRuns

    // Redirect ind1 to c(30) in child subgraph, then invalidate child subgraph -> ind1 resets to aSame or initial `a`?
    d.setSource(c, for: ind1)
    let v3 = d.read(reader)
    let r3 = readerRuns

    d.invalidate(subChild)
    let v4 = d.read(reader)
    let r4 = readerRuns

    precondition([v1, v2, v3, v4] == [11, 11, 31, 31] && [r1, r2, r3, r4] == [1, 2, 3, 3] && dep1Runs == 1 && dep2Runs == 1)
    print(
        "indirect-chain-and-intermediate-death|values=[\(v1), \(v2), \(v3), \(v4)]|"
            + "readerRuns=[\(r1), \(r2), \(r3), \(r4)]|deps=[\(dep1Runs), \(dep2Runs)]"
    )
}

func changedValueAfterSkippedReadsAndIndirect() {
    let d = Driver()
    defer { d.close() }

    // Part A: skipped reads while input changed and returned to original value.
    let flag = d.input(true)
    let x = d.input(10)
    let y = d.input(99)
    var changedLog: [(Int, Bool)] = []
    var runs = 0

    let sr = d.statefulRule { (ctx: StatefulHandleContext<Int>) in
        runs += 1
        let f = d.read(flag)
        if f {
            let cv = ctx.changedValue(of: x)
            changedLog.append(cv)
            ctx.value = cv.value
        } else {
            let cy = ctx.changedValue(of: y)
            ctx.value = cy.value
        }
    }

    let v1 = d.read(sr)
    d.write(false, to: flag)
    let v2 = d.read(sr)
    // Mutate x away and back while sr is not reading x.
    d.write(50, to: x)
    d.write(10, to: x)
    d.write(true, to: flag)
    let v3 = d.read(sr)

    // Part B: changedValue of an IndirectAttribute redirected to a different source with the SAME value.
    let s1 = d.input(50)
    let s2 = d.input(50)
    let ind = d.indirect(s1)
    let indAttr = d.attribute(of: ind)
    let tick = d.input(0)
    var indLog: [(Int, Bool)] = []

    let srInd = d.statefulRule { (ctx: StatefulHandleContext<Int>) in
        _ = d.read(tick)
        let cv = ctx.changedValue(of: indAttr)
        indLog.append(cv)
        ctx.value = cv.value + d.read(tick)
    }

    let iv1 = d.read(srInd)
    d.setSource(s2, for: ind)
    let iv2 = d.read(srInd)
    d.write(1, to: tick)
    let iv3 = d.read(srInd)

    let aChangedStrings = changedLog.map { "\($0.0):\($0.1)" }
    let bChangedStrings = indLog.map { "\($0.0):\($0.1)" }
    precondition([v1, v2, v3] == [10, 99, 10] && aChangedStrings == ["10:true", "10:true"])
    precondition([iv1, iv2, iv3] == [50, 50, 51] && bChangedStrings == ["50:true", "50:true", "50:false"])
    print(
        "changed-value-after-skipped-and-indirect|aVals=[\(v1), \(v2), \(v3)]|"
            + "aChanged=\(aChangedStrings)|"
            + "bVals=[\(iv1), \(iv2), \(iv3)]|"
            + "bChanged=\(bChangedStrings)"
    )
}

func multiObserverTreeOrderAndCancel() {
    let d = Driver()
    defer { d.close() }
    var events: [String] = []

    let parent = d.makeSubgraph()
    let child1 = d.withSubgraph(parent) { d.makeSubgraph() }
    let grand1 = d.withSubgraph(child1) { d.makeSubgraph() }
    let child2 = d.withSubgraph(parent) { d.makeSubgraph() }

    var cancelC1Obs2: SubgraphObserverHandle? = nil
    var cancelC2Obs2: SubgraphObserverHandle? = nil
    let c1Obs1 = d.observeSubgraph(child1) {
        events.append("child1-obs1")
        cancelC1Obs2?.cancel()
    }
    let c1Obs2 = d.observeSubgraph(child1) {
        events.append("child1-obs2")
    }
    cancelC1Obs2 = c1Obs2

    let g1Obs1 = d.observeSubgraph(grand1) {
        events.append("grand1-obs1")
    }
    let c2Obs1 = d.observeSubgraph(child2) {
        events.append("child2-obs1")
    }
    let c2Obs2 = d.observeSubgraph(child2) {
        events.append("child2-obs2")
    }
    cancelC2Obs2 = c2Obs2
    let pObs1 = d.observeSubgraph(parent) {
        events.append("parent-obs1")
        cancelC2Obs2?.cancel()
    }
    let pObs2 = d.observeSubgraph(parent) {
        events.append("parent-obs2")
    }
    _ = (c1Obs1, c1Obs2, g1Obs1, c2Obs1, c2Obs2, pObs1, pObs2)

    d.invalidate(parent)
    precondition(events == ["parent-obs1", "parent-obs2", "child2-obs1", "child1-obs1", "child1-obs2", "grand1-obs1"])
    print("multi-observer-tree-order-and-cancel|events=\(events)")
}

func offsetRangeInsideAndOutside() {
    struct Pair: BitwiseCopyable, Equatable { var x: Int64; var y: Int64 }
    let graph = Driver()
    let source = graph.input(Pair(x: 1, y: 10))
    let field = graph.offsetIndirect(source, keyPath: \Pair.y)
    var runs = 0
    let consumer = graph.rule {
        runs += 1
        return graph.read(field) * 2
    }
    let v1 = graph.read(consumer)
    let r1 = runs
    graph.write(Pair(x: 99, y: 10), to: source)
    let v2 = graph.read(consumer)
    let r2 = runs
    graph.write(Pair(x: 99, y: 25), to: source)
    let v3 = graph.read(consumer)
    let r3 = runs
    print("offset-range-inside-outside|values=\([v1, v2, v3])|runs=\([r1, r2, r3])")
}

func offsetStickyInsideThenOutside() {
    struct Pair: BitwiseCopyable, Equatable { var x: Int64; var y: Int64 }
    let graph = Driver()
    let source = graph.input(Pair(x: 1, y: 10))
    let field = graph.offsetIndirect(source, keyPath: \Pair.y)
    var runs = 0
    let consumer = graph.rule {
        runs += 1
        return graph.read(field) * 2
    }
    let v1 = graph.read(consumer)
    let r1 = runs
    graph.write(Pair(x: 1, y: 20), to: source)
    graph.write(Pair(x: 99, y: 10), to: source)
    let v2 = graph.read(consumer)
    let r2 = runs
    print("offset-sticky-inside-then-outside|values=\([v1, v2])|runs=\([r1, r2])")
}

func offsetMixedChain() {
    struct Pair: BitwiseCopyable, Equatable { var x: Int64; var y: Int64 }
    let graph = Driver()
    let source = graph.input(Pair(x: 1, y: 10))
    let field = graph.offsetIndirect(source, keyPath: \Pair.y)
    let ind = graph.indirect(field)
    var runs = 0
    let consumer: Handle<Int64> = graph.rule {
        runs += 1
        return graph.read(ind.projectedValue) * 2
    }
    let v1 = graph.read(consumer)
    let r1 = runs
    // Outside range
    graph.write(Pair(x: 99, y: 10), to: source)
    let v2 = graph.read(consumer)
    let r2 = runs
    // Inside range
    graph.write(Pair(x: 99, y: 20), to: source)
    let v3 = graph.read(consumer)
    let r3 = runs
    // Sticky: inside then back to original before reading
    graph.write(Pair(x: 99, y: 30), to: source)
    graph.write(Pair(x: 99, y: 20), to: source)
    let v4 = graph.read(consumer)
    let r4 = runs
    print("offset-mixed-chain|values=\([v1, v2, v3, v4])|runs=\([r1, r2, r3, r4])")
}

func indirectSetSameValue() {
    let graph = Driver()
    let a = graph.input(Int64(10))
    let b = graph.input(Int64(10))
    let ind = graph.indirect(a)
    var runs = 0
    let consumer: Handle<Int64> = graph.rule {
        runs += 1
        return graph.read(ind.projectedValue) + 1
    }
    let v1 = graph.read(consumer)
    let r1 = runs
    graph.setSource(b, for: ind)
    let v2 = graph.read(consumer)
    let r2 = runs
    print("indirect-set-same-value|values=\([v1, v2])|runs=\([r1, r2])")
}

func directEdgeEqualAndDifferentWrite() {
    let graph = Driver()
    let source = graph.input(Int64(10))
    var runs = 0
    let consumer: Handle<Int64> = graph.rule {
        runs += 1
        return graph.read(source) * 2
    }
    let v1 = graph.read(consumer)
    let r1 = runs
    graph.write(Int64(10), to: source)
    let v2 = graph.read(consumer)
    let r2 = runs
    graph.write(Int64(25), to: source)
    let v3 = graph.read(consumer)
    let r3 = runs
    print("direct-edge-equal-and-different-write|values=\([v1, v2, v3])|runs=\([r1, r2, r3])")
}

func offsetWholeValue() {
    struct Pair: BitwiseCopyable, Equatable { var x: Int64; var y: Int64 }
    let graph = Driver()
    let source = graph.input(Pair(x: 1, y: 10))
    let whole = graph.offsetIndirect(source, keyPath: \Pair.self)
    var runs = 0
    let consumer: Handle<Int64> = graph.rule {
        runs += 1
        return graph.read(whole).y * 2
    }
    let v1 = graph.read(consumer)
    let r1 = runs
    // Different x, same y: since whole covers the entire struct, it must re-evaluate
    graph.write(Pair(x: 99, y: 10), to: source)
    let v2 = graph.read(consumer)
    let r2 = runs
    // Same whole value: should cut
    graph.write(Pair(x: 99, y: 10), to: source)
    let v3 = graph.read(consumer)
    let r3 = runs
    print("offset-whole-value|values=\([v1, v2, v3])|runs=\([r1, r2, r3])")
}

func subgraphDagAddChild() {
    let graph = Driver()
    // Case A: same context (parent1 -> child, then parent2 -> child; invalidate parent1)
    let p1 = graph.makeSubgraph()
    let p2 = graph.makeSubgraph()
    let childSame = graph.withSubgraph(p1) { graph.makeSubgraph() }
    graph.addChild(childSame, to: p2)
    graph.invalidate(p1)
    let sameValidAfterP1 = graph.isValid(childSame)
    graph.invalidate(p2)
    let sameValidAfterP2 = graph.isValid(childSame)

    print("subgraph-dag-add-child|same=[\(sameValidAfterP1), \(sameValidAfterP2)]")
}

func contextUpdateCallback() {
    let graph = Driver()
    var calls = 0
    var drainExtra = false
    graph.setUpdateCallback {
        calls += 1
        if drainExtra {
            drainExtra = false
            graph.setNeedsUpdate()
        }
    }
    let a = graph.input(Int64(1))
    let r: Handle<Int64> = graph.rule { graph.read(a) + 1 }
    _ = graph.read(r)
    // Two setNeedsUpdate calls before any read: coalesced
    graph.setNeedsUpdate()
    graph.setNeedsUpdate()
    let callsBeforeRead = calls
    _ = graph.read(r)
    let callsAfterRead = calls

    // Request another update from inside the callback (same-pass drain)
    drainExtra = true
    graph.setNeedsUpdate()
    _ = graph.read(r)
    let callsAfterReentrant = calls
    print("context-update-callback|before=\(callsBeforeRead)|after=\(callsAfterRead)|reentrant=\(callsAfterReentrant)")
}

func cooperativeCancel() {
    let graph = Driver()
    let a = graph.input(Int64(10))
    var shouldCancel = false
    var runs = 0
    let r: Handle<Int64> = graph.rule {
        runs += 1
        let v = graph.read(a) * 2
        if shouldCancel {
            graph.cancelUpdate()
            return 999
        }
        return v
    }
    let v1 = graph.read(r)
    let r1 = runs

    graph.write(Int64(50), to: a)
    shouldCancel = true
    let v2 = graph.read(r)
    let r2 = runs

    shouldCancel = false
    let v3 = graph.read(r)
    let r3 = runs
    print("cooperative-cancel|values=\([v1, v2, v3])|runs=\([r1, r2, r3])")
}
