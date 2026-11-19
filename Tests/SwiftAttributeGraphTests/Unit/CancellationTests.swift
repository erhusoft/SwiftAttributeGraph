import Testing
@testable import SwiftAttributeGraph

@Suite("CooperativeCancellationTests")
struct CooperativeCancellationTests {
    @Test
    func cancelUpdateMarksCurrentAndNestedFramesAndRestoresAfterExit() {
        let graph = Graph()
        let source = graph.makeInput(10)
        var innerSawCancel = false
        var outerSawCancelBeforeInner = false
        var outerSawCancelAfterInner = false

        let inner = graph.makeRule {
            let v = source.value
            graph.cancelUpdate()
            innerSawCancel = graph.updateWasCancelled
            return v + 1
        }

        let outer = graph.makeRule {
            outerSawCancelBeforeInner = graph.updateWasCancelled
            let v = inner.value
            outerSawCancelAfterInner = graph.updateWasCancelled
            return v * 2
        }

        #expect(graph.value(of: outer) == 22)
        #expect(outerSawCancelBeforeInner == false)
        #expect(innerSawCancel == true)
        #expect(outerSawCancelAfterInner == true)
        #expect(graph.frames.isEmpty)
    }
}
