import Testing
import SwiftAttributeGraph
@testable import ShellUI

private final class BodyCounts {
    var selected = 0
    var independent = 0
}

private struct SelectedLabel: View {
    @Binding var first: Int
    @Binding var second: Int
    @Binding var alternate: Bool
    let counts: BodyCounts

    var body: Text {
        counts.selected += 1
        return Text("\(alternate ? second : first)")
    }
}

private struct IndependentLabel: View {
    let counts: BodyCounts
    var body: Text {
        counts.independent += 1
        return Text("fixed")
    }
}

extension SliceTests {
    @Test func buttonBindingLazyBodiesAndBranchDependencyPruning() {
        let graph = Graph()
        let scope = ViewGraphScope(graph: graph)
        let first = State(wrappedValue: 0)
        let second = State(wrappedValue: 100)
        let alternate = State(wrappedValue: false)
        first.install(in: scope)
        second.install(in: scope)
        alternate.install(in: scope)
        let counts = BodyCounts()
        let selected = scope.mount(SelectedLabel(first: first.projectedValue, second: second.projectedValue,
                                                alternate: alternate.projectedValue, counts: counts))
        let independent = scope.mount(IndependentLabel(counts: counts))
        let increment = Button("Increment") { first.projectedValue.wrappedValue += 1 }
        let flip = Button("Switch") { alternate.projectedValue.wrappedValue.toggle() }
        #expect(counts.selected == 0 && counts.independent == 0)
        #expect(graph.value(of: selected).content == "0")
        _ = graph.value(of: independent)
        increment.activate()
        #expect(counts.selected == 1) // writes do not eagerly evaluate a body
        #expect(graph.value(of: selected).content == "1")
        _ = graph.value(of: independent)
        #expect(counts.selected == 2 && counts.independent == 1)
        first.wrappedValue = 1
        _ = graph.value(of: selected)
        #expect(counts.selected == 2)
        flip.activate()
        #expect(graph.value(of: selected).content == "100")
        #expect(counts.selected == 3)
        #expect(graph.outputCount(of: first.attributeID!) == 0)
        #expect(graph.outputCount(of: second.attributeID!) == 1)
        increment.activate() // the inactive branch must no longer invalidate the body
        #expect(graph.value(of: selected).content == "100")
        #expect(counts.selected == 3)
        second.projectedValue.wrappedValue = 101
        #expect(graph.value(of: selected).content == "101")
        #expect(counts.selected == 4)
        flip.activate()
        #expect(graph.value(of: selected).content == "2")
        #expect(counts.selected == 5 && counts.independent == 1)
        scope.unmount()
        #expect(graph.nodeCount == 0 && graph.edgeCount == 0 && graph.liveSubgraphCount == 1)
    }

    @Test func replacingBranchesReleasesStateAndReinitializesItOnRemount() {
        let graph = Graph()
        let screen = ViewGraphScope(graph: graph)
        let baseline = graph.nodeCount
        for _ in 0..<100 {
            let branch = ViewGraphScope(graph: graph, parent: screen.owner)
            let state = State(wrappedValue: 7)
            state.install(in: branch)
            let counts = BodyCounts()
            let body = branch.mount(SelectedLabel(first: state.projectedValue, second: state.projectedValue,
                alternate: Binding(get: { false }, set: { _ in }), counts: counts))
            #expect(graph.value(of: body).content == "7")
            state.wrappedValue = 8
            #expect(graph.value(of: body).content == "8")
            branch.unmount()
            #expect(graph.nodeCount == baseline)
            #expect(graph.liveSubgraphCount == 2)
        }
        screen.unmount()
        #expect(graph.nodeCount == 0 && graph.liveSubgraphCount == 1)
    }

    @Test func stateCopiesShareStorageAndUnmountReleasesCapturedObjects() {
        final class Token {}
        let graph = Graph()
        let scope = ViewGraphScope(graph: graph)
        var token: Token? = Token()
        weak var weakToken = token
        var state: State<Token>? = State(wrappedValue: token!)
        state!.install(in: scope)
        let copy = state!
        #expect(copy.wrappedValue === token)
        token = nil
        state = nil
        #expect(weakToken != nil)
        scope.unmount()
        #expect(weakToken == nil) // even a retained wrapper must not retain its old initial value
        #expect(graph.nodeCount == 0)
    }

