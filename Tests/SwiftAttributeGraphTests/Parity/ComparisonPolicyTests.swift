import Testing
import Foundation
@testable import SwiftAttributeGraph

/// The comparison policies against what SwiftUI does on macOS 15.7.9 (M1), measured in the *warm* state (see
/// `docs/DISENO-M2.md` §1–§5, probe `parity/Compare`). Each case lists whether the observer **runs** (the version
/// rises) for the property of a view (`viewValue`), an environment value (`environment`) and a `@State` write
/// (`stateWrite`).
@Suite struct ComparisonPolicyTests {
    // MARK: Fixtures

    private final class Box { let v: Int; init(_ v: Int) { self.v = v } }
    @inline(never) private static func long() -> String { String(repeating: "abcdefghij", count: 5) }

    private struct Padded: Equatable { var flag: Bool; var n: Int }
    private struct IgnoresB: Equatable { var a: Int; var b: Int; static func == (l: Self, r: Self) -> Bool { l.a == r.a } }
    private struct NeverEqual: Equatable { var a: Int; static func == (l: Self, r: Self) -> Bool { false } }
    private struct AlwaysEqual: Equatable { var a: Int; static func == (l: Self, r: Self) -> Bool { true } }
    private struct Holder: Equatable {
        let box: Box; let n: Int
        static func == (l: Self, r: Self) -> Bool { l.box.v == r.box.v && l.n == r.n }
    }
    private struct Mixed { var d: Double; var s: String }
    private struct MixedEq: Equatable { var d: Double; var s: String }
    private struct Outer { var inner: Mixed; var n: Int }
    private struct TrivialNonEq { var d: Double; var i: Int }
    private struct WithClosure { var label: String; var action: () -> Void }
    private struct DoubleArray { var d: Double; var a: [Int] }
    private struct DoubleBox { var d: Double; var b: Box }
    private struct DoubleOptString { var d: Double; var s: String? }
    private enum PayloadString { case a(Int), b(String) }
    private enum PayloadDouble { case a(Double), b(Int) }

    /// Whether writing `b` over `a` raises the version under `policy`.
    private func changes<V>(_ policy: ValuePolicy, _ a: V, _ b: V) -> Bool {
        let graph = Graph()
        let attribute = graph.makeInput(a, comparison: policy)
        let before = graph.version(of: attribute.id)
        graph.setValue(b, for: attribute)
        return graph.version(of: attribute.id) != before
    }

    /// Checks the three sites. `true` = the observer runs.
    private func expect<V>(_ a: V, _ b: V, view: Bool, environment: Bool, state: Bool,
                           _ what: Comment, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(changes(.viewValue, a, b) == view, "viewValue: \(what)", sourceLocation: sourceLocation)
        #expect(changes(.environment, a, b) == environment, "environment: \(what)", sourceLocation: sourceLocation)
        #expect(changes(.stateWrite, a, b) == state, "stateWrite: \(what)", sourceLocation: sourceLocation)
    }

    // MARK: Plain values (E4, E14, E15, R3-2, R3-3, R4-1…R4-5)

    @Test func integers() {
        expect(1, 1, view: false, environment: false, state: false, "Int 1 -> 1")
        expect(1, 2, view: true, environment: true, state: true, "Int 1 -> 2")
    }

    @Test func doubles() {
        expect(1.0, 1.0, view: false, environment: false, state: false, "1.0 -> 1.0")
        expect(0.0, -0.0, view: true, environment: false, state: false, "0.0 -> -0.0")
        expect(Double.nan, Double.nan, view: false, environment: false, state: true, "nan -> nan (same bits)")
    }

    @Test func strings() {
        let stored = Self.long()
        expect(stored, stored, view: false, environment: false, state: false, "long, same buffer")
        expect(Self.long(), Self.long(), view: false, environment: false, state: false, "long, other buffer")
        expect(Self.long(), "other", view: true, environment: true, state: true, "long, different content")
        expect("abc", "abc", view: false, environment: false, state: false, "short, equal")
        expect("abc", "abd", view: true, environment: true, state: true, "short, different")
    }

    @Test func classes() {
        let shared = Box(1)
        expect(shared, shared, view: false, environment: false, state: false, "same object")
        expect(Box(1), Box(1), view: true, environment: true, state: true, "other object with the same content")
    }

