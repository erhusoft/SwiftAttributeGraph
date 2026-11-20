import Testing
@testable import SwiftAttributeGraph

/// The minimal model of shared contexts (`AGGraphCreateShared`): a second context over the same graph with its own
/// identifier, update callback, `needsUpdate` flag and `contextThreadUpdating`, and its own subgraphs. Expected values
/// were measured on macOS 15.8.3 with `native-scratch/nc6b.swift` [O].
@Suite struct SharedGraphContextTests {
    @Test func sharedContextKeepsTheGraphIDAndTakesTheNextCounterNumber() {
        let graph = Graph()
        let other = Graph()
        let shared = graph.makeSharedContext()
        let after = Graph()
        #expect(graph.defaultContext.contextID == graph.counter(for: .graphID) + 1)
        #expect(shared.graphID == graph.counter(for: .graphID), "native: same graphID as the original [O]")
        #expect(shared.contextID > other.counter(for: .contextID), "native: advances the process counter [O]")
        #expect(after.counter(for: .graphID) > shared.contextID)
        #expect(shared.counter(for: .contextID) == shared.contextID)
        #expect(shared.counter(for: .graphID) == graph.counter(for: .graphID))
        #expect(shared !== graph.defaultContext, "native: the object returned is not the original [O]")
    }

    @Test func subgraphsBelongToTheContextTheyWereCreatedWith() {
        let graph = Graph()
        let shared = graph.makeSharedContext()
        let sg1 = graph.defaultContext.makeSubgraph()
        let sg2 = shared.makeSubgraph()
        let a1 = graph.withCurrent(sg1) { graph.makeInput(Int64(1)) }
        let a2 = graph.withCurrent(sg2) { graph.makeInput(Int64(2)) }
        #expect(graph.graphContext(of: sg1) === graph.defaultContext)
        #expect(graph.graphContext(of: sg2) === shared)
        #expect(graph.graphContext(of: a1) === graph.defaultContext)
        #expect(graph.graphContext(of: a2) === shared)
        #expect(graph.graphContext(of: graph.rootSubgraph) === graph.defaultContext)
    }

    @Test func needsUpdateIsPerContextAndAnyRuleReadClearsAllOfThem() {
        let graph = Graph()
        let shared = graph.makeSharedContext()
        let original = graph.defaultContext
        let sg1 = original.makeSubgraph()
        let sg2 = shared.makeSubgraph()
        let a = graph.withCurrent(sg1) { graph.makeInput(Int64(1)) }
        let r1 = graph.withCurrent(sg1) { graph.makeRule { graph.value(of: a) + 1 } }
        let r2 = graph.withCurrent(sg2) { graph.makeRule { graph.value(of: a) + 2 } }
        func flags() -> [UInt64] {
            [original.counter(for: .needsUpdate), original.counter(for: .contextNeedsUpdate),
             shared.counter(for: .needsUpdate), shared.counter(for: .contextNeedsUpdate)]
        }
        #expect(flags() == [0, 0, 0, 0])
        graph.setNeedsUpdate()
        #expect(flags() == [1, 1, 1, 0], "native: nu is graph-wide, cnu only of the original [O]")
        _ = graph.value(of: r2)
        #expect(flags() == [0, 0, 0, 0], "native: a rule read in the other context clears both [O]")
        shared.setNeedsUpdate()
        #expect(flags() == [1, 0, 1, 1])
        _ = graph.value(of: r1)
        #expect(flags() == [0, 0, 0, 0])
        graph.setNeedsUpdate(); shared.setNeedsUpdate()
        #expect(flags() == [1, 1, 1, 1])
        _ = graph.value(of: a)
        #expect(flags() == [1, 1, 1, 1], "native: reading an input clears nothing [O]")
        _ = graph.value(of: r2)
        #expect(flags() == [0, 0, 0, 0])
    }

    @Test func updateCallbacksFireForTheContextThatRaisedTheFlag() {
        let graph = Graph()
        let shared = graph.makeSharedContext()
        var calls1 = 0, calls2 = 0
        graph.setUpdateCallback { calls1 += 1 }
        shared.setUpdateCallback { calls2 += 1 }
        let sg1 = graph.defaultContext.makeSubgraph()
        let sg2 = shared.makeSubgraph()
        let a = graph.withCurrent(sg1) { graph.makeInput(Int64(1)) }
        let r1 = graph.withCurrent(sg1) { graph.makeRule { graph.value(of: a) + 1 } }
        let r2 = graph.withCurrent(sg2) { graph.makeRule { graph.value(of: a) + 2 } }
        _ = graph.value(of: r1); _ = graph.value(of: r2)
        #expect([calls1, calls2] == [0, 0], "native: nothing fires without setNeedsUpdate [O]")
        graph.setNeedsUpdate()
        _ = graph.value(of: r2)
        #expect([calls1, calls2] == [1, 0], "native: the callback of the context that raised it, read in the other one [O]")
        shared.setNeedsUpdate()
        _ = graph.value(of: r1)
        #expect([calls1, calls2] == [1, 1])
        graph.setNeedsUpdate(); shared.setNeedsUpdate()
        _ = graph.value(of: r1)
        #expect([calls1, calls2] == [2, 2])
    }

