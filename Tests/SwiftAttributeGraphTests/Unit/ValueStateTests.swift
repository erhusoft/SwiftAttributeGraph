import Testing
@testable import SwiftAttributeGraph

/// `AGGraphGetValueState` (`AGAttribute.valueState`). Measured with the `value-state` oracle scenario on macOS 15.8:
/// a rule starts dirty and pending with no value (0x53 with the main-thread bits), a read clears dirty and pending and
/// sets the value (0x08 bit-masked), and an input change makes the rule dirty again (0x09). The main-thread bits
/// (0x10, 0x40) are not modeled: a graph is used from one thread. The mask 0x0B covers what is compared.
@Suite struct ValueStateTests {
    @Test func ruleStateFollowsReadsAndInputChanges() {
        let graph = Graph()
        let input = graph.makeInput(1)
        let r = graph.makeRule { graph.value(of: input) + 1 }
        #expect(r.valueState.rawValue & 0x0B == 0x03)

        _ = graph.value(of: r)
        #expect(r.valueState.rawValue & 0x0B == 0x08)

        graph.setValue(2, for: input)
        #expect(r.valueState.rawValue & 0x0B == 0x09)

        _ = graph.value(of: r)
        #expect(r.valueState.rawValue & 0x0B == 0x08)
    }

    @Test func inputHasAValueAndIsNotDirty() {
        let graph = Graph()
        let input = graph.makeInput(7)
        #expect(input.valueState.rawValue & 0x0B == 0x08)
    }
}
