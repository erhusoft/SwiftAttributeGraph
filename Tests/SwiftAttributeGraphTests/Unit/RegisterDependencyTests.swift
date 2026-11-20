import Testing
@testable import SwiftAttributeGraph

/// `AGGraphRegisterDependency(attribute, options)` (`Graph.registerDependency(on:)`). SwiftUI calls it from inside rules at
/// four sites with options 0 and the attribute in the first argument. Measured with the `register-dependency-in-rule`
/// oracle scenario: a rule that registers a dependency on an input without reading it is dirtied by a write to that input
/// and runs again. Only options 0 is modeled.
@Suite struct RegisterDependencyTests {
    @Test func aRuleThatRegistersADependencyIsDirtiedAndRerun() {
        let graph = Graph()
        let source = graph.makeInput(1)
        var runs = 0
        let rule = graph.makeRule { () -> Int in
            runs += 1
            graph.registerDependency(on: source)
            return 5
        }
        _ = graph.value(of: rule)
        #expect(runs == 1)

        graph.setValue(2, for: source)
        #expect(graph.valueState(of: rule).rawValue & 0x01 == 1)
        _ = graph.value(of: rule)
        #expect(runs == 2)
    }
}