    @Test func PerformanceVerticalSliceUpdates() {
        let graph = Graph()
        let scope = ViewGraphScope(graph: graph)
        let first = State(wrappedValue: 0), second = State(wrappedValue: 100)
        let alternate = State(wrappedValue: false)
        first.install(in: scope); second.install(in: scope); alternate.install(in: scope)
        let counts = BodyCounts()
        let body = scope.mount(SelectedLabel(first: first.projectedValue, second: second.projectedValue,
            alternate: alternate.projectedValue, counts: counts))
        _ = graph.value(of: body)
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for i in 1...10_000 {
                first.projectedValue.wrappedValue = i
                _ = graph.value(of: body)
            }
        }
        #expect(counts.selected == 10_001)
        scope.unmount()
        #expect(graph.nodeCount == 0)
        print("VerticalSlice: 10000 binding writes + body + Text: \(elapsed)")
    }
}

extension SliceTests {
    @Test func twentyThousandNestedScopesUnmountWithoutRecursiveTraversal() {
        let graph = Graph()
        let screen = ViewGraphScope(graph: graph)
        var parent = screen.owner
        var scopes: [ViewGraphScope] = []
        for _ in 0..<20_000 {
            let scope = ViewGraphScope(graph: graph, parent: parent)
            let state = State(wrappedValue: 1)
            state.install(in: scope)
            scopes.append(scope)
            parent = scope.owner
        }
        #expect(graph.nodeCount == 20_000)
        screen.unmount()
        #expect(graph.nodeCount == 0 && graph.liveSubgraphCount == 1)
        for scope in scopes { scope.unmount() } // ancestor invalidation must mark descendants dead too
    }

    @Test func retainedBindingCannotAccessAnUnmountedState() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            let scope = ViewGraphScope(graph: graph)
            let state = State(wrappedValue: 1)
            state.install(in: scope)
            let binding = state.projectedValue
            scope.unmount()
            _ = binding.wrappedValue
        }
    }
}

private struct BranchScreen: View {
    @Binding var alternate: Bool
    @ViewBuilder var body: _ConditionalContent<Text, Text> {
        if alternate { Text("second") } else { Text("first") }
    }
}

extension SliceTests {
    @Test func structuralIfBuildsNewStateBeforeReleasingTheOldBranch() {
        let graph = Graph()
        let screen = ViewGraphScope(graph: graph)
        let alternate = State(wrappedValue: false)
        alternate.install(in: screen)
        let root = screen.mount(BranchScreen(alternate: alternate.projectedValue))
        let flip = Button("Switch") { alternate.wrappedValue.toggle() }
        var oldBranch: ViewGraphScope?
        var oldState: State<Int>?
        for index in 0..<100 {
            let selection = graph.value(of: root)
            switch selection.storage {
            case .first(let text): #expect(index % 2 == 1 && text.content == "second")
            case .second(let text): #expect(index % 2 == 0 && text.content == "first")
            }
            // Fixed-shape experimental reconciliation: construct the new branch, then dispose the old one.
            let branch = ViewGraphScope(graph: graph, parent: screen.owner)
            let state = State(wrappedValue: 7)
            state.install(in: branch)
            let body = branch.mount(SelectedLabel(first: state.projectedValue, second: state.projectedValue,
                alternate: Binding(get: { false }, set: { _ in }), counts: BodyCounts()))
            #expect(graph.value(of: body).content == "7")
            if let oldState { #expect(oldState.wrappedValue == 8) }
            oldBranch?.unmount()
            #expect(graph.nodeCount == 4) // screen state + root body + branch state + branch body
            #expect(graph.liveSubgraphCount == 3)
            state.wrappedValue = 8
            #expect(graph.value(of: body).content == "8")
            oldBranch = branch
            oldState = state
            flip.activate()
        }
        screen.unmount()
        #expect(graph.nodeCount == 0 && graph.edgeCount == 0 && graph.liveSubgraphCount == 1)
    }
}
