#if os(macOS)
import AppKit
import SwiftUI
import Testing
import SwiftAttributeGraph
@testable import ShellUI

private enum ConstructionMode: String, CaseIterable {
    case closureDiscarded, closureUnread, closureRead, projectedDiscarded, projectedUnread, projectedRead
}

@MainActor private final class OwnerTrace {
    var owner = 0
    var child = 0
    var gets = 0
    var value = ""
    var first: ((Int) -> Void)?
    var second: ((Int) -> Void)?
    var flip: (() -> Void)?
    var replaceChild: (() -> Void)?
    var replaceOwner: (() -> Void)?
    func clear() { first = nil; second = nil; flip = nil; replaceChild = nil; replaceOwner = nil }
}

@MainActor private struct OwnerConsumer: SwiftUI.View {
    @SwiftUI.Binding var first: Int
    @SwiftUI.Binding var second: Int
    @SwiftUI.Binding var alternate: Bool
    let trace: OwnerTrace
    var body: some SwiftUI.View {
        trace.child += 1
        trace.value = String(alternate ? second : first)
        return SwiftUI.Text(trace.value)
    }
}

@MainActor private struct StateOwner: SwiftUI.View {
    @SwiftUI.State private var first = 0
    @SwiftUI.State private var second = 100
    @SwiftUI.State private var alternate = false
    @SwiftUI.State private var generation = 0
    let trace: OwnerTrace
    var body: some SwiftUI.View {
        trace.owner += 1
        let a = $first, b = $second, flag = $alternate, childID = $generation
        return OwnerConsumer(first: a, second: b, alternate: flag, trace: trace)
            .id(generation).onAppear {
                trace.first = { a.wrappedValue = $0 }
                trace.second = { b.wrappedValue = $0 }
                trace.flip = { flag.wrappedValue.toggle() }
                trace.replaceChild = { childID.wrappedValue += 1 }
            }
    }
}

@MainActor private struct OwnerContainer: SwiftUI.View {
    @SwiftUI.State private var generation = 0
    let trace: OwnerTrace
    var body: some SwiftUI.View {
        let identity = $generation
        return StateOwner(trace: trace).id(generation).onAppear {
            trace.replaceOwner = { identity.wrappedValue += 1 }
        }
    }
}

@MainActor private struct ConstructionConsumer: SwiftUI.View {
    @SwiftUI.Binding var value: Int
    let read: Bool
    let trace: OwnerTrace
    var body: some SwiftUI.View {
        trace.child += 1
        trace.value = read ? String(value) : "fixed"
        return SwiftUI.Text(trace.value)
    }
}

@MainActor private struct ConstructionOwner: SwiftUI.View {
    @SwiftUI.State private var value = 0
    let mode: ConstructionMode
    let trace: OwnerTrace
    var body: some SwiftUI.View {
        trace.owner += 1
        let source = $value
        let binding: SwiftUI.Binding<Int>
        switch mode {
        case .closureDiscarded, .closureUnread, .closureRead:
            binding = SwiftUI.Binding(get: { trace.gets += 1; return value }, set: { value = $0 })
        default: binding = source
        }
        return SwiftUI.Group {
            switch mode {
            case .closureDiscarded, .projectedDiscarded:
                SwiftUI.Text("fixed")
            default:
                ConstructionConsumer(value: binding, read: mode == .closureRead || mode == .projectedRead, trace: trace)
            }
        }.onAppear { trace.first = { source.wrappedValue = $0 } }
    }
}

