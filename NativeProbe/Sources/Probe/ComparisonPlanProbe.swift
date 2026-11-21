#if NATIVE_ATTRIBUTE_GRAPH
import AttributeGraph

@_silgen_name("AGCompareValues")
private func c_cmpPlan(_ lhs: UnsafeRawPointer, _ rhs: UnsafeRawPointer, _ type: Metadata, _ options: UInt32) -> Bool

private func nativeEqual<T>(_ a: T, _ b: T, mode: UInt32) -> Bool {
    var a = a, b = b
    return withUnsafePointer(to: &a) { pa in
        withUnsafePointer(to: &b) { pb in
            c_cmpPlan(UnsafeRawPointer(pa), UnsafeRawPointer(pb), Metadata(T.self), mode)
        }
    }
}

enum PlanNonEq { case a(Int), b(String) }
struct PlanDesc: CustomStringConvertible { var id: Int; var description: String { "same" } }
enum PlanCollide { case p(PlanDesc) }
enum PlanStr { case b(String) }
enum PlanDoubleCase { case a(Double) }
enum PlanTag: CustomStringConvertible { case a, b; var description: String { "same" } }

/// `Probe compare-plan`: native AGCompareValues on non-Equatable enums and optionals, for the four comparison modes.
func runComparisonPlanProbeIfRequested() {
    guard CommandLine.arguments.count > 1, CommandLine.arguments[1] == "compare-plan" else { return }
    for mode: UInt32 in 0...3 {
        let payloadDiff = nativeEqual(PlanNonEq.a(1), PlanNonEq.a(2), mode: mode)
        let caseDiff = nativeEqual(PlanNonEq.a(1), PlanNonEq.b("x"), mode: mode)
        let optionalPayload = nativeEqual(Optional(PlanNonEq.a(1)), Optional(PlanNonEq.a(2)), mode: mode)
        let collide = nativeEqual(PlanCollide.p(PlanDesc(id: 1)), PlanCollide.p(PlanDesc(id: 2)), mode: mode)
        let control = nativeEqual(PlanStr.b(String(repeating: "x", count: 40)), PlanStr.b(String(repeating: "x", count: 40)), mode: mode)
        print("compare-plan-control|mode=\(mode)|sameBytesEqual=\(control)")
        let shortS = "abc"
        let longS = String(repeating: "x", count: 40)
        let longS2 = String(repeating: "x", count: 39) + "x"
        let strRepr = nativeEqual(PlanStr.b(longS), PlanStr.b(longS2), mode: mode)
        print("compare-plan-str|mode=\(mode)|longSameContentEqual=\(strRepr)|shortVsLongDiffer=\(nativeEqual(PlanStr.b(shortS), PlanStr.b(longS), mode: mode))")
        print("compare-plan-double|mode=\(mode)|zeroVsNegZeroEqual=\(nativeEqual(PlanDoubleCase.a(0.0), PlanDoubleCase.a(-0.0), mode: mode))|samePayloadEqual=\(nativeEqual(PlanDoubleCase.a(1.0), PlanDoubleCase.a(1.0), mode: mode))")
        let tag = nativeEqual(PlanTag.a, PlanTag.b, mode: mode)
        print("compare-plan-tag|mode=\(mode)|noPayloadSameDescription=\(tag)")
        print("compare-plan|mode=\(mode)|payloadDiff=\(payloadDiff)|caseDiff=\(caseDiff)|optionalPayloadDiff=\(optionalPayload)|collideSameDescription=\(collide)")
    }
    exit(0)
}
#endif
