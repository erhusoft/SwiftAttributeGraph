import Testing
@testable import SwiftAttributeGraph

/// A minimal vertical probe: a test harness that imitates the AttributeGraph patterns the SwiftUICore reports (F2 to
/// F8) found, using only the public API of the engine. It is not a view framework: there are no views, no layout and
/// no drawing. Each test says what the harness had to improvise; the findings are collected in
/// `PRUEBA_VERTICAL_MOTOR.md`.
@Suite struct HostPatternTests {

    // MARK: Harness

    /// A reference counter that closures can share.
    final class Counter { var n = 0 }

    /// `ClearUpdate; GetCurrent; SetCurrent(new); <create attributes>; SetCurrent(previous); SetUpdate` (the owner
    /// pattern of 70 of the 78 functions of F4). `Subgraph.current` is `nil` when nothing is current, so the harness
    /// falls back to the root subgraph to restore something valid.
    static func inScope<T>(_ graph: Graph, _ subgraph: Subgraph, _ body: () -> T) -> T {
        let token = Graph.clearUpdate()
        let previous = Subgraph.current ?? graph.rootSubgraph
        Subgraph.current = subgraph
        defer {
            Subgraph.current = previous
            Graph.setUpdate(token)
        }
        return body()
    }

    /// `Create; AddChild(parent, child)` followed by the scoped creation of the content.
    static func makeChild<T>(_ graph: Graph, of parent: Subgraph, addChild: Bool = true, _ build: () -> T) -> (Subgraph, T) {
        let child = graph.makeSubgraph(parent: parent)
        if addChild { graph.addChild(child, to: parent) }       // idempotent: makeSubgraph(parent:) already linked it [O, test 3]
        let content = inScope(graph, child, build)
        return (child, content)
    }

    struct Env: Equatable {
        var scale = 1
        var scheme = 0
        var name = "a"
    }

    // MARK: Case 1: minimal host

    /// The seven external root attributes of `GraphHost.Data` (F2 §1.1), an update callback, and a transaction that
    /// writes inputs and raises `setNeedsUpdate` itself.
    final class Host {
        let graph = Graph()
        let calls = Counter()
        let global: Subgraph
        let time: Attribute<Int>
        let environment: Attribute<Env>
        let transaction: Attribute<Int>
        let viewSeed: Attribute<Int>
        let propertySeed: Attribute<Int>
        let preferenceSeed: Attribute<Int>
        let size: Attribute<Int>
        let output: Attribute<String>
        private var pending: [() -> Void] = []

        init() {
            let graph = self.graph
            global = graph.makeSubgraph(parent: graph.rootSubgraph)
            let made = HostPatternTests.inScope(graph, global) {
                (graph.makeInput(0), graph.makeInput(Env(), comparison: .equatableUnlessPOD), graph.makeInput(0),
                 graph.makeInput(0), graph.makeInput(0), graph.makeInput(0), graph.makeInput(0))
            }
            (time, environment, transaction, viewSeed, propertySeed, preferenceSeed, size) = made
            let (t, e, x, s) = (made.0, made.1, made.2, made.3)
            output = HostPatternTests.inScope(graph, global) {
                graph.makeRule({ "t\(t.value)s\(e.value.scale)x\(x.value)v\(s.value)" }, comparison: .equatableUnlessPOD)
            }
            let calls = self.calls
            graph.setUpdateCallback { calls.n += 1 }
        }

        /// How a state write enters this harness: the core receives it through `AGGraphSetInvalidationCallback`
        /// (`graphInvalidation` -> `asyncTransaction`), which the engine does not have [O, F2 §2]. The harness queues
        /// the write and applies it when the transaction is committed.
        func write(_ body: @escaping () -> Void) { pending.append(body) }

        /// One transaction: apply the queued writes, then raise `setNeedsUpdate` explicitly, as
        /// `ViewRendererHost.invalidateProperties` does (the single call site of `SetNeedsUpdate`, F2 §2.1).
        func commit() {
            let writes = pending
            pending = []
            for write in writes { write() }
            graph.setNeedsUpdate()
        }
    }

