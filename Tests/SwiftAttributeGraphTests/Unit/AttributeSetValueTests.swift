import Testing
@testable import SwiftAttributeGraph

/// `Attribute.setValue(_:) -> Bool` (`AGAttribute.setValue`). Measured with the `set-value-result` scenario on macOS 15.8:
/// a new value returns `true`, the same value again returns `false`, and a different value returns `true`.
@Suite struct AttributeSetValueTests {
    @Test func returnsWhetherTheValueChanged() {
        let graph = Graph()
        let input = graph.makeInput(1)
        #expect(input.setValue(2) == true)
        #expect(input.setValue(2) == false)
        #expect(input.setValue(3) == true)
        #expect(graph.value(of: input) == 3)
    }
}
