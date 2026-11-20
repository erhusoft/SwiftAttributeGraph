import Testing
@testable import SwiftAttributeGraph

/// `AGGraphAddInput(attribute1, attribute2, options, token)` (`Graph.addInput`). Measured with the `add-input` oracle
/// scenario on macOS 15.8: after the call, changing `attribute2` dirties `attribute1` and the next read runs it again;
/// the added edge is an ordinary read, so the next run of `attribute1` drops it unless the rule reads `attribute2` again.
/// Apple's options and token are not modeled; the disassembly also shows a same-namespace precondition, not measured.
@Suite struct AddInputTests {
    @Test func changingTheAddedInputDirtiesAndRerunsTheRule() {
        let graph = Graph()
        let source = graph.makeInput(1)
        var runs = 0
        let rule = graph.makeRule { () -> Int in runs += 1; return 5 }
        _ = graph.value(of: rule)
        #expect(runs == 1)

        graph.addInput(rule, source)
        #expect(graph.valueState(of: rule).rawValue & 0x01 == 0)

        graph.setValue(2, for: source)
        #expect(graph.valueState(of: rule).rawValue & 0x01 == 1)
        _ = graph.value(of: rule)
        #expect(runs == 2)
    }

    @Test func theAddedEdgeIsDroppedByTheNextRunThatDoesNotReadIt() {
        let graph = Graph()
        let source = graph.makeInput(1)
        var runs = 0
        let rule = graph.makeRule { () -> Int in runs += 1; return 5 }
        _ = graph.value(of: rule)
        graph.addInput(rule, source)
        graph.setValue(2, for: source)
        _ = graph.value(of: rule)
        #expect(runs == 2)

        graph.setValue(3, for: source)
        _ = graph.value(of: rule)
        #expect(runs == 2)
    }
}
