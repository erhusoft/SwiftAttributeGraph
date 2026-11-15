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

private struct ProbePair {
    var left: Int
    var right: Int
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
