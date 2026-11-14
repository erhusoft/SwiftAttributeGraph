import Testing
@testable import SwiftAttributeGraph

/// The comparison is resolved once, when the attribute is created, and it ignores padding bytes.
@Suite struct ComparisonResolutionTests {
    /// Counts how many times `==` runs.
    private struct Counted: Equatable {
        nonisolated(unsafe) static var calls = 0
        var a: Int
        static func == (l: Self, r: Self) -> Bool { calls += 1; return l.a == r.a }
    }
    private struct Padded { var flag: Bool; var n: Int }

    @Test func equalityRunsOncePerWriteAndNeverWhenCreatingTheAttribute() {
        Counted.calls = 0
        let graph = Graph()
        let a = graph.makeInput(Counted(a: 1), comparison: .stateWrite)
        #expect(Counted.calls == 0)
        graph.setValue(Counted(a: 2), for: a)
        #expect(Counted.calls == 1)
        graph.setValue(Counted(a: 2), for: a)
        #expect(Counted.calls == 2)
    }

    @Test func viewValueNeverCallsTheEqualityOfATrivialType() {
        Counted.calls = 0
        let graph = Graph()
        let a = graph.makeInput(Counted(a: 1), comparison: .viewValue)
        graph.setValue(Counted(a: 1), for: a)
        graph.setValue(Counted(a: 2), for: a)
        #expect(Counted.calls == 0)
    }

    @Test func paddingBytesAreNotCompared() {
        // Two buffers with the same fields and different bytes in the padding between `flag` and `n`.
        let size = MemoryLayout<Padded>.size
        let left = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<Padded>.alignment)
        let right = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<Padded>.alignment)
        defer { left.deallocate(); right.deallocate() }
        memset8(left, 0x00, size); memset8(right, 0xFF, size)
        for buffer in [left, right] {
            buffer.storeBytes(of: true, toByteOffset: MemoryLayout<Padded>.offset(of: \.flag)!, as: Bool.self)
            buffer.storeBytes(of: 7, toByteOffset: MemoryLayout<Padded>.offset(of: \.n)!, as: Int.self)
        }
        #expect(size == 16 && !bytesEqualRaw(left, right, size))                  // the padding does differ
        for mode in [ComparisonPlan.Mode.view, .state] {
            let plan = ComparisonPlan.make(for: Padded.self, mode: mode)
            #expect(plan.equal(left, right), "mode \(mode)")
        }
    }

    @Test func aTrivialStructIsOneRangeOfBytesPerRun() {
        struct Three { var a: Int; var b: Int; var c: Int }
        let plan = ComparisonPlan.make(for: Three.self, mode: .view)
        #expect(plan.operationCount == 1)                                            // adjacent fields merge
        let padded = ComparisonPlan.make(for: Padded.self, mode: .view)
        #expect(padded.operationCount == 2)                                          // the padding splits the range
    }

    @Test func theLayoutReaderSeesTheFieldsOfStructsAndTuples() {
        struct S { var d: Double; var s: String; var o: Int? }
        let fields = TypeLayout.fields(of: S.self)
        #expect(fields?.map(\.offset) == [0, 8, 24])
        #expect(TypeLayout.fields(of: (Double, String).self)?.count == 2)
        #expect(TypeLayout.kind(of: S.self) == .structure)
        #expect(TypeLayout.kind(of: (Int, Int).self) == .tuple)
        #expect(TypeLayout.kind(of: Optional<String>.self) == .optional)
        #expect(TypeLayout.kind(of: Any.self) == .existential)
        #expect(TypeLayout.kind(of: ComparisonResolutionTests.self) == .structure)
        #expect(TypeLayout.kind(of: ComparisonResolutionTestsClass.self) == .reference)
        #expect(TypeLayout.kind(of: (() -> Void).self) == .function)
        #expect(TypeLayout.isPOD(Int.self) && !TypeLayout.isPOD(String.self))
    }

    /// A deep type nesting is walked once, when the attribute is created (type depth, not data depth).
    @Test func aDeeplyNestedTypeResolvesAndCompares() {
        struct L0 { var d: Double; var s: String }
        struct L1 { var x: L0; var n: Int }
        struct L2 { var x: L1; var f: Float }
        struct L3 { var x: L2; var b: Bool }
        let graph = Graph()
        let make = { (d: Double) in L3(x: L2(x: L1(x: L0(d: d, s: "x"), n: 1), f: 1), b: true) }
        let a = graph.makeInput(make(0.0), comparison: .viewValue)
        let v = graph.version(of: a.id)
        graph.setValue(make(0.0), for: a)
        #expect(graph.version(of: a.id) == v)
        graph.setValue(make(-0.0), for: a)
        #expect(graph.version(of: a.id) == v + 1)
    }
}

private final class ComparisonResolutionTestsClass {}

private func memset8(_ pointer: UnsafeMutableRawPointer, _ value: UInt8, _ count: Int) {
    for i in 0..<count { pointer.storeBytes(of: value, toByteOffset: i, as: UInt8.self) }
}
private func bytesEqualRaw(_ a: UnsafeRawPointer, _ b: UnsafeRawPointer, _ count: Int) -> Bool {
    for i in 0..<count where a.load(fromByteOffset: i, as: UInt8.self) != b.load(fromByteOffset: i, as: UInt8.self) { return false }
    return true
}