    @Test func readingAnInputDrainsNoCallbackButReadingATopLevelRuleDrainsAllContexts() {
        let graph = Graph()
        let shared = graph.makeSharedContext()
        var calls1 = 0, calls2 = 0
        graph.setUpdateCallback { calls1 += 1 }
        shared.setUpdateCallback { calls2 += 1 }
        let sg1 = graph.defaultContext.makeSubgraph()
        let a = graph.withCurrent(sg1) { graph.makeInput(Int64(1)) }
        let r1 = graph.withCurrent(sg1) { graph.makeRule { graph.value(of: a) + 1 } }
        graph.setNeedsUpdate(); shared.setNeedsUpdate()
        _ = graph.value(of: a)
        #expect([calls1, calls2] == [0, 0], "native: an input read drains nothing, afterInput=0,0 [O]")
        _ = graph.value(of: r1)
        #expect([calls1, calls2] == [1, 1], "native: a top-level rule read drains every context, afterRule=1,1 [O]")
    }

    @Test func contextThreadUpdatingIsOnlyOneForTheContextOfTheRunningRule() {
        let graph = Graph()
        let shared = graph.makeSharedContext()
        let original = graph.defaultContext
        let sg1 = original.makeSubgraph()
        let sg2 = shared.makeSubgraph()
        var seen: [String] = []
        func probe(_ label: String) {
            seen.append("\(label): g1[\(original.counter(for: .threadUpdating)),\(original.counter(for: .contextThreadUpdating))] "
                        + "g2[\(shared.counter(for: .threadUpdating)),\(shared.counter(for: .contextThreadUpdating))]")
        }
        let t1 = graph.withCurrent(sg1) { graph.makeRule { probe("r1"); return Int64(1) } }
        let t2 = graph.withCurrent(sg2) { graph.makeRule { probe("r2"); return Int64(2) } }
        _ = graph.value(of: t1); _ = graph.value(of: t2)
        #expect(seen == ["r1: g1[1,1] g2[1,0]", "r2: g1[1,0] g2[1,1]"], "native [O]")
    }

    @Test func invalidatingTheSubgraphOfOneContextLeavesTheOtherAlive() {
        let graph = Graph()
        let shared = graph.makeSharedContext()
        let sg1 = graph.defaultContext.makeSubgraph()
        let sg2 = shared.makeSubgraph()
        let a1 = graph.withCurrent(sg1) { graph.makeInput(Int64(1)) }
        _ = graph.withCurrent(sg2) { graph.makeInput(Int64(2)) }
        #expect(graph.counter(for: .nodes) == 2)
        graph.invalidate(sg2)
        #expect(graph.isValid(sg1) && !graph.isValid(sg2))
        #expect(graph.value(of: a1) == 1)
        #expect(shared.counter(for: .nodes) == 1 && graph.counter(for: .nodes) == 1, "native: counters are graph-wide [O]")
        #expect(graph.counter(for: .subgraphs) == 1)
        graph.invalidate(sg1)
        #expect(graph.counter(for: .nodes) == 0 && graph.counter(for: .subgraphs) == 0)
    }

    @Test func aContextOfAGraphWithoutSharedContextsMatchesTheGraphCounters() {
        let graph = Graph()
        graph.setNeedsUpdate()
        #expect(graph.defaultContext.counter(for: .contextNeedsUpdate) == graph.counter(for: .contextNeedsUpdate))
        #expect(graph.defaultContext.counter(for: .needsUpdate) == 1)
    }

    @Test func setContextAndGetContextStorePerContextOpaquePointer() {
        let graph = Graph()
        let shared = graph.makeSharedContext()
        #expect(graph.context == nil)
        #expect(graph.defaultContext.context == nil)
        #expect(shared.context == nil)

        var token1 = 111
        var token2 = 222
        withUnsafePointer(to: &token1) { p1 in
            withUnsafePointer(to: &token2) { p2 in
                let raw1 = UnsafeRawPointer(p1)
                let raw2 = UnsafeRawPointer(p2)
                graph.context = raw1
                #expect(graph.context == raw1)
                #expect(graph.defaultContext.context == raw1)
                #expect(shared.context == nil)

                shared.context = raw2
                #expect(graph.context == raw1)
                #expect(shared.context == raw2)

                graph.context = nil
                #expect(graph.context == nil)
                #expect(shared.context == raw2)
            }
        }
    }

