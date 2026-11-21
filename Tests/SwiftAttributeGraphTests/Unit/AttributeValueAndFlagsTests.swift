import Testing
@testable import SwiftAttributeGraph

/// `Attribute.valueAndFlags(options:)` and `AGChangedValueFlags`. Measured with the `value-and-flags` scenario on macOS 15.8:
/// outside a rule the flags are 0; inside a rule the `changed` bit is set on the first run and after the input changes.
@Suite struct AttributeValueAndFlagsTests {
    @Test func rawValuesMatchTheHeader() {
        #expect(AGChangedValueFlags.changed.rawValue == 1 << 0)
        #expect(AGChangedValueFlags.requiresMainThread.rawValue == 1 << 1)
    }

    @Test func outsideARuleTheFlagsAreZero() {
        let graph = Graph()
        let input = graph.makeInput(1)
        graph.setValue(2, for: input)
        let read = input.valueAndFlags()
        #expect(read.value == 2)
        #expect(read.flags == [])
    }

    @Test func insideARuleTheChangedBitFollowsTheInput() {
        let graph = Graph()
        let source = graph.makeInput(1)
        var flags: [AGChangedValueFlags] = []
        let rule = graph.makeRule { () -> Int in
            let read = source.valueAndFlags()
            flags.append(read.flags)
            return read.value
        }
        _ = graph.value(of: rule)
        graph.setValue(2, for: source)
        _ = graph.value(of: rule)
        #expect(flags == [.changed, .changed])
    }
}