    @Test func arraysAndOptionals() {
        let stored = [1, 2, 3]
        expect(stored, stored, view: false, environment: false, state: false, "[Int] stored buffer")
        expect([1, 2, 3], Array((1...3).map { $0 }), view: false, environment: false, state: false, "[Int] rebuilt equal")
        expect(Int?.some(1), .some(1), view: false, environment: false, state: false, "Int? 1 -> 1")
        expect(String?.none, .none, view: false, environment: false, state: false, "String? nil -> nil")
        expect(Optional(Self.long()), Optional(Self.long()), view: false, environment: false, state: false, "String? long, other buffer")
        expect(Double?.some(0.0), .some(-0.0), view: true, environment: false, state: false, "Double? 0.0 -> -0.0")
        expect(Double?.some(.nan), .some(.nan), view: false, environment: false, state: true, "Double? nan -> nan")
        expect((1, 2), (1, 2), view: false, environment: false, state: false, "(Int, Int) equal")
    }

    // MARK: Structs with a custom == (R5)

    @Test func trivialStructsWithTheirOwnEquality() {
        expect(Padded(flag: true, n: 7), Padded(flag: true, n: 7), view: false, environment: false, state: false, "Padded equal")
        expect(IgnoresB(a: 1, b: 1), IgnoresB(a: 1, b: 2), view: true, environment: false, state: false, "== ignores b, b changes")
        expect(NeverEqual(a: 1), NeverEqual(a: 1), view: false, environment: false, state: true, "== always false, same bytes")
        expect(AlwaysEqual(a: 1), AlwaysEqual(a: 2), view: true, environment: false, state: false, "== always true, other bytes")
    }

    @Test func equatableStructWithAReference() {
        let shared = Box(1)
        expect(Holder(box: shared, n: 1), Holder(box: shared, n: 1), view: false, environment: false, state: false, "same object")
        expect(Holder(box: Box(1), n: 1), Holder(box: Box(1), n: 1), view: false, environment: false, state: false, "other object, == true")
    }

    // MARK: Mixed and nested shapes (round 5 and 6): each field follows its own rule

    @Test func mixedStructs() {
        expect(Mixed(d: 0.0, s: "ab"), Mixed(d: -0.0, s: "ab"), view: true, environment: false, state: false, "d 0.0 -> -0.0")
        expect(Mixed(d: .nan, s: "ab"), Mixed(d: .nan, s: "ab"), view: false, environment: false, state: true, "d nan -> nan")
        expect(Mixed(d: 1.0, s: Self.long()), Mixed(d: 1.0, s: Self.long()), view: false, environment: false, state: false, "s long, other buffer")
        expect(MixedEq(d: 0.0, s: "ab"), MixedEq(d: -0.0, s: "ab"), view: false, environment: false, state: false, "Equatable: == decides")
        expect(Outer(inner: Mixed(d: 0.0, s: "ab"), n: 1), Outer(inner: Mixed(d: -0.0, s: "ab"), n: 1), view: true, environment: false, state: false, "nested d -0.0")
        expect(Outer(inner: Mixed(d: 1.0, s: Self.long()), n: 1), Outer(inner: Mixed(d: 1.0, s: Self.long()), n: 1),
               view: false, environment: false, state: false, "nested s, other buffer")
        expect(TrivialNonEq(d: 0.0, i: 1), TrivialNonEq(d: -0.0, i: 1), view: true, environment: false, state: false, "trivial, not Equatable, -0.0")
        expect(TrivialNonEq(d: .nan, i: 1), TrivialNonEq(d: .nan, i: 1), view: false, environment: false, state: true, "trivial, not Equatable, nan")
        expect((0.0, "ab"), (-0.0, "ab"), view: true, environment: false, state: false, "tuple (Double, String) -0.0")
        expect((1.0, Self.long()), (1.0, Self.long()), view: false, environment: false, state: false, "tuple s, other buffer")
        let shared = [1, 2, 3]
        expect(DoubleArray(d: 1.0, a: [1, 2, 3]), DoubleArray(d: 1.0, a: Array((1...3).map { $0 })), view: false, environment: false, state: false, "array rebuilt")
        expect(DoubleArray(d: 0.0, a: shared), DoubleArray(d: -0.0, a: shared), view: true, environment: false, state: false, "d -0.0, same array")
        expect(DoubleBox(d: 1.0, b: Box(1)), DoubleBox(d: 1.0, b: Box(1)), view: true, environment: true, state: true, "other object")
        let box = Box(1)
        expect(DoubleBox(d: 0.0, b: box), DoubleBox(d: -0.0, b: box), view: true, environment: false, state: false, "same object, d -0.0")
        expect(DoubleOptString(d: 1.0, s: Self.long()), DoubleOptString(d: 1.0, s: Self.long()), view: false, environment: false, state: false, "String? other buffer")
        expect(DoubleOptString(d: 0.0, s: "ab"), DoubleOptString(d: -0.0, s: "ab"), view: true, environment: false, state: false, "d -0.0")
    }

    @Test func closures() {
        let none = WithClosure(label: "a", action: { })
        expect(none, none, view: false, environment: false, state: false, "no captures, same value")
        expect(WithClosure(label: "a", action: { [x = 1] in print(x) }), WithClosure(label: "a", action: { [x = 2] in print(x) }),
               view: true, environment: true, state: true, "captured value changes")
    }

