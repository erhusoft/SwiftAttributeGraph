import Testing
@testable import SwiftAttributeGraph

/// `Rule._update(_:attribute:)`, `StatefulRule._update(_:attribute:)` and the aliases `Subgraph.ChildFlags` and `AttributeUpdateBlock`,
/// which native AttributeGraph declares and the engine lacked. `_update` is what `Rule.cachedValue` hands to `_cachedValue` as its update
/// (oracle scenarios `c0`, `c13`): it reads the rule from the pointer and writes its value to the attribute.
@Suite struct RuleUpdateAndAliasesTests {
    final class Counter { var runs = 0 }

    struct PlainK: Rule, Hashable {
        let id: Int
        let counter: Counter
        var value: Int { counter.runs += 1; return id * 10 }
        static func == (l: PlainK, r: PlainK) -> Bool { l.id == r.id }
        func hash(into h: inout Hasher) { h.combine(id) }
    }

    struct StatefulK: StatefulRule, Hashable {
        typealias Value = Int
        let id: Int
        let counter: Counter
        mutating func updateValue(_ context: inout RuleContext<Int>) {
            counter.runs += 1
            context.value = id * 100
        }
        static func == (l: StatefulK, r: StatefulK) -> Bool { l.id == r.id }
        func hash(into h: inout Hasher) { h.combine(id) }
    }

    @Test func aRulesUpdateWritesItsValueToTheAttribute() { // c0 [10, 1]
        let graph = Graph(); let sg = graph.makeSubgraph(); let c = Counter()
        var body = PlainK(id: 1, counter: c)
        let value = graph.withCurrent(sg) {
            withUnsafePointer(to: &body) { pointer in
                PlainK._cachedValue(options: [], owner: nil, hashValue: 1, bodyPtr: UnsafeRawPointer(pointer)) {
                    { storage, attribute in PlainK._update(storage, attribute: attribute) }
                }.pointee
            }
        }
        #expect(value == 10)
        #expect(c.runs == 1)
    }

    @Test func aStatefulRulesUpdateRunsItsUpdateValue() {
        let graph = Graph(); let sg = graph.makeSubgraph(); let c = Counter()
        let storage = UnsafeMutablePointer<StatefulK>.allocate(capacity: 1)
        storage.initialize(to: StatefulK(id: 3, counter: c))
        let node = RawCachedRuleNode<Int>(
            storage: UnsafeMutableRawPointer(storage),
            destroyStorage: { raw in
                let typed = raw.assumingMemoryBound(to: StatefulK.self)
                typed.deinitialize(count: 1); typed.deallocate()
            },
            update: { pointer, attribute in StatefulK._update(pointer, attribute: attribute) },
            typeName: "StatefulK", type: graph.comparators.nodeType(.viewValue, for: Int.self))
        let attribute = graph.withCurrent(sg) { Attribute<Int>(id: graph.allocateTypeRule(node)) }
        #expect(graph.value(of: attribute) == 300)
        #expect(c.runs == 1)
    }

    @Test func theAliasesAreTheNativeTypes() {
        #expect(ObjectIdentifier(Subgraph.ChildFlags.self) == ObjectIdentifier(AnyAttribute.Flags.self))
        let block: AttributeUpdateBlock = { { _, _ in } }
        _ = block
    }
}
