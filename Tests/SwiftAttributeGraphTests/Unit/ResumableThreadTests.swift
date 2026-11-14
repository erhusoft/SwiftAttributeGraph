// Foundation and Dispatch are test-only, for selecting a stack size and synchronizing the result.
import Foundation
import Dispatch
import Testing
@testable import SwiftAttributeGraph

@Suite struct ResumableThreadTests {
    final class Result: @unchecked Sendable {
        let done = DispatchSemaphore(value: 0)
        var value = 0
        var original: UInt64 = 0
        var final: UInt64 = 0
        var emptyFrames = false
    }
    @Test func oneHundredThousandColdRulesKeepTheirThreadWithA512KBStack() {
        let result = Result()
        let worker = Thread {
            let graph = Graph()
            let counter = ResumableRuleTests.Counter()
            result.original = currentThreadToken()
            var last = graph.makeInput(0)
            for _ in 0..<100_000 {
                last = graph.makeResumableRule(ResumableRuleTests.PlusOne(source: last, counter: counter))
            }
            result.value = graph.value(of: last)
            result.final = currentThreadToken()
            result.emptyFrames = graph.frames.isEmpty
            result.done.signal()
        }
        worker.stackSize = 512 * 1024
        worker.start()
        let completed = result.done.wait(timeout: .now() + 30)
        #expect(completed == .success)
        guard completed == .success else { return }
        #expect(result.value == 100_000 && result.original == result.final && result.emptyFrames)
    }
}