    @Test func typesOfOtherModules() {
        expect(CGPoint(x: 0, y: 1), CGPoint(x: -0.0, y: 1), view: true, environment: false, state: false, "CGPoint x -0.0")
        expect(CGPoint(x: Double.nan, y: 1), CGPoint(x: Double.nan, y: 1), view: false, environment: false, state: true, "CGPoint nan")
        expect(CGSize(width: 0, height: 1), CGSize(width: -0.0, height: 1), view: true, environment: false, state: false, "CGSize -0.0")
    }

    // MARK: Existentials (round 5 and 6): the dynamic value is opened

    @Test func existentials() {
        expect(1 as Any, 1 as Any, view: false, environment: false, state: false, "Any holding Int 1 -> 1")
        expect(1 as Any, 2 as Any, view: true, environment: true, state: true, "Any holding Int 1 -> 2")
        expect(1 as Any, 1.0 as Any, view: true, environment: true, state: true, "Any Int -> Double")
        expect(0.0 as Any, -0.0 as Any, view: true, environment: false, state: false, "Any holding Double -0.0")
        expect(Self.long() as Any, Self.long() as Any, view: false, environment: false, state: false, "Any holding long String, other buffer")
        expect(Box(1) as Any, Box(1) as Any, view: true, environment: true, state: true, "Any holding class, other object")
        expect(1 as any Equatable, 1 as any Equatable, view: false, environment: false, state: false, "any Equatable holding Int")
    }

    // MARK: Enums with a payload that are not Equatable

    /// SwiftUI compares an enum with a payload case-by-case and field-by-field.
    @Test func enumsWithAPayloadThatAreNotEquatableAreComparedByCaseAndPayload() {
        #expect(changes(.viewValue, PayloadString.b(Self.long()), PayloadString.b(Self.long())) == false)
        #expect(changes(.stateWrite, PayloadDouble.a(0.0), PayloadDouble.a(-0.0)) == false)
        #expect(changes(.environment, PayloadDouble.a(0.0), PayloadDouble.a(-0.0)) == false)
        #expect(changes(.viewValue, PayloadString.b("hi"), PayloadString.b("hi")) == false)
        #expect(changes(.viewValue, PayloadString.b("hi"), PayloadString.b("bye")) == true)
        #expect(changes(.viewValue, PayloadString.a(1), PayloadString.b("1")) == true)
        #expect(changes(.viewValue, PayloadDouble.a(0.0), PayloadDouble.a(-0.0)) == true)
    }

    // MARK: The older policies keep their behaviour

    @Test func bitsStillComparesOnlyBytes() {
        #expect(changes(.bits, Self.long(), Self.long()) == true)        // M0 behaviour
        #expect(changes(.bits, [1, 2, 3], Array((1...3).map { $0 })) == true)
        #expect(changes(.bits, 0.0, -0.0) == true)
        #expect(changes(.bits, Double.nan, Double.nan) == false)
    }

    @Test func alwaysDifferentAlwaysChanges() {
        #expect(changes(.alwaysDifferent, 1, 1))
        #expect(changes(.alwaysDifferent, "a", "a"))
    }

    @Test func theDefaultPolicyIsViewValue() {
        let graph = Graph()
        let a = graph.makeInput(Self.long())
        let before = graph.version(of: a.id)
        graph.setValue(Self.long(), for: a)      // another buffer: viewValue compares String with ==
        #expect(graph.version(of: a.id) == before)
    }

    @Test func equatableUnlessPODIgnoresPaddingInPODStructs() {
        struct PaddedPOD { var a: Int8; var b: Int64 }
        struct NestedPOD { var head: Int8; var inner: PaddedPOD }

        var p1 = PaddedPOD(a: 1, b: 2)
        var p2 = PaddedPOD(a: 1, b: 2)
        withUnsafeMutableBytes(of: &p1) { $0[1] = 0xAA }
        withUnsafeMutableBytes(of: &p2) { $0[1] = 0x55 }
        #expect(!changes(.comparison(.equatableUnlessPOD), p1, p2))

        let p3 = PaddedPOD(a: 1, b: 3)
        #expect(changes(.comparison(.equatableUnlessPOD), p1, p3))

        var n1 = NestedPOD(head: 7, inner: p1)
        var n2 = NestedPOD(head: 7, inner: p2)
        withUnsafeMutableBytes(of: &n1) { $0[1] = 0x11 }
        withUnsafeMutableBytes(of: &n2) { $0[1] = 0x22 }
        #expect(!changes(.comparison(.equatableUnlessPOD), n1, n2))
    }
}
