import Testing
@testable import SwiftAttributeGraph

/// Writing inputs and the `bits` comparison policy. The expectations about `0.0`/`-0.0`, `nan`, class identity and
/// array buffers are the parity measurements against SwiftUI on macOS (E4, E14, E15, E16).
@Suite struct ValueTests {
    private final class Box { let v: Int; init(_ v: Int) { self.v = v } }

    @Test func aWriteChangesWhatIsRead() {
        let graph = Graph()
        let a = graph.makeInput(1)
        graph.setValue(2, for: a)
        #expect(graph.value(of: a) == 2)
    }

    @Test func writingTheSameValueDoesNotRaiseTheVersion() {
        let graph = Graph()
        let a = graph.makeInput(7)
        let before = graph.version(of: a.id)
        graph.setValue(7, for: a)
        #expect(graph.version(of: a.id) == before)
        graph.setValue(8, for: a)
        #expect(graph.version(of: a.id) == before + 1)
    }

    @Test func bitsTellMinusZeroFromZero() {
        let graph = Graph()
        let a = graph.makeInput(0.0)
        let before = graph.version(of: a.id)
        graph.setValue(-0.0, for: a)          // == says equal, the bits differ (E14)
        #expect(graph.version(of: a.id) == before + 1)
    }

    @Test func bitsTreatTheSameNaNAsEqual() {
        let graph = Graph()
        let a = graph.makeInput(Double.nan)
        let before = graph.version(of: a.id)
        graph.setValue(Double.nan, for: a)    // == says different, the bits are the same (E14)
        #expect(graph.version(of: a.id) == before)
    }

    @Test func aClassIsComparedByIdentity() {
        let graph = Graph()
        let first = Box(1)
        let a = graph.makeInput(first)
        let before = graph.version(of: a.id)
        graph.setValue(first, for: a)         // same object (E15)
        #expect(graph.version(of: a.id) == before)
        graph.setValue(Box(1), for: a)        // another object with the same content
        #expect(graph.version(of: a.id) == before + 1)
    }

    @Test func anArrayIsComparedByItsBuffer() {
        let graph = Graph()
        let stored = [1, 2, 3]
        let a = graph.makeInput(stored)
        let before = graph.version(of: a.id)
        graph.setValue(stored, for: a)        // same buffer (E16)
        #expect(graph.version(of: a.id) == before)
        var grown = stored
        grown.append(4)
        graph.setValue(grown, for: a)
        #expect(graph.version(of: a.id) == before + 1)
    }

    /// The M0 policy: only bytes. (The default policy since M2 compares a `String` with `==`; see `ComparisonPolicyTests`.)
    @Test func aLongStringRebuiltIsDifferentButTheSameBufferIsEqual() {
        let graph = Graph()
        let make = { String(repeating: "abcdefghij", count: 5) }
        let stored = make()
        let a = graph.makeInput(stored, comparison: .bits)
        let before = graph.version(of: a.id)
        let copy = stored
        graph.setValue(copy, for: a)          // same buffer
        #expect(graph.version(of: a.id) == before)
        graph.setValue(make(), for: a)        // another buffer, same content (E16)
        #expect(graph.version(of: a.id) == before + 1)
    }

    @Test func alwaysDifferentRaisesTheVersionOnEveryWrite() {
        let graph = Graph()
        let a = graph.makeInput(1, comparison: .alwaysDifferent)
        let before = graph.version(of: a.id)
        graph.setValue(1, for: a)
        graph.setValue(1, for: a)
        #expect(graph.version(of: a.id) == before + 2)
    }

    @Test func optionalsEnumsAndTuplesAreComparedByBitsToo() {
        enum Payload { case number(Int), text(String) }
        let graph = Graph()
        let o = graph.makeInput(Int?.none)
        let e = graph.makeInput(Payload.number(1))
        let t = graph.makeInput((1, 2))
        let (vo, ve, vt) = (graph.version(of: o.id), graph.version(of: e.id), graph.version(of: t.id))
        graph.setValue(nil, for: o)
        graph.setValue(Payload.number(1), for: e)
        graph.setValue((1, 2), for: t)
        #expect((graph.version(of: o.id), graph.version(of: e.id), graph.version(of: t.id)) == (vo, ve, vt))
        graph.setValue(1, for: o)
        graph.setValue(Payload.text("hola"), for: e)
        graph.setValue((1, 3), for: t)
        #expect((graph.version(of: o.id), graph.version(of: e.id), graph.version(of: t.id)) == (vo + 1, ve + 1, vt + 1))
    }

    @Test func writingADeadAttributeStopsTheProgram() async {
        await #expect(processExitsWith: .failure) {
            let graph = Graph()
            let sub = graph.makeSubgraph()
            let a = graph.withCurrent(sub) { graph.makeInput(1) }
            sub.invalidate()
            graph.setValue(2, for: a)
        }
    }
}
