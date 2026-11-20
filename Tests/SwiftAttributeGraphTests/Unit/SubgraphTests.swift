import Testing
@testable import SwiftAttributeGraph

/// Hierarchical subgraphs, the notice before they disappear, and invalidation from inside a rule (M5,
/// `docs/DISENO-M5.md`).
@Suite struct SubgraphTests {
    private final class Log { var events: [String] = [] }
    private final class Counter { var runs = 0 }

    // MARK: Hierarchy

    @Test func theDefaultParentIsTheCurrentSubgraph() {
        let graph = Graph()
        let a = graph.makeSubgraph()
        #expect(graph.parent(of: a) == graph.rootSubgraph)
        let b = graph.withCurrent(a) { graph.makeSubgraph() }
        #expect(graph.parent(of: b) == a)
        let c = graph.makeSubgraph(parent: a)
        #expect(graph.parent(of: c) == a)
        #expect(graph.children(of: a) == [b, c])
        #expect(graph.parent(of: graph.rootSubgraph) == nil)
    }

    @Test func invalidatingAParentInvalidatesItsDescendants() {
        let graph = Graph()
        let parent = graph.makeSubgraph()
        let child = graph.makeSubgraph(parent: parent)
        let grandchild = graph.makeSubgraph(parent: child)
        let attributes = [parent, child, grandchild].map { s in graph.withCurrent(s) { graph.makeInput(1) } }
        #expect(graph.nodeCount == 3 && graph.liveSubgraphCount == 4)
        parent.invalidate()
        #expect(graph.nodeCount == 0 && graph.liveSubgraphCount == 1)
        #expect(attributes.allSatisfy { !graph.contains($0.id) })
        #expect(![parent, child, grandchild].contains { graph.isLive($0) })
        #expect(graph.children(of: graph.rootSubgraph).isEmpty)
    }

    @Test func invalidatingAChildKeepsItsParentAndSiblingsAndDetachesIt() {
        let graph = Graph()
        let parent = graph.makeSubgraph()
        let first = graph.makeSubgraph(parent: parent), second = graph.makeSubgraph(parent: parent), third = graph.makeSubgraph(parent: parent)
        let kept = [parent, first, third].map { s in graph.withCurrent(s) { graph.makeInput(1) } }
        graph.withCurrent(second) { _ = graph.makeInput(2) }
        second.invalidate()
        #expect(graph.children(of: parent) == [first, third])
        #expect(kept.allSatisfy { graph.contains($0.id) })
        #expect(graph.nodeCount == 3)
        first.invalidate(); third.invalidate()
        #expect(graph.children(of: parent).isEmpty)
    }

