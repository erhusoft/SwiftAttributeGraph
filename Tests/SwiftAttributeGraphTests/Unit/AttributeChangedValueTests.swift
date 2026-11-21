import Testing
@testable import SwiftAttributeGraph

/// `Attribute.changedValue(options:)` (`AGAttribute.changedValue`). Measured on macOS 15.8 (`changed-value`): outside a rule
/// it is always `false`. Inside a rule it reports whether the input changed since the rule's previous run.
@Suite struct AttributeChangedValueTests {
    @Test func outsideARuleItIsAlwaysFalse() {
        let graph = Graph()
        let input = graph.makeInput(1)
        graph.setValue(2, for: input)
        let read = input.changedValue()
        #expect(read.value == 2)
        #expect(read.changed == false)
    }

    @Test func insideARuleItReportsAChangeSinceThePreviousRun() {
        let graph = Graph()
        let source = graph.makeInput(1)
        var seen: [Bool] = []
        let rule = graph.makeRule { () -> Int in
            let read = source.changedValue()
            seen.append(read.changed)
            return read.value
        }
        _ = graph.value(of: rule)
        graph.setValue(2, for: source)
        _ = graph.value(of: rule)
        rule.invalidateValue()
        _ = graph.value(of: rule)
        #expect(seen == [true, true, false])
    }
}
