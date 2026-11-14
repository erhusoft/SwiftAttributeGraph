// Build with -Xswiftc -enable-testing. This driver measures the internal prototype without publishing its API.
@testable import ResumableGraphPrototype

@main struct Profile {
    struct Sum: ResumableRule {
        let first: Attribute<Int>
        let second: Attribute<Int>
        var left: Int?
        static var initialValue: Int? { 0 }
        mutating func resume(_ context: inout RuleContext<Int>) -> RuleStep {
            if context.isFirstStep { left = nil }
            if left == nil {
                switch context.poll(first) {
                case .pending: return .needsInput(first.erased)
                case .ready(let value): left = value
                }
            }
            switch context.poll(second) {
            case .pending: return .needsInput(second.erased)
            case .ready(let value):
                if context.hasChanged(first) { context.value = left! + value }
                return .finished
            }
        }
    }

    static func main() {
        let cycles = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 5_000
        precondition(cycles > 0)
        let graph = PrototypeGraph()
        let first = graph.makeInput(0), second = graph.makeInput(1)
        let rules = (0..<1_000).map { _ in graph.makeRule(Sum(first: first, second: second)) }
        for rule in rules { _ = graph.value(of: rule) }
        let duration = ContinuousClock().measure {
            for value in 1...cycles {
                graph.setValue(value, for: first)
                for rule in rules { _ = graph.value(of: rule) }
            }
        }
        precondition(graph.value(of: rules[0]) == cycles + 1)
        print("\(cycles * rules.count) rule evaluations: \(duration)")
    }
}
