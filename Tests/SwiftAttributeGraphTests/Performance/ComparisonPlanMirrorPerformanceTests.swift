import Testing
@testable import SwiftAttributeGraph

/// Cost of the view-value comparison of a non-Equatable enum with a payload (the `Mirror` path in `ComparisonPlan`)
/// against a plain struct of the same size (no `Mirror`), when the bytes differ. Release only.
/// Run with: swift test -c release -Xswiftc -enable-testing --filter ComparisonPlanMirrorPerformance
@Suite("ComparisonPlanMirrorPerformance")
struct ComparisonPlanMirrorPerformanceTests {
    enum PayloadEnum { case a(Int), b(String) }
    struct PlainPair { var x: Int; var y: String }

    @Test func measureMirrorPathAgainstAPlainStruct() {
        let count = 1_000_000
        let enumCompare = ValueComparator.make(.viewValue, for: PayloadEnum.self)
        let structCompare = ValueComparator.make(.viewValue, for: PlainPair.self)
        var hits = 0

        let start = ContinuousClock.now
        for i in 0..<count {
            if enumCompare(.a(i), .a(i &+ 1)) { hits += 1 }
        }
        let enumTime = start.duration(to: ContinuousClock.now)

        let start2 = ContinuousClock.now
        for i in 0..<count {
            if structCompare(PlainPair(x: i, y: "s"), PlainPair(x: i &+ 1, y: "s")) { hits += 1 }
        }
        let structTime = start2.duration(to: ContinuousClock.now)

        print("PERF enum payload (Mirror path), bytes differ, 1M: \(enumTime) hits \(hits)")
        print("PERF plain struct (no Mirror), bytes differ, 1M: \(structTime) hits \(hits)")
    }
}