    @Test func aTransactionWritesInputsAndRaisesNeedsUpdateAndTheCallbackDrainsOnTheFirstRuleRead() {
        let host = Host()
        let graph = host.graph
        #expect(graph.value(of: host.output) == "t0s1x0v0")
        #expect(host.calls.n == 0, "no flag, no callback")

        host.write { graph.setValue(5, for: host.time) }
        host.write { graph.setValue(Env(scale: 2), for: host.environment) }
        host.write { graph.setValue(1, for: host.transaction) }
        host.commit()
        #expect(host.calls.n == 0, "setNeedsUpdate does not call back by itself")
        #expect(graph.counter(for: .needsUpdate) == 1)

        #expect(graph.value(of: host.time) == 5)
        #expect(host.calls.n == 0, "reading an input drains nothing (native [O], task A)")
        #expect(graph.counter(for: .needsUpdate) == 1)

        #expect(graph.value(of: host.output) == "t5s2x1v0")
        #expect(host.calls.n == 1, "the first top-level rule read drains the callback")
        #expect(graph.counter(for: .needsUpdate) == 0)
        _ = graph.value(of: host.output)
        #expect(host.calls.n == 1, "once")

        // A write without setNeedsUpdate never raises the flag: the core does not either, it goes through the
        // invalidation callback, which the engine lacks.
        graph.setValue(9, for: host.time)
        #expect(graph.value(of: host.output) == "t9s2x1v0")
        #expect(host.calls.n == 1)
    }

    // MARK: Case 2: environment

    /// One environment attribute for the whole graph; the key-level cut is policy of the harness (the `Tracker`
    /// pattern of F5 §3): each reader remembers the value of the key it used and only runs its body if that changed.
    @Test func environmentReadersRerunTheirRuleButOnlyTheBodyOfTheKeyThatChangedCutsDownstream() {
        let graph = Graph()
        let scope = graph.makeSubgraph(parent: graph.rootSubgraph)
        let env = HostPatternTests.inScope(graph, scope) { graph.makeInput(Env(), comparison: .equatableUnlessPOD) }

        final class Counts { var rule = 0, body = 0, consumer = 0 }
        final class Memo<K> { var last: K?; var cached = 0 }

        func reader<K: Equatable>(_ key: KeyPath<Env, K>, _ counts: Counts, _ transform: @escaping (K) -> Int)
            -> Attribute<Int> {
            let memo = Memo<K>()
            return HostPatternTests.inScope(graph, scope) {
                let output = graph.makeRule({ () -> Int in
                    counts.rule += 1
                    let used = env.value[keyPath: key]
                    if let last = memo.last, last == used { return memo.cached }
                    counts.body += 1
                    memo.last = used
                    memo.cached = transform(used)
                    return memo.cached
                }, comparison: .equatableUnlessPOD)
                return output
            }
        }
        func consumer(_ source: Attribute<Int>, _ counts: Counts) -> Attribute<Int> {
            HostPatternTests.inScope(graph, scope) {
                graph.makeRule({ counts.consumer += 1; return source.value + 1 }, comparison: .equatableUnlessPOD)
            }
        }

        let (cs, cx, cn) = (Counts(), Counts(), Counts())
        let scale = reader(\.scale, cs) { $0 * 10 }
        let scheme = reader(\.scheme, cx) { $0 + 100 }
        let name = reader(\.name, cn) { $0.count }
        let consumers = [consumer(scale, cs), consumer(scheme, cx), consumer(name, cn)]
        func readAll() { for c in consumers { _ = graph.value(of: c) } }
        func snapshot() -> [Int] { [cs, cx, cn].flatMap { [$0.rule, $0.body, $0.consumer] } }

        readAll()
        #expect(snapshot() == [1, 1, 1,  1, 1, 1,  1, 1, 1])

        graph.setValue(Env(scale: 2), for: env)
        readAll()
        #expect(snapshot() == [2, 2, 2,  2, 1, 1,  2, 1, 1],
                "every reader rule reruns (they read the whole attribute), only the changed key reruns body and consumer [O]")

        graph.setValue(Env(scale: 2, name: "abc"), for: env)
        readAll()
        #expect(snapshot() == [3, 2, 2,  3, 1, 1,  3, 2, 2])

