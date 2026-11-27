import Testing
@testable import SwiftAttributeGraph

/// `Rule._cachedValue(options:owner:hashValue:bodyPtr:update:)`. Native values from oracle scenario `c13`: the same `bodyPtr`
/// with `hashValue` 111, 222 and 111 gives `[101, 102, 101]`; the outer `update` closure runs once and the inner one twice.
@Suite struct RuleRawCachedValueTests {
    struct RawRule: Rule, Hashable {
        let id: Int
        var value: Int { id }
    }

    @Test func theHashValueDistinguishesEntriesAndTheOuterClosureRunsOnce() { // c13 [101, 102, 101, 1, 2]
        let graph = Graph(); let sg = graph.makeSubgraph()
        var outer = 0, inner = 0
        var body = RawRule(id: 42)
        var values: [Int] = []
        graph.withCurrent(sg) {
            withUnsafePointer(to: &body) { pointer in
                for hash in [111, 222, 111] {
                    let result = RawRule._cachedValue(options: [], owner: nil, hashValue: hash,
                                                      bodyPtr: UnsafeRawPointer(pointer)) {
                        outer += 1
                        return { _, attribute in
                            inner += 1
                            RuleContext<Int>(attribute: attribute.unsafeCast(to: Int.self)).value = 100 + inner
                        }
                    }
                    values.append(result.pointee)
                }
            }
        }
        #expect(values == [101, 102, 101])
        #expect(outer == 1)
        #expect(inner == 2)
    }

    @Test func aContextBuiltFromTheAttributeWritesItsValue() {
        let graph = Graph(); let sg = graph.makeSubgraph()
        var body = RawRule(id: 7)
        let result = graph.withCurrent(sg) {
            withUnsafePointer(to: &body) { pointer in
                RawRule._cachedValue(options: [], owner: nil, hashValue: 1, bodyPtr: UnsafeRawPointer(pointer)) {
                    { storage, attribute in
                        let rule = storage.assumingMemoryBound(to: RawRule.self).pointee
                        RuleContext<Int>(attribute: attribute.unsafeCast(to: Int.self)).value = rule.value * 3
                    }
                }.pointee
            }
        }
        #expect(result == 21)
    }

    @Test func aBodyThatWritesNothingStopsTheProgram() async { // "attribute failed to set an initial value"
        await #expect(processExitsWith: .failure) {
            let graph = Graph(); let sg = graph.makeSubgraph()
            var body = RawRule(id: 7)
            graph.withCurrent(sg) {
                withUnsafePointer(to: &body) { pointer in
                    _ = RawRule._cachedValue(options: [], owner: nil, hashValue: 1, bodyPtr: UnsafeRawPointer(pointer)) {
                        { _, _ in }
                    }
                }
            }
        }
    }
}
