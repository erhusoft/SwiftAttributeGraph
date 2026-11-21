#if NATIVE_ATTRIBUTE_GRAPH
import AttributeGraph
import Darwin

/// `Probe compare-types`: native AGCompareValues on enums with payloads of different kinds, mode 0 (bitwise) and 3.
/// Each line is `case|native mode 0 result|native mode 3 result`.
func runComparisonTypesProbeIfRequested() {
    guard CommandLine.arguments.count > 1, CommandLine.arguments[1] == "compare-types" else { return }
    final class Ref { let v: Int; init(_ v: Int) { self.v = v } }
    struct Padded: Equatable { var small: Int8; var big: Int64 }
    enum IntCase { case v(Int) }
    enum DoubleCase { case v(Double) }
    enum ClassCase { case v(Ref) }
    enum ArrayCase { case v([Int]) }
    enum OptionalCase { case v(Int?) }
    enum PaddedCase { case v(Padded) }
    struct NoPad: Equatable { var a: Int64; var b: Int64 }
    enum NoPadCase { case v(NoPad) }
    struct Int8Only: Equatable { var a: Int8; var b: Int8 }
    enum Int8Case { case v(Int8Only) }
    let longA = String(repeating: "x", count: 40)
    let longB = String(repeating: "x", count: 40)
    let cases: [(String, Bool, Bool)] = [
        ("int equal", nativeEqual(IntCase.v(5), IntCase.v(5), mode: 0), nativeEqual(IntCase.v(5), IntCase.v(5), mode: 3)),
        ("int different", nativeEqual(IntCase.v(5), IntCase.v(6), mode: 0), nativeEqual(IntCase.v(5), IntCase.v(6), mode: 3)),
        ("double 1.0 vs 1.0", nativeEqual(DoubleCase.v(1.0), DoubleCase.v(1.0), mode: 0), nativeEqual(DoubleCase.v(1.0), DoubleCase.v(1.0), mode: 3)),
        ("class same instance", nativeEqual(ClassCase.v(Ref(1)), ClassCase.v(Ref(1)), mode: 0), nativeEqual(ClassCase.v(Ref(1)), ClassCase.v(Ref(1)), mode: 3)),
        ("array same content, separate storage", nativeEqual(ArrayCase.v([1, 2, 3]), ArrayCase.v([1, 2, 3]), mode: 0), nativeEqual(ArrayCase.v([1, 2, 3]), ArrayCase.v([1, 2, 3]), mode: 3)),
        ("optional int some(5) vs some(5)", nativeEqual(OptionalCase.v(5), OptionalCase.v(5), mode: 0), nativeEqual(OptionalCase.v(5), OptionalCase.v(5), mode: 3)),
        ("optional nil vs some(0)", nativeEqual(OptionalCase.v(nil), OptionalCase.v(0), mode: 0), nativeEqual(OptionalCase.v(nil), OptionalCase.v(0), mode: 3)),
        ("padded struct equal fields", nativeEqual(PaddedCase.v(Padded(small: 1, big: 2)), PaddedCase.v(Padded(small: 1, big: 2)), mode: 0), nativeEqual(PaddedCase.v(Padded(small: 1, big: 2)), PaddedCase.v(Padded(small: 1, big: 2)), mode: 3)),
        ("struct no padding equal fields", nativeEqual(NoPadCase.v(NoPad(a: 1, b: 2)), NoPadCase.v(NoPad(a: 1, b: 2)), mode: 0), nativeEqual(NoPadCase.v(NoPad(a: 1, b: 2)), NoPadCase.v(NoPad(a: 1, b: 2)), mode: 3)),
        ("struct Int8 pair equal fields", nativeEqual(Int8Case.v(Int8Only(a: 1, b: 2)), Int8Case.v(Int8Only(a: 1, b: 2)), mode: 0), nativeEqual(Int8Case.v(Int8Only(a: 1, b: 2)), Int8Case.v(Int8Only(a: 1, b: 2)), mode: 3)),
        ("long string separate storage", nativeEqual(PlanStr.b(longA), PlanStr.b(longB), mode: 0), nativeEqual(PlanStr.b(longA), PlanStr.b(longB), mode: 3)),
    ]
    for (name, m0, m3) in cases { print("types|\(name)|mode0=\(m0)|mode3=\(m3)") }
    exit(0)
}
#endif
