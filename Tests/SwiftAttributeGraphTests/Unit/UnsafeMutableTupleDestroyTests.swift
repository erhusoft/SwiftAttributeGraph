import Testing
@testable import SwiftAttributeGraph

/// `deinitialize(at:)`, `deinitialize()` and `deallocate(initialized:)` destroy the elements with their real type, so
/// reference-counted elements are released. Oracle scenario `cov79-b-tuples`: the live instances go `[1, 0, 0, 1, 0]` in
/// native; before this they stayed alive (`[1, 1, 2, 3, 3]`) because the three calls did nothing.
/// The elements are 8 bytes wide: `AGTupleType` lays every element out in 8 bytes (see `docs/AttributeGraph/COBERTURA-API-79-SIN-ESCENARIO.md`).
@Suite struct UnsafeMutableTupleDestroyTests {
    private final class Counter { var live = 0 }

    private final class Box {
        let counter: Counter
        init(_ counter: Counter) { self.counter = counter; counter.live += 1 }
        deinit { counter.live -= 1 }
    }

    private func makeTuple(_ counter: Counter) -> AGUnsafeMutableTuple {
        let type = AGTupleType([Box.self, Int.self, Box.self, Double.self])
        let tuple = AGUnsafeMutableTuple(with: type)
        tuple.initialize(at: 0, to: Box(counter))
        tuple.initialize(at: 1, to: 7)
        tuple.initialize(at: 2, to: Box(counter))
        tuple.initialize(at: 3, to: 2.5)
        return tuple
    }

    @Test func deinitializeAtReleasesOnlyThatElement() {
        let counter = Counter()
        let tuple = makeTuple(counter)
        #expect(counter.live == 2)

        tuple.deinitialize(at: 0)
        #expect(counter.live == 1)
        tuple.deinitialize(at: 1)                       // a trivial element: nothing to release, nothing breaks
        #expect(counter.live == 1)
        tuple.deinitialize(at: 2)
        #expect(counter.live == 0)

        tuple.deinitialize(at: 3)
        tuple.deallocate(initialized: false)
    }

    @Test func deinitializeReleasesEveryElement() {
        let counter = Counter()
        let tuple = makeTuple(counter)

        tuple.deinitialize()

        #expect(counter.live == 0)
        tuple.deallocate(initialized: false)
    }

    @Test func deallocateInitializedReleasesEveryElement() {
        let counter = Counter()
        let tuple = makeTuple(counter)
        #expect(counter.live == 2)

        tuple.deallocate(initialized: true)

        #expect(counter.live == 0)
    }
}
