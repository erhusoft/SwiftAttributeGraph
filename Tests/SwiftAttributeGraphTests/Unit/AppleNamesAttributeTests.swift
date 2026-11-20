import Testing
@testable import SwiftAttributeGraph

@Suite("AppleNamesAttributeTests")
struct AppleNamesAttributeTests {
    /// Apple's attribute accessors (AGAttribute.value, hasValue, flags) on the handle, resolving the graph from the tag
    /// [O, native headers AGAttribute.h].
    @Test func attributeAccessorsMatchTheAppleNames() {
        let graph = Graph()
        let input = graph.makeInput(7)
        let rule = graph.makeRule { graph.value(of: input) * 2 }

        #expect(rule.hasValue == false)
        #expect(graph.value(of: rule) == 14)
        #expect(rule.hasValue)

        #expect(rule.flags.isEmpty)
        rule.flags = AttributeFlags(rawValue: 0x4)
        #expect(rule.flags == AttributeFlags(rawValue: 0x4))
    }
}