    @Test func invalidationCallbackFiresAcrossContextsWithMinimalSequenceAndCounterproofs() {
        let graph = Graph()
        let c1 = graph.defaultContext
        let c2 = graph.makeSharedContext()
        var events: [AnyAttribute] = []
        c2.setInvalidationCallback { attr in
            events.append(attr)
        }

        let sg1 = c1.makeSubgraph()
        let sg2 = c2.makeSubgraph()
        let a = graph.withCurrent(sg1) { graph.makeInput(Int64(10)) }
        let r = graph.withCurrent(sg2) { graph.makeRule { graph.value(of: a) + 1 } }
        let r2 = graph.withCurrent(sg2) { graph.makeRule { graph.value(of: r) + 1 } }

        // Counterproof 1: writing before any read does not fire (initial read epoch 0 == 0, and r is dirty)
        graph.setValue(11, for: a)
        #expect(events.isEmpty)

        // Minimal sequence: read r2 once, then write a -> fires once with origin attribute a
        _ = graph.value(of: r2)
        graph.setValue(12, for: a)
        #expect(events == [a.erased])
        events.removeAll()

        // Counterproof 2: second consecutive write without an intervening read does not fire
        graph.setValue(13, for: a)
        #expect(events.isEmpty)

        // (e) Writing twice with a read of r2 in between fires a second time
        _ = graph.value(of: r2)
        graph.setValue(14, for: a)
        #expect(events == [a.erased])
        events.removeAll()

        // Reading only input `a` (leaving `r` dirty) and writing `a` again does not fire because `r` is not clean
        _ = graph.value(of: a)
        graph.setValue(15, for: a)
        #expect(events.isEmpty)

        // Counterproof 3: single context never fires
        let single = Graph()
        var singleEvents = 0
        single.setInvalidationCallback { _ in singleEvents += 1 }
        let sgs = single.defaultContext.makeSubgraph()
        let sa = single.withCurrent(sgs) { single.makeInput(Int64(1)) }
        let sr1 = single.withCurrent(sgs) { single.makeRule { single.value(of: sa) + 1 } }
        let sr2 = single.withCurrent(sgs) { single.makeRule { single.value(of: sr1) + 1 } }
        _ = single.value(of: sr2)
        single.setValue(2, for: sa)
        #expect(singleEvents == 0)
    }

