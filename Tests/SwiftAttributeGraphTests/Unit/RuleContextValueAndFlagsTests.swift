import Testing
@testable import SwiftAttributeGraph

/// `RuleContext.valueAndFlags(of:options:)` and `RuleContext.changedValue(of:options:)` (native `RuleContext`, Swift
/// interface). Inside a rule they read the input as a dependency and report its change, like the attribute forms.
@Suite struct RuleContextValueAndFlagsTests {
    @Test func valueAndFlagsReportsTheChangedBitForTheRule() {
        let graph = Graph()
        let source = graph.makeInput(1)
        var flags: [AGChangedValueFlags] = []
        let rule = graph.makeStatefulRule(initialValue: 0) { (context: inout RuleContext<Int>) in
            let read = context.valueAndFlags(of: source)
            flags.append(read.flags)
            context.value = read.value
        }
        _ = graph.value(of: rule)
        graph.setValue(2, for: source)
        _ = graph.value(of: rule)
        #expect(flags == [.changed, .changed])
    }

    @Test func changedValueAcceptsOptionsAndReportsTheChange() {
        let graph = Graph()
        let source = graph.makeInput(1)
        var changes: [Bool] = []
        let rule = graph.makeStatefulRule(initialValue: 0) { (context: inout RuleContext<Int>) in
            let read = context.changedValue(of: source, options: [])
            changes.append(read.changed)
            context.value = read.value
        }
        _ = graph.value(of: rule)
        #expect(changes == [true])
    }
}
