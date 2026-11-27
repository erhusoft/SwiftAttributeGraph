import Testing
@testable import SwiftAttributeGraph

@Suite("ObservedAttributeTests")
struct ObservedAttributeTests {
    struct TestObservedBody: ObservedAttribute {
        var onUpdate: () -> Void = {}
        var onDestroy: () -> Void = {}

        mutating func destroy() {
            onDestroy()
        }
    }

    @Test
    func observedAttributeConformanceDefaults() {
        #expect(TestObservedBody._hasDestroySelf == true)
        
        var destroyed = false
        var body = TestObservedBody(onDestroy: {
            destroyed = true
        })

        withUnsafeMutablePointer(to: &body) { ptr in
            TestObservedBody._destroySelf(UnsafeMutableRawPointer(ptr))
        }

        #expect(destroyed == true)
    }

    @Test
    func observedAttributeBodyFlagsAndModeDefaults() {
        #expect(TestObservedBody.flags == [.mainThread])   // native raw 8 (oracle scenario f6)
        #expect(TestObservedBody.comparisonMode == .equatableUnlessPOD)   // native mode 2 (f6)
    }
}