    @Test func readsBetweenMembersOfTheInvalidatedSetDirtyNothingAndReadersOutsideKeepTheirCachedState() {
        let graph = Graph()
        let outside = graph.makeInput(0)
        let parent = graph.makeSubgraph(), child = graph.makeSubgraph(parent: parent)
        let inChild = graph.withCurrent(child) { graph.makeInput(1) }
        let inParent = graph.withCurrent(parent) { graph.makeRule { inChild.value + outside.value } }
        let reader = graph.makeRule { inParent.value + 1 }                 // outside the set
        _ = graph.value(of: reader)
        parent.invalidate()
        #expect(!graph.isDirty(reader.id))
        #expect(graph.inputs(of: reader.id).isEmpty)
        #expect(graph.table.outputs[Int(outside.id.index)].isEmpty)        // the dead rule left no edge behind
        #expect(graph.table.state[Int(inParent.id.index)] == 0 && graph.table.state[Int(inChild.id.index)] == 0,
                "a freed slot is not marked dirty by the members that read each other")
    }

    @Test func aSubgraphIDDoesNotResolveAfterItsSlotIsReused() {
        let graph = Graph()
        let old = graph.makeSubgraph()
        old.invalidate()
        let reborn = graph.makeSubgraph()
        #expect(reborn.id.index == old.id.index && reborn != old)
        #expect(!graph.isLive(old) && graph.isLive(reborn))
    }

    // MARK: The notice before disappearing

    @Test func theNoticeComesOnceParentsBeforeChildrenAndBeforeAnythingIsFreed() {
        let graph = Graph()
        let log = Log()
        let parent = graph.makeSubgraph()
        let first = graph.makeSubgraph(parent: parent), second = graph.makeSubgraph(parent: parent)
        let state = graph.withCurrent(first) { graph.makeInput(41) }
        for (name, subgraph) in [("parent", parent), ("first", first), ("second", second)] {
            graph.observe(subgraph) {
                log.events.append("\(name) alive=\(graph.contains(state.id))")
                if name == "first" { log.events.append("state=\(graph.value(of: state))") }
            }
        }
        parent.invalidate()
        #expect(log.events == ["parent alive=true", "second alive=true", "first alive=true", "state=41"])
        #expect(!graph.contains(state.id))
    }

    @Test func aCancelledNoticeDoesNotRun() {
        let graph = Graph()
        let log = Log()
        let sub = graph.makeSubgraph()
        let token = graph.observe(sub) { log.events.append("told") }
        token.cancel()
        sub.invalidate()
        #expect(log.events.isEmpty)
    }

    @Test func invalidatingAnotherSubgraphFromANoticeWorks() {
        let graph = Graph()
        let a = graph.makeSubgraph(), b = graph.makeSubgraph()
        graph.withCurrent(b) { _ = graph.makeInput(1) }
        graph.observe(a) { b.invalidate() }
        a.invalidate()
        #expect(!graph.isLive(b) && graph.nodeCount == 0 && graph.liveSubgraphCount == 1)
    }

    @Test func separatelyQueuedInvalidationsDetachReadersBeforeTheirNotice() {
        let graph = Graph()
        let a = graph.makeSubgraph(), b = graph.makeSubgraph()
        let tick = graph.makeInput(0)
        let source = graph.withCurrent(a) { graph.makeInput(7) }
        let reader = graph.withCurrent(b) {
            graph.makeRule { _ = tick.value; return graph.contains(source.id) ? source.value : 99 }
        }
        #expect(graph.value(of: reader) == 7)
        let log = Log()
        graph.observe(b) {
            #expect(!graph.contains(source.id))
            #expect(graph.inputs(of: reader.id) == [tick.id])
            #expect(!graph.isDirty(reader.id))
            graph.setValue(1, for: tick)
            log.events.append("value=\(graph.value(of: reader))")
        }
        let trigger = graph.makeRule { () -> Int in
            a.invalidate()
            b.invalidate()
            return 0
        }
        _ = graph.value(of: trigger)
        #expect(log.events == ["value=99"])
        #expect(graph.nodeCount == 2 && graph.liveSubgraphCount == 1)
    }

    @Test func separatelyQueuedInvalidationsDetachSourcesBeforeTheirNotice() {
        let graph = Graph()
        let a = graph.makeSubgraph(), b = graph.makeSubgraph()
        let source = graph.withCurrent(b) { graph.makeInput(7) }
        let reader = graph.withCurrent(a) { graph.makeRule { source.value } }
        _ = graph.value(of: reader)
        let log = Log()
        graph.observe(b) {
            #expect(!graph.contains(reader.id))
            #expect(graph.table.outputs[Int(source.id.index)].isEmpty)
            log.events.append("detached")
        }
        let trigger = graph.makeRule { () -> Int in
            a.invalidate()
            b.invalidate()
            return 0
        }
        _ = graph.value(of: trigger)
        #expect(log.events == ["detached"])
        #expect(graph.nodeCount == 1 && graph.liveSubgraphCount == 1)
    }

    // MARK: Invalidating from inside a rule (deferred)

    @Test func theAttributesOfASubgraphInvalidatedByARuleStayReadableUntilTheUpdateEnds() {
        let graph = Graph()
        let switcher = graph.makeInput(false)
        let branch = graph.makeSubgraph()
        let state = graph.withCurrent(branch) { graph.makeInput(7) }
        let log = Log()
        let rule = graph.makeRule { () -> Int in
            if switcher.value {
                branch.invalidate()
                log.events.append("subgraph valid right after invalidate: \(branch.isValid)")
                log.events.append("alive right after invalidate: \(graph.contains(state.id))")
                log.events.append("still readable: \(state.value)")
            }
            return 1
        }
        _ = graph.value(of: rule)
        graph.setValue(true, for: switcher)
        _ = graph.value(of: rule)
        #expect(log.events == ["subgraph valid right after invalidate: false",
                               "alive right after invalidate: true",
                               "still readable: 7"])
        #expect(!graph.contains(state.id) && !graph.isLive(branch) && !branch.isValid)
        #expect(graph.nodeCount == 2)                                      // `switcher` and `rule`
    }

    @Test func creatingInASubgraphThatIsFallingStopsTheProgram() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            let branch = graph.makeSubgraph()
            let rule = graph.makeRule { () -> Int in
                branch.invalidate()
                _ = graph.withCurrent(branch) { graph.makeInput(1) }
                return 0
            }
            _ = graph.value(of: rule)
        }
    }

    @Test func invalidatingTwiceWhileFallingDoesNothingTheSecondTime() {
        let graph = Graph()
        let branch = graph.makeSubgraph()
        graph.withCurrent(branch) { _ = graph.makeInput(1) }
        let rule = graph.makeRule { () -> Int in branch.invalidate(); branch.invalidate(); return 0 }
        _ = graph.value(of: rule)
        #expect(!graph.isLive(branch) && graph.nodeCount == 1)
    }

    @Test func invalidatingAnAlreadyFreedSubgraphStopsTheProgram() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            let sub = graph.makeSubgraph()
            sub.invalidate()
            sub.invalidate()
        }
    }

    @Test func theRootCannotBeInvalidated() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            graph.rootSubgraph.invalidate()
        }
    }

    @Test func aRuleThatInvalidatesItsOwnSubgraphReturnsItsValueAndThenDies() {
        let graph = Graph()
        let sub = graph.makeSubgraph()
        let rule = graph.withCurrent(sub) { () -> Attribute<Int> in
            graph.makeRule { () -> Int in sub.invalidate(); return 5 }
        }
        #expect(graph.value(of: rule) == 5)
        #expect(!graph.contains(rule.id) && graph.nodeCount == 0)
    }

    @Test func noticesOfADeferredInvalidationRunAfterTheUpdateNotInsideIt() {
        let graph = Graph()
        let log = Log()
        let branch = graph.makeSubgraph()
        graph.observe(branch) { log.events.append("notice") }
        let rule = graph.makeRule { () -> Int in
            branch.invalidate()
            log.events.append("rule done")
            return 0
        }
        _ = graph.value(of: rule)
        #expect(log.events == ["rule done", "notice"])
    }

    // MARK: The current subgraph while a rule runs

    /// Native parity (`NativeProbe` `cc-create-placement-caller-scope`, `cc-caller-invalidated-after-*`): evaluating a
    /// rule does not change the current subgraph, so what it creates belongs to the caller's current subgraph, not to
    /// the subgraph that owns the rule; invalidating the caller frees it, invalidating the owner does not.
    @Test func whatARuleCreatesBelongsToTheCallersCurrentSubgraph() {
        let graph = Graph()
        let owner = graph.makeSubgraph()
        let caller = graph.makeSubgraph()
        let made = Log()
        var direct: Attribute<Int>? = nil
        let rule = graph.withCurrent(owner) {
            graph.makeRule { () -> Int in
                let child = graph.makeSubgraph()
                let state = graph.withCurrent(child) { graph.makeInput(1) }
                direct = graph.makeInput(2)
                made.events.append("\(graph.parent(of: child) == caller) \(graph.subgraph(of: direct!.id) == caller) \(graph.subgraph(of: state.id) == child)")
                return 0
            }
        }
        _ = graph.withCurrent(caller) { graph.value(of: rule) }
        #expect(made.events == ["true true true"])
        #expect(graph.nodeCount == 3)
        owner.invalidate()
        #expect(graph.contains(direct!.id) && graph.nodeCount == 2)
        caller.invalidate()
        #expect(!graph.contains(direct!.id) && graph.nodeCount == 0 && graph.liveSubgraphCount == 1)
    }

    /// Design decision, not native parity: native AttributeGraph stops the program when a rule creates an attribute and
    /// no subgraph is current (`attempting to create attribute with no subgraph`); here the root subgraph is always
    /// current at top level, so a rule read from top level creates in the root.
    @Test func aRuleReadFromTopLevelCreatesInTheRootSubgraph() {
        let graph = Graph()
        let owner = graph.makeSubgraph()
        var direct: Attribute<Int>? = nil
        let rule = graph.withCurrent(owner) {
            graph.makeRule { () -> Int in
                direct = graph.makeInput(2)
                return direct!.value
            }
        }
        #expect(graph.value(of: rule) == 2)
        #expect(graph.subgraph(of: direct!.id) == graph.rootSubgraph)
        owner.invalidate()
        #expect(graph.contains(direct!.id))
    }

    /// The created attribute is an ordinary dependency of its creator: writing its input runs the created rule and then
    /// the creator again (native parity, `cc-caller-invalidated-after-rule`).
    @Test func attributesCreatedByARuleAreTrackedLikeAnyOther() {
        let graph = Graph()
        let owner = graph.makeSubgraph()
        let caller = graph.makeSubgraph()
        let y = graph.makeInput(5)
        let log = Log()
        var created: Attribute<Int>? = nil
        let r = graph.withCurrent(owner) {
            graph.makeRule { () -> Int in
                log.events.append("r")
                if created == nil {
                    created = graph.makeRule { () -> Int in log.events.append("created"); return y.value * 10 }
                }
                return created!.value + 1
            }
        }
        let outer = graph.makeRule { () -> Int in log.events.append("outer"); return r.value + 100 }
        #expect(graph.withCurrent(caller) { graph.value(of: outer) } == 151)
        #expect(log.events == ["outer", "r", "created"])
        log.events.removeAll()
        graph.setValue(6, for: y)
        #expect(graph.value(of: outer) == 161)
        #expect(log.events == ["created", "r", "outer"])
        caller.invalidate()
        #expect(!graph.contains(created!.id))
        log.events.removeAll()
        #expect(graph.value(of: outer) == 161 && log.events == [])
    }

    /// Native parity (`cc-caller-falling-input`, `cc-caller-falling-rule`, values and lifetime only): when the caller's
    /// subgraph is being invalidated in the same update, the running rule creates in its own subgraph, so the created
    /// attribute survives the caller and is freed with the rule's owner.
    @Test(arguments: [false, true])
    func creatingWhileTheCallersSubgraphIsFallingUsesTheRulesOwner(createRule: Bool) {
        let graph = Graph()
        let caller = graph.makeSubgraph()
        let owner = graph.makeSubgraph()
        let y = graph.makeInput(5)
        var created: Attribute<Int>? = nil
        var callerValidAtCreation = true
        let r = graph.withCurrent(owner) {
            graph.makeRule { () -> Int in
                if created == nil {
                    callerValidAtCreation = caller.isValid
                    created = createRule ? graph.makeRule { y.value * 10 } : graph.makeInput(10)
                }
                return created!.value + 1
            }
        }
        var armed = true
        let outer = graph.makeRule { () -> Int in
            if armed {
                armed = false
                caller.invalidate()
            }
            return r.value + 100
        }
        #expect(graph.withCurrent(caller) { graph.value(of: outer) } == (createRule ? 151 : 111))
        #expect(!callerValidAtCreation)
        #expect(graph.subgraph(of: created!.id) == owner)
        #expect(!caller.isValid && graph.contains(created!.id))
        if createRule {
            graph.setValue(6, for: y)
            #expect(graph.value(of: outer) == 161)
        }
        owner.invalidate()
        #expect(!graph.contains(created!.id))
    }

    private final class CreatedBox { var attribute: Attribute<Int>? }

    private struct CreatingResumableRule: ResumableRule {
        let box: CreatedBox
        mutating func resume(_ context: inout ResumableRuleContext<Int>) -> RuleStep {
            if box.attribute == nil { box.attribute = ThreadLocalGraph.current()!.makeInput(4) }
            switch context.poll(box.attribute!) {
            case .pending: return .needsInput(box.attribute!.erased)
            case .ready(let value): context.value = value; return .finished
            }
        }
    }

    /// The resumable path follows the same rule. No native counterpart: resumable rules exist only in this engine.
    @Test func aResumableRuleCreatesInTheCallersCurrentSubgraph() {
        let graph = Graph()
        let owner = graph.makeSubgraph()
        let caller = graph.makeSubgraph()
        let box = CreatedBox()
        let rule = graph.withCurrent(owner) { graph.makeResumableRule(CreatingResumableRule(box: box)) }
        #expect(graph.withCurrent(caller) { graph.value(of: rule) } == 4)
        #expect(graph.subgraph(of: box.attribute!.id) == caller)
        caller.invalidate()
        #expect(!graph.contains(box.attribute!.id))
    }

    @Test func theCurrentSubgraphIsRestoredAfterARuleRuns() {
        let graph = Graph()
        let sub = graph.makeSubgraph()
        let rule = graph.withCurrent(sub) { graph.makeRule { 1 } }
        let other = graph.makeSubgraph()
        graph.withCurrent(other) {
            _ = graph.value(of: rule)
            #expect(graph.subgraph(of: graph.makeInput(0).id) == other)
        }
    }

    @Test func aRuleThatIsRunningFromAFallingSubgraphDoesNotCreateInsideIt() {
        // The rule of a falling subgraph can still run in the same update; it is read from top level, so what it creates
        // goes to the caller's current subgraph (the root), never into the falling owner.
        let graph = Graph()
        let branch = graph.makeSubgraph()
        let tick = graph.makeInput(0)
        let kept = Log()
        let inside = graph.withCurrent(branch) {
            graph.makeRule { () -> Int in
                let a = graph.makeInput(9)
                kept.events.append("\(graph.subgraph(of: a.id) == graph.rootSubgraph)")
                return tick.value
            }
        }
        let invalidator = graph.makeRule { () -> Int in
            _ = tick.value
            branch.invalidate()
            return graph.value(of: inside)
        }
        _ = graph.value(of: invalidator)
        #expect(kept.events == ["true"])
    }

    @Test func aNestedRuleOfTheSameFallingOwnerCreatesInTheLiveAncestor() async {
        await #expect(processExitsWith: .success) {
            let graph = Graph()
            let sub = graph.makeSubgraph()
            let inner = graph.withCurrent(sub) {
                graph.makeRule { () -> Int in
                    let made = graph.makeInput(9)
                    let child = graph.makeSubgraph()
                    precondition(graph.subgraph(of: made.id) == graph.rootSubgraph)
                    precondition(graph.parent(of: child) == graph.rootSubgraph)
                    return made.value
                }
            }
            let outer = graph.withCurrent(sub) {
                graph.makeRule { () -> Int in
                    sub.invalidate()
                    return inner.value
                }
            }
            precondition(graph.value(of: outer) == 9)
            precondition(!graph.isLive(sub))
            precondition(graph.nodeCount == 1 && graph.liveSubgraphCount == 2)
        }
    }

    // MARK: C28 — AttributeFlags and Subgraph flag operations

    @Test func attributeFlagsAndSubgraphFlagQueriesAndUpdateFollowReverseCreationOrder() {
        let graph = Graph()
        let root = graph.rootSubgraph
        let c1 = graph.makeSubgraph(parent: root)
        let c2 = graph.makeSubgraph(parent: root)
        let flag0 = AttributeFlags(rawValue: 1 << 0)
        let flag1 = AttributeFlags(rawValue: 1 << 1)
        let log = Log()

        func makeTracked(_ sub: Subgraph, _ name: String, _ flag: AttributeFlags) -> Attribute<Int> {
            graph.withCurrent(sub) {
                let r = graph.makeRule { log.events.append(name); return 1 }
                graph.setFlags(flag, for: r)
                return r
            }
        }

        let a1 = makeTracked(root, "a1", flag0)
        let a2 = makeTracked(root, "a2", flag0)
        let b1 = makeTracked(c1, "b1", flag0)
        let b2 = makeTracked(c1, "b2", flag0)
        let d1 = makeTracked(c2, "d1", flag0)
        let d2 = makeTracked(c2, "d2", flag1)

        #expect(graph.flags(of: a1) == flag0)
        #expect(graph.flags(of: d2) == flag1)
        #expect(graph.intersects(root, flags: flag0))
        #expect(graph.intersects(c1, flags: flag0))
        #expect(!graph.intersects(c1, flags: flag1))
        #expect(graph.intersects(c2, flags: flag1))
        #expect(graph.isDirty(root, flags: flag0))
        #expect(graph.isDirty(c2, flags: flag1))

        var visited: [AttributeID] = []
        graph.forEach(in: root, flags: flag0) { visited.append($0.id) }
        // Reverse creation order within each subgraph (`a2, a1`), then child subgraphs in reverse creation order (`c2`, then `c1`).
        #expect(visited == [a2.id, a1.id, d1.id, b2.id, b1.id])

        graph.update(root, flags: flag0)
        #expect(log.events == ["a2", "a1", "d1", "b2", "b1"])
        #expect(!graph.isDirty(root, flags: flag0))
        #expect(graph.isDirty(root, flags: flag1))

        graph.update(root, flags: flag1)
        #expect(log.events == ["a2", "a1", "d1", "b2", "b1", "d2"])
        #expect(!graph.isDirty(root, flags: .all))
    }

    @Test func isDirtyRemainsSetAfterReadUntilSubgraphUpdate() {
        let graph = Graph()
        let sg = graph.makeSubgraph()
        let node = graph.withCurrent(sg) { graph.makeRule { 10 } }
        graph.setFlags(AttributeFlags(rawValue: 1), for: node)
        let consumer = graph.withCurrent(sg) { graph.makeRule { node.value + 1 } }

        #expect(graph.value(of: consumer) == 11)
        #expect(graph.isDirty(sg, flags: AttributeFlags(rawValue: 1)))

        graph.invalidateValue(of: node)
        #expect(graph.isDirty(sg, flags: AttributeFlags(rawValue: 1)))
        #expect(graph.value(of: consumer) == 11)
        #expect(graph.isDirty(sg, flags: AttributeFlags(rawValue: 1)))

        graph.update(sg, flags: AttributeFlags(rawValue: 1))
        #expect(!graph.isDirty(sg, flags: AttributeFlags(rawValue: 1)))
    }

    // MARK: C30 — withoutSubgraphInvalidation and isAncestor

    @Test func isAncestorAndWithoutSubgraphInvalidationDeferFreeingUntilScopeEnds() {
        let graph = Graph()
        let root = graph.rootSubgraph
        let parent = graph.makeSubgraph(parent: root)
        let child = graph.makeSubgraph(parent: parent)
        let sibling = graph.makeSubgraph(parent: root)

        #expect(graph.isAncestor(root, of: root))
        #expect(graph.isAncestor(root, of: parent))
        #expect(graph.isAncestor(root, of: child))
        #expect(graph.isAncestor(parent, of: child))
        #expect(!graph.isAncestor(child, of: parent))
        #expect(!graph.isAncestor(parent, of: sibling))

        let target = graph.withCurrent(child) { graph.makeInput(42) }
        let weakTarget = WeakAttribute(target)
        let log = Log()
        graph.observe(child) { log.events.append("child invalidated") }

        graph.withoutSubgraphInvalidation {
            child.invalidate()
            // Immediately marked invalid (`isValid == false`), while its attributes remain alive until the scope ends.
            #expect(!child.isValid)
            #expect(graph.contains(target.id))
            #expect(graph.value(of: weakTarget) == 42)
            #expect(log.events.isEmpty)
        }

        // Freed as soon as the outermost `withoutSubgraphInvalidation` scope exits.
        #expect(log.events == ["child invalidated"])
        #expect(!graph.contains(target.id))
        #expect(graph.value(of: weakTarget) == nil)
    }
}