extension SliceTests {
    @MainActor private func processOwnerEvents() {
        let end = Date(timeIntervalSinceNow: 0.10)
        while Date() < end { _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005)) }
    }

    @MainActor private func hostOwnerProbe<V: SwiftUI.View>(_ view: V, trace: OwnerTrace,
                                                           run: () throws -> Void) rethrows {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.contentView = nil; window.orderOut(nil); trace.clear() }
        processOwnerEvents()
        try run()
    }

    @Test @MainActor func ownerBindingConstructorReadsDuringInitialization() {
        var gets = 0
        let binding = SwiftUI.Binding(get: { gets += 1; return 7 }, set: { _ in })
        let afterConstruction = gets
        let value = binding.wrappedValue
        print("OwnerBinding constructor: afterConstruction=\(afterConstruction) afterRead=\(gets) value=\(value)")
        #expect(afterConstruction == 1) // G1; G0 was refuted and preserved in the discovery log
        #expect(gets == 2)
        #expect(value == 7)
    }

    @Test @MainActor func ownerBindingOwnerAndConsumerIdentityProfiles() throws {
        let trace = OwnerTrace()
        try hostOwnerProbe(OwnerContainer(trace: trace), trace: trace) {
            #expect(trace.value == "0")
            var owners: [Int] = [], children: [Int] = [], values: [String] = []
            for step in 0..<10 {
                let ownerBefore = trace.owner, childBefore = trace.child
                switch step {
                case 0: let action = try #require(trace.first); action(1)
                case 1: let action = try #require(trace.flip); action()
                case 2: let action = try #require(trace.first); action(2)
                case 3: let action = try #require(trace.replaceChild); action()
                case 4: let action = try #require(trace.first); action(3)
                case 5: let action = try #require(trace.second); action(101)
                case 6: let action = try #require(trace.replaceOwner); action()
                case 7: let action = try #require(trace.second); action(102)
                case 8, 9: let action = try #require(trace.first); action(4)
                default: break
                }
                processOwnerEvents()
                owners.append(trace.owner - ownerBefore)
                children.append(trace.child - childBefore)
                values.append(trace.value)
            }
            #expect(values == ["1", "100", "100", "100", "100", "101", "0", "0", "4", "4"])
            #expect(owners == [0, 0, 0, 1, 0, 0, 1, 0, 0, 0])
            #expect(children == [1, 1, 1, 1, 0, 1, 1, 0, 1, 0])
            print("OwnerBinding identity: owner=\(owners) child=\(children) values=\(values)")
        }
    }

    @Test @MainActor func ownerBindingConstructionAndConsumptionProfiles() throws {
        for mode in ConstructionMode.allCases {
            let trace = OwnerTrace()
            try hostOwnerProbe(ConstructionOwner(mode: mode, trace: trace), trace: trace) {
                let write = try #require(trace.first)
                var owners: [Int] = [], children: [Int] = [], gets: [Int] = []
                for value in [1, 1, 2] {
                    let before = (trace.owner, trace.child, trace.gets)
                    write(value)
                    processOwnerEvents()
                    owners.append(trace.owner - before.0)
                    children.append(trace.child - before.1)
                    gets.append(trace.gets - before.2)
                }
                let closureMode = mode == .closureDiscarded || mode == .closureUnread || mode == .closureRead
                let hasChild = mode != .closureDiscarded && mode != .projectedDiscarded
                let expectedOwners = closureMode ? [1, 0, 1] : [0, 0, 0]
                let expectedChildren = hasChild && (closureMode || mode == .projectedRead) ? [1, 0, 1] : [0, 0, 0]
                let expectedGets = closureMode ? (hasChild ? [2, 0, 2] : [1, 0, 1]) : [0, 0, 0]
                #expect(owners == expectedOwners)
                #expect(children == expectedChildren)
                #expect(gets == expectedGets)
                if mode == .closureRead || mode == .projectedRead { #expect(trace.value == "2") }
                print("OwnerBinding construction \(mode.rawValue): owner=\(owners) child=\(children) get=\(gets)")
            }
        }
    }
}
extension SliceTests {
    @Test func ownerBindingPrototypeStillDefersItsGetter() {
        var gets = 0
        let binding = ShellUI.Binding(get: { gets += 1; return 7 }, set: { _ in })
        #expect(gets == 0) // explicit prototype gap: native construction calls get once
        #expect(binding.wrappedValue == 7)
        #expect(gets == 1)
        print("OwnerBinding prototype: afterConstruction=0 afterRead=1; native=1,2")
    }

    @Test func ownerBindingGraphOwnerRetainsStateUntilOwnerRemoval() {
        final class Payload { let value: Int; init(_ value: Int) { self.value = value } }
        let graph = Graph()
        let owner = graph.makeSubgraph()
        var payload: Payload? = Payload(7)
        weak var retainedPayload = payload
        let state = graph.withCurrent(owner) { graph.makeInput(payload!) }
        payload = nil
        func makeConsumer() -> (Subgraph, Attribute<Int>) {
            let child = graph.makeSubgraph(parent: owner)
            let body = graph.withCurrent(child) { graph.makeRule { state.value.value } }
            return (child, body)
        }
        var (child, body) = makeConsumer()
        #expect(graph.value(of: body) == 7)
        graph.invalidate(child)
        #expect(retainedPayload != nil && graph.nodeCount == 1)
        (child, body) = makeConsumer()
        #expect(graph.value(of: body) == 7 && graph.nodeCount == 2)
        graph.invalidate(owner)
        #expect(retainedPayload == nil)
        #expect(graph.nodeCount == 0 && graph.edgeCount == 0 && graph.liveSubgraphCount == 1)
        print("OwnerBinding graph: consumer replacement preserves state; owner removal releases payload and all nodes")
    }
}
#endif
