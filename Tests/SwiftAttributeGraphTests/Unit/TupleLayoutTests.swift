import Testing
@testable import SwiftAttributeGraph

/// Tuple layout follows Swift's own: each element at its natural alignment, size without trailing padding. Values measured
/// on macOS 15.8 by oracle scenarios `hueco-a0` to `hueco-a9`.
@Suite struct TupleLayoutTests {
    private func layout(_ types: [Any.Type]) -> (size: Int, offsets: [Int], sizes: [Int]) {
        let t = AGTupleType(types)
        return (t.size, t.indices.map { t.offset(at: $0, as: Any.self) }, t.indices.map { t.elementSize(at: $0) })
    }

    @Test func int8ThenInt64() {
        let l = layout([Int8.self, Int64.self])
        #expect(l.size == 16); #expect(l.offsets == [0, 8]); #expect(l.sizes == [1, 8])
    }

    @Test func threeInt8sArePacked() {
        let l = layout([Int8.self, Int8.self, Int8.self])
        #expect(l.size == 3); #expect(l.offsets == [0, 1, 2]); #expect(l.sizes == [1, 1, 1])
    }

    @Test func int32ThenInt8() {
        let l = layout([Int32.self, Int8.self])
        #expect(l.size == 5); #expect(l.offsets == [0, 4]); #expect(l.sizes == [4, 1])
    }

    @Test func boolThenDouble() {
        let l = layout([Bool.self, Double.self])
        #expect(l.size == 16); #expect(l.offsets == [0, 8]); #expect(l.sizes == [1, 8])
    }

    @Test func int64ThenString() {
        let l = layout([Int64.self, String.self])
        #expect(l.size == 24); #expect(l.offsets == [0, 8]); #expect(l.sizes == [8, 16])
    }

    @Test func stringThenInt8() {
        let l = layout([String.self, Int8.self])
        #expect(l.size == 17); #expect(l.offsets == [0, 16]); #expect(l.sizes == [16, 1])
    }

    @Test func singleAndEmpty() {
        let one = layout([Int64.self])
        #expect(one.size == 8); #expect(one.offsets == [0])
        let none = layout([])
        #expect(none.size == 0); #expect(none.offsets == [])
    }

    @Test func aStringAndAnInt8RoundTripInTheirBuffer() {
        let t = AGTupleType([String.self, Int8.self])
        let tuple = AGUnsafeMutableTuple(with: t)
        tuple.initialize(at: 0, to: "a string long enough to live on the heap")
        tuple.initialize(at: 1, to: Int8(5))
        let s: String = tuple[0]
        let n: Int8 = tuple[1]
        #expect(s == "a string long enough to live on the heap")
        #expect(n == 5)
        tuple.deallocate()
    }
}
