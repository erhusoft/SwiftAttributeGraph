import Testing
@testable import SwiftAttributeGraph

@Suite(.serialized) struct ResumablePerformanceTests {
    struct ColdPlus: ResumableRule {
        let source: Attribute<Int>
        mutating func resume(_ context: inout ResumableRuleContext<Int>) -> RuleStep {
            switch context.poll(source) {
            case .pending: return .needsInput(source.erased)
            case .ready(let value): context.value = value + 1; return .finished
            }
        }
    }

    @Test func measureColdChainsWithoutCreationOrDestruction() {
        for depth in [20_000, 100_000] {
            var samples: [Double] = []
            for _ in 0..<5 {
                let graph = Graph()
                var last = graph.makeInput(0)
                for _ in 0..<depth { last = graph.makeResumableRule(ColdPlus(source: last)) }
                var result = 0
                let duration = ContinuousClock().measure { result = graph.value(of: last) }
                samples.append(Double(duration.components.seconds) * 1_000
                               + Double(duration.components.attoseconds) / 1e15)
                #expect(result == depth && graph.frames.isEmpty)
            }
            print("M4_COLD depth=\(depth) median_ms=\(samples.sorted()[2])")
        }
    }
    struct SynchronousSum: StatefulRule {
        typealias Value = Int
        let first: Attribute<Int>
        let second: Attribute<Int>
        static var initialValue: Int? { 0 }
        mutating func updateValue() {
            let a = first.value, b = second.value
            if context.hasChanged(first) { context.value = a + b }
        }
    }
    struct ResumableSum: ResumableRule {
        let first: Attribute<Int>
        let second: Attribute<Int>
        var left: Int?
        static var initialValue: Int? { 0 }
        mutating func resume(_ context: inout ResumableRuleContext<Int>) -> RuleStep {
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

    func measure(resumable: Bool) -> Double {
        let graph = Graph()
        let a = graph.makeInput(0), b = graph.makeInput(1)
        let rules: [Attribute<Int>] = (0..<1_000).map { _ in
            resumable ? graph.makeResumableRule(ResumableSum(first: a, second: b))
                : graph.makeStatefulRule(SynchronousSum(first: a, second: b))
        }
        for rule in rules { _ = graph.value(of: rule) }
        let duration = ContinuousClock().measure {
            for value in 1...50 {
                graph.setValue(value, for: a)
                for rule in rules { _ = graph.value(of: rule) }
            }
        }
        #expect(graph.value(of: rules[0]) == 51 && graph.frames.isEmpty)
        return Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    @Test func theCandidateMustStayWithinThirtyPercentOfEquivalentTypedStatefulRules() {
        var synchronous: [Double] = [], resumable: [Double] = []
        for sample in 0..<7 {
            if sample % 2 == 0 {
                synchronous.append(measure(resumable: false))
                resumable.append(measure(resumable: true))
            } else {
                resumable.append(measure(resumable: true))
                synchronous.append(measure(resumable: false))
            }
        }
        let syncMedian = synchronous.sorted()[3], resumeMedian = resumable.sorted()[3]
        let ratio = resumeMedian / syncMedian
        print("M4_GATE synchronous_ms=\(syncMedian) resumable_ms=\(resumeMedian) ratio=\(ratio) limit=1.30")
        print("M4_SAMPLES synchronous=\(synchronous) resumable=\(resumable)")
        print("M4_FRAME_STRIDE \(MemoryLayout<UpdateFrame>.stride)")
        #if !DEBUG
        #expect(ratio <= 1.30, "the predeclared M4 candidate acceptance budget")
        #endif
    }
}
