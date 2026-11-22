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
        #expect(TestObservedBody.flags == [])
        #expect(TestObservedBody.comparisonMode == .equatableAlways)
    }
}
