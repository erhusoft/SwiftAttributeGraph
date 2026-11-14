// Foundation and Dispatch are test-only: they create a thread with a chosen stack size and join its result.
import Foundation
import Dispatch
import Testing
@testable import ResumableGraphPrototype

@Suite struct ThreadTests {
    final class Result: @unchecked Sendable {
        let done = DispatchSemaphore(value: 0)
        var value = 0
        var original: UInt64 = 0
        var final: UInt64 = 0
        var maximumActiveSteps = 0
        var frames = 0
    }

    @Test func oneHundredThousandColdRulesRunOnTheOriginalThreadWithA512KBStack() {
        let result = Result()
        let worker = Thread {
            let graph = PrototypeGraph()
            let counter = PrototypeTests.Counter()
            var last = graph.makeInput(0)
            for _ in 0..<100_000 {
                last = graph.makeRule(PrototypeTests.PlusOne(source: last, counter: counter))
            }
            result.original = graph.owningThread
            result.value = graph.value(of: last)
            result.final = threadIdentity()
            result.maximumActiveSteps = graph.maximumActiveSteps
            result.frames = graph.frameCount
            result.done.signal()
        }
        worker.stackSize = 512 * 1024
        worker.start()
        #expect(result.done.wait(timeout: .now() + 30) == .success)
        #expect(result.value == 100_000)
        #expect(result.original == result.final)
        #expect(result.maximumActiveSteps == 1 && result.frames == 0)
    }
}