        graph.setValue(Env(scale: 2, name: "abc"), for: env)
        readAll()
        #expect(snapshot() == [3, 2, 2,  3, 1, 1,  3, 2, 2], "an equal environment is cut at the input (equatableUnlessPOD uses ==)")
    }

    // MARK: Case 3: dynamic container

    @Test func dynamicContainerCreatesChildrenWithTheCorePatternAndReturnsToTheBase() {
        let graph = Graph()
        let base = graph.nodeCount
        let baseSubgraphs = graph.liveSubgraphCount
        let parent = graph.makeSubgraph(parent: graph.rootSubgraph)
        let source = HostPatternTests.inScope(graph, parent) { graph.makeInput(1) }

        var children: [Subgraph] = []
        var outputs: [Attribute<Int>] = []
        for i in 0..<4 {
            let (child, output) = HostPatternTests.makeChild(graph, of: parent) {
                let local = graph.makeInput(i)
                return graph.makeRule { local.value + source.value }
            }
            children.append(child)
            outputs.append(output)
        }
        let container = HostPatternTests.inScope(graph, parent) {
            graph.makeRule { outputs.reduce(0) { $0 + $1.value } }
        }
        #expect(graph.value(of: container) == 10)
        #expect(graph.nodeCount == base + 1 + 1 + 4 * 2)
        #expect(graph.inputCount(of: container.id) == 4)
        for child in children { #expect(graph.isAncestor(parent, of: child)) }

        // Immediate removal: Apply + Invalidate.
        graph.invalidate(children[3])
        #expect(!graph.isValid(children[3]))
        #expect(graph.nodeCount == base + 1 + 1 + 3 * 2)
        #expect(graph.inputCount(of: container.id) == 3, "no dangling edge to the freed child [O]")
        #expect(graph.value(of: container) == 10, "the container keeps its cached value until another input dirties it")
        // Rewriting `source` and reading `container` would read the freed child handle again: a dead handle is a
        // precondition failure, so the harness must rebuild the list of live children first (see the report).
    }

    @Test func deferredRemovalKeepsTheChildAliveAndItCanBeReinserted() {
        let graph = Graph()
        let base = graph.nodeCount
        let baseSubgraphs = graph.liveSubgraphCount
        let parent = graph.makeSubgraph(parent: graph.rootSubgraph)
        var children: [Subgraph] = []
        var outputs: [Attribute<Int>] = []
        for i in 0..<3 {
            let (child, output) = HostPatternTests.makeChild(graph, of: parent) {
                let local = graph.makeInput(i)
                return graph.makeRule { local.value * 2 }
            }
            children.append(child)
            outputs.append(output)
        }
        let nodes = graph.nodeCount
        #expect(nodes == base + 3 * 2)

        graph.removeChild(children[1], from: parent)
        #expect(graph.isValid(children[1]) && graph.nodeCount == nodes, "deferred: nothing freed, content readable")
        #expect(graph.value(of: outputs[1]) == 2)
        #expect(!graph.isAncestor(parent, of: children[1]))

        graph.addChild(children[1], to: parent)             // reinsertion
        #expect(graph.isAncestor(parent, of: children[1]))

        graph.removeChild(children[2], from: parent)
        graph.invalidate(parent)
        #expect(graph.isValid(children[2]), "the removed child is an orphan: invalidating the parent does not reach it [O]")
        #expect(graph.nodeCount == base + 2, "only the orphan's nodes remain")
        graph.invalidate(children[2])
        #expect(graph.nodeCount == base)
        #expect(graph.liveSubgraphCount == baseSubgraphs)
        #expect(graph.edgeCount == 0)
    }

    // MARK: Case 4: preferences

    struct Combiner: Rule {
        var children: [WeakAttribute<Int>]
        let runs: Counter
        let order: Counter?
        var value: [Int] {
            runs.n += 1
            return children.compactMap { $0.value }          // in array order; a dead weak is skipped
        }
    }

    @Test func aWeakCombinerIsNotRerunByTheInvalidationOfAChildButIsByAnExplicitMutation() {
        let graph = Graph()
        let base = graph.nodeCount
        let parent = graph.makeSubgraph(parent: graph.rootSubgraph)
        var subgraphs: [Subgraph] = []
        var weaks: [WeakAttribute<Int>] = []
        for i in 1...3 {
            let (child, output) = HostPatternTests.makeChild(graph, of: parent) { graph.makeRule { i * 10 } }
            subgraphs.append(child)
            weaks.append(WeakAttribute(output))
        }
        let runs = Counter()
        let combiner = HostPatternTests.inScope(graph, parent) {
            graph.makeRule(Combiner(children: weaks, runs: runs, order: nil), comparison: .equatableUnlessPOD)
        }
        #expect(graph.value(of: combiner) == [10, 20, 30])
        #expect(runs.n == 1)

        graph.invalidate(subgraphs[1])
        #expect(weaks[1].id.map { !graph.isLiveForTest($0) } ?? true)
        #expect(graph.value(of: weaks[1]) == nil, "the weak of an invalidated child reads nil [O]")
        #expect(graph.value(of: combiner) == [10, 20, 30], "native: not rerun by dependency, keeps the stale value [O, weak-combiner-three-children-invalidate-middle]")
        #expect(runs.n == 1)

        // HostPreferencesCombiner.removeChild: AGGraphMutateAttribute(invalidating = 1).
        graph.mutateBody(of: combiner, as: Combiner.self, invalidating: true) { $0.children.remove(at: 1) }
        #expect(graph.value(of: combiner) == [10, 30])
        #expect(runs.n == 2)

        // Even without removing the dead weak, an explicit invalidation recomputes it in order, skipping the nil.
        let stale = HostPatternTests.inScope(graph, parent) {
            graph.makeRule(Combiner(children: weaks, runs: runs, order: nil), comparison: .equatableUnlessPOD)
        }
        #expect(graph.value(of: stale) == [10, 30])

        graph.invalidate(parent)
        #expect(graph.nodeCount == base)
    }

    // MARK: Case 5: display list item and layout

    final class LayoutComputer { let tag: Int; init(_ tag: Int) { self.tag = tag } }
    struct Point: Equatable { var x = 0, y = 0 }
    struct Item: Equatable { var position: Point; var seed: Int }

    @Test func anItemRuleKeepsItsSeedWhenOnlyThePositionMovesAndMeasuresOutsideTheRule() {
        let graph = Graph()
        let base = graph.nodeCount
        let scope = graph.makeSubgraph(parent: graph.rootSubgraph)
        let seeds = Counter(), layoutBuilds = Counter()
        let (position, container, view, unrelated) = HostPatternTests.inScope(graph, scope) {
            (graph.makeInput(Point(), comparison: .equatableUnlessPOD), graph.makeInput(Point(), comparison: .equatableUnlessPOD),
             graph.makeInput(1), graph.makeInput(0))
        }
        // The LayoutComputer: a stateful rule that makes a new object only when the view changes; compared by identity.
        let layout = HostPatternTests.inScope(graph, scope) {
            graph.makeStatefulRule(comparison: .equatableUnlessPOD) { (ctx: inout RuleContext<LayoutComputer>) in
                _ = unrelated.value                                   // reruns when the unrelated input changes
                let (v, changed) = ctx.changedValue(of: view)
                if changed || !ctx.hasValue {
                    layoutBuilds.n += 1
                    ctx.value = LayoutComputer(v)
                }
            }
        }
        // ENGINE BUG found by this harness [O]: `Graph.inputValue(of:for:)` from outside a rule crashes (index out of
        // range, later, on propagation) when the measured source has a LOWER index than the last edge of the reader:
        // the middle-insertion branch of `recordRead(of:by:keepForNextPrune:)` appends `evaluatingNode` (noNode outside a
        // rule) instead of `consumerNode` to `outputs`, and drops `keepForNextPrune`. The measured input is therefore
        // created after the layout rule so that its edge is appended at the end (the correct branch).
        let size = HostPatternTests.inScope(graph, scope) { graph.makeInput(100) }
        let item = HostPatternTests.inScope(graph, scope) {
            graph.makeStatefulRule(comparison: .equatableUnlessPOD) { (ctx: inout RuleContext<Item>) in
                let p = position.value
                _ = container.value
                let l = layout.value
                if ctx.anyInputsChanged(excluding: [position.erased, container.erased]) {
                    seeds.n += 1
                    ctx.value = Item(position: p, seed: l.tag * 1000 + seeds.n)
                } else {
                    ctx.value.position = p
                }
            }
        }
        func version(_ a: AnyAttribute) -> UInt32 { graph.table.versions[Int(a.id.index)] }

        #expect(graph.value(of: item) == Item(position: Point(), seed: 1001))
        let (v0, l0) = (version(item.erased), version(layout.erased))
        #expect(seeds.n == 1 && layoutBuilds.n == 1)

        graph.setValue(Point(x: 5, y: 5), for: position)
        #expect(graph.value(of: item) == Item(position: Point(x: 5, y: 5), seed: 1001), "the seed is kept")
        #expect(seeds.n == 1)
        #expect(version(item.erased) > v0, "the item version rises: its position changed")

        graph.setValue(Point(x: 9, y: 9), for: container)
        #expect(graph.value(of: item) == Item(position: Point(x: 5, y: 5), seed: 1001))
        #expect(seeds.n == 1, "the container position is excluded too")

        graph.setValue(1, for: unrelated)                             // layout reruns, returns the same object
        _ = graph.value(of: item)
        #expect(version(layout.erased) == l0, "same LayoutComputer reference: compared by identity, no version change [O]")
        #expect(seeds.n == 1 && layoutBuilds.n == 1)

        graph.setValue(2, for: view)
        #expect(graph.value(of: item).seed == 2002 , "a new view rebuilds the seed")
        #expect(layoutBuilds.n == 2 && seeds.n == 2)
        #expect(version(layout.erased) > l0)

        // LayoutProxy.size: an explicit read outside any rule, recorded against the item as reader (GetInputValue).
        let before = graph.inputCount(of: item.id)
        #expect(graph.inputValue(of: size, for: item.erased) == 100)
        #expect(graph.inputCount(of: item.id) == before + 1, "the edge belongs to the item although no rule is running [O]")
        graph.setValue(120, for: size)
        let runsBefore = seeds.n
        _ = graph.value(of: item)
        #expect(seeds.n == runsBefore + 1, "the measured input is a real dependency of the item (it reran and anyInputsChanged saw it)")

        graph.invalidate(scope)
        #expect(graph.nodeCount == base)
    }

    // MARK: Depth

    @Test func aChainOfTwentyThousandNestedSubgraphsIsBuiltPropagatedAndFreedWithoutRecursion() {
        let depth = 20_000
        let graph = Graph()
        let base = graph.nodeCount
        let baseSubgraphs = graph.liveSubgraphCount
        // Without the explicit `addChild` on purpose: `addChild` runs a cycle check that walks the ancestors, so it is
        // O(depth) per call (46 s in debug for this chain with it, 0.3 s without) [O].
        let top = graph.makeSubgraph(parent: graph.rootSubgraph)
        let root = HostPatternTests.inScope(graph, top) { graph.makeInput(0) }
        var parent = top
        var last = root
        var firstChild: Subgraph?
        for _ in 0..<depth {
            let previous = last
            let (child, next) = HostPatternTests.makeChild(graph, of: parent, addChild: false) { graph.makeRule { previous.value + 1 } }
            _ = graph.value(of: next)                  // warm node by node (the cold chain nests: DepthTests)
            firstChild = firstChild ?? child
            parent = child
            last = next
        }
        #expect(graph.value(of: last) == depth)
        graph.setValue(5, for: root)
        #expect(graph.value(of: last) == depth + 5)
        #expect(graph.liveSubgraphCount == baseSubgraphs + depth + 1)

        graph.invalidate(top)
        #expect(graph.nodeCount == base)
        #expect(graph.liveSubgraphCount == baseSubgraphs)
    }
}

extension Graph {
    /// Whether the attribute is still in the table (test helper).
    func isLiveForTest(_ id: AttributeID) -> Bool { table.isLive(id) }
}