    @Test func invalidationCallbackRunsWithoutCurrentUpdateAndCanReadValues() {
        let graph = Graph()
        let c1 = graph.defaultContext
        let c2 = graph.makeSharedContext()
        let sg1 = c1.makeSubgraph()
        let sg2 = c2.makeSubgraph()

        let a = graph.withCurrent(sg1) { graph.makeInput(Int64(10)) }
        let r = graph.withCurrent(sg2) { graph.makeRule { graph.value(of: a) + 1 } }
        let r2 = graph.withCurrent(sg2) { graph.makeRule { graph.value(of: r) + 1 } }

        var log: [String] = []
        var readR2InCallback = false
        c2.setInvalidationCallback { _ in
            let curNil = Graph.currentAttribute == nil
            let tu = "\(c1.counter(for: .threadUpdating))\(c1.counter(for: .contextThreadUpdating))\(c2.counter(for: .contextThreadUpdating))"
            let aVal = graph.value(of: a)
            let r2Val = readR2InCallback ? graph.value(of: r2) : -1
            log.append("curNil=\(curNil),tu=\(tu),a=\(aVal),r2=\(r2Val)")
        }

        _ = graph.value(of: r2)
        graph.setValue(20, for: a)
        _ = graph.value(of: r2)
        readR2InCallback = true
        graph.setValue(30, for: a)
        readR2InCallback = false
        // Because the previous callback read r2 itself, r is clean again, but the epoch was bumped during that read!
        //Wait: native probe_t2_c showed that after callback read r2, writing a=40 did NOT fire a 3rd callback!
        graph.setValue(40, for: a)
        #expect(log == [
            "curNil=true,tu=000,a=20,r2=-1",
            "curNil=true,tu=000,a=30,r2=22"
        ])

        // Inside an active update: rule mRule in c1 invalidates aRule in c1 while evaluating
        let g2 = Graph()
        let ctx1 = g2.defaultContext
        let ctx2 = g2.makeSharedContext()
        let s1 = ctx1.makeSubgraph()
        let s2 = ctx2.makeSubgraph()
        let trig = g2.withCurrent(s1) { g2.makeInput(Int64(0)) }
        let srcA = g2.withCurrent(s1) { g2.makeInput(Int64(100)) }
        let aRule = g2.withCurrent(s1) { g2.makeRule { g2.value(of: srcA) + 1 } }
        let mRule = g2.withCurrent(s1) {
            g2.makeRule { () -> Int64 in
                let v = g2.value(of: trig)
                if v > 0 {
                    g2.withoutUpdate { g2.invalidateValue(of: aRule) }
                }
                return v
            }
        }
        let cr1 = g2.withCurrent(s2) { g2.makeRule { g2.value(of: aRule) + 1 } }
        let cr2 = g2.withCurrent(s2) { g2.makeRule { g2.value(of: cr1) + 1 } }
        var insideLog: [String] = []
        ctx2.setInvalidationCallback { attr in
            let curNil = Graph.currentAttribute == nil
            let tu = "\(ctx1.counter(for: .threadUpdating))\(ctx1.counter(for: .contextThreadUpdating))\(ctx2.counter(for: .contextThreadUpdating))"
            let val = g2.value(of: srcA)
            insideLog.append("match=\(attr == aRule.erased),curNil=\(curNil),tu=\(tu),src=\(val)")
        }
        _ = g2.value(of: cr2)
        _ = g2.value(of: mRule)
        g2.setValue(1, for: trig)
        _ = g2.value(of: mRule)
        #expect(insideLog == ["match=true,curNil=true,tu=110,src=100"])
    }

    @Test func invalidationCallbackAcrossThreeContextsAndAfterSubgraphOrContextInvalidation() {
        // (d) Three contexts A -> B -> C (with and without an output on C)
        let graph = Graph()
        let c1 = graph.defaultContext
        let c2 = graph.makeSharedContext()
        let c3 = graph.makeSharedContext()
        let sg1 = c1.makeSubgraph()
        let sg2 = c2.makeSubgraph()
        let sg3 = c3.makeSubgraph()

        let a = graph.withCurrent(sg1) { graph.makeInput(Int64(10)) }
        let b = graph.withCurrent(sg2) { graph.makeRule { graph.value(of: a) + 1 } }
        let c = graph.withCurrent(sg3) { graph.makeRule { graph.value(of: b) + 1 } }

        var ev1: [AnyAttribute] = []
        var ev2: [AnyAttribute] = []
        var ev3: [AnyAttribute] = []
        c1.setInvalidationCallback { ev1.append($0) }
        c2.setInvalidationCallback { ev2.append($0) }
        c3.setInvalidationCallback { ev3.append($0) }

        // Without an output on c, only c2 fires (b has output c; c has no outputs)
        _ = graph.value(of: c)
        graph.setValue(20, for: a)
        #expect(ev1.isEmpty && ev2 == [a.erased] && ev3.isEmpty)
        ev2.removeAll()

        // With an output c2 on c in sg3, both c2 and c3 fire with origin attribute `a`
        let cOut = graph.withCurrent(sg3) { graph.makeRule { graph.value(of: c) + 1 } }
        _ = graph.value(of: cOut)
        graph.setValue(30, for: a)
        #expect(ev1.isEmpty && ev2 == [a.erased] && ev3 == [a.erased])
        ev2.removeAll(); ev3.removeAll()

        // Invalidating `b` in c2 notifies only c3 with `b`
        _ = graph.value(of: cOut)
        graph.invalidateValue(of: b)
        #expect(ev1.isEmpty && ev2.isEmpty && ev3 == [b.erased])
        ev3.removeAll()

        // (f) Invalidating consumer subgraph sg3 stops c3 from firing
        _ = graph.value(of: cOut)
        graph.invalidate(sg3)
        #expect(ev1.isEmpty && ev2.isEmpty && ev3.isEmpty)
        graph.setValue(40, for: a)
        // Now `b` in sg2 has no outputs left either (since `c` in sg3 was invalidated!), so neither c2 nor c3 fires!
        #expect(ev1.isEmpty && ev2.isEmpty && ev3.isEmpty)

        // (g) Invalidating context 2 stops c2 from firing
        let bOut = graph.withCurrent(sg2) { graph.makeRule { graph.value(of: b) + 1 } }
        _ = graph.value(of: bOut)
        graph.setValue(50, for: a)
        #expect(ev2 == [a.erased])
        ev2.removeAll()
        _ = graph.value(of: bOut)
        c2.invalidate()
        graph.setValue(60, for: a)
        #expect(ev2.isEmpty)
    }
}
