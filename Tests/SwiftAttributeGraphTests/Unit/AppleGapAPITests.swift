import Testing
@testable import SwiftAttributeGraph

/// The declarations the compile audit found missing, spelled as native AttributeGraph spells them. They are specified from the native Swift
/// interface and covered here; none was compared with the native framework yet (evidence level S in COVERAGE.md).
@Suite struct AppleGapAPITests {
    final class Seen { var attribute: AnyAttribute?; var hadValue: [Bool] = []; var initial: [Int?] = [] }

    struct ReadsItself: Rule {
        let seen: Seen
        static var initialValue: Int? { 7 }
        var value: Int {
            seen.attribute = attribute.erased
            _ = context
            return 1
        }
    }

    struct Accumulating: StatefulRule {
        typealias Value = Int
        let input: Attribute<Int>
        let seen: Seen
        static var initialValue: Int? { 100 }
        mutating func updateValue() {
            seen.attribute = attribute.erased
            seen.hadValue.append(hasValue)
            if !hasValue { value = 100 }   // native does not show `initialValue` inside `updateValue()` (`api3b1`, `api3b2`)
            value = value + input.value
        }
    }

    @Test func aRuleSeesItsOwnAttributeAndHasNoInitialValueByDefault() {
        struct Plain: Rule { var value: Int { 1 } }
        #expect(Plain.initialValue == nil)
        #expect(ReadsItself.initialValue == 7)
        let graph = Graph(); let sg = graph.makeSubgraph()
        let seen = Seen()
        let a = graph.withCurrent(sg) { Attribute(ReadsItself(seen: seen)) }
        #expect(graph.value(of: a) == 1)
        #expect(seen.attribute == a.erased)
    }

    @Test func aStatefulRuleReadsAndWritesItsValueThroughItsOwnProperties() {
        let graph = Graph(); let sg = graph.makeSubgraph()
        let seen = Seen()
        let input = graph.makeInput(1)
        let a = graph.withCurrent(sg) { Attribute(Accumulating(input: input, seen: seen)) }
        #expect(graph.value(of: a) == 101)
        graph.setValue(5, for: input)
        #expect(graph.value(of: a) == 106)
        #expect(seen.attribute == a.erased)
        #expect(seen.hadValue == [false, true])
    }

    @Test func aStatefulRuleContextOutsideTheUpdateStopsTheProgram() async {
        await #expect(processExitsWith: .failure) {
            struct Rule1: StatefulRule { typealias Value = Int; mutating func updateValue() {} }
            _ = Rule1().context
        }
    }

    @Test func descriptionsPrintTheRawIdentifier() {
        let graph = Graph(); let sg = graph.makeSubgraph()
        let a = graph.withCurrent(sg) { Attribute(value: 1) }
        #expect(a.erased.description == "#\(a.erased.id.rawValue)")
        #expect(AnyWeakAttribute(a.erased).description == a.erased.description)
        #expect(AnyWeakAttribute(nil).description == "nil")
    }

    @Test func applyMakesTheSubgraphCurrentAndReturnsTheResult() {
        let graph = Graph(); let sg = graph.makeSubgraph()
        let inside = sg.apply { Subgraph.current }
        #expect(inside == sg)
        #expect(sg.apply { 42 } == 42)
    }

    @Test func forEachVisitsTheAttributesWhoseFlagsIntersect() {
        let graph = Graph(); let sg = graph.makeSubgraph()
        let a = graph.withCurrent(sg) { Attribute(value: 1) }
        let b = graph.withCurrent(sg) { Attribute(value: 2) }
        a.flags = AnyAttribute.Flags(rawValue: 1)
        var visited: [AnyAttribute] = []
        sg.forEach(AnyAttribute.Flags(rawValue: 1)) { visited.append($0) }
        #expect(visited == [a.erased])
        _ = b
    }

    @Test func mutateBodyChangesTheStoredRuleAndInvalidatesOnRequest() {
        struct Adds: Rule { var amount: Int; var value: Int { amount } }
        let graph = Graph(); let sg = graph.makeSubgraph()
        let a = graph.withCurrent(sg) { Attribute(Adds(amount: 1)) }
        #expect(graph.value(of: a) == 1)
        a.mutateBody(as: Adds.self, invalidating: true) { $0.amount = 5 }
        #expect(graph.value(of: a) == 5)
        a.erased.mutateBody(as: Adds.self, invalidating: true) { $0.amount = 9 }
        #expect(graph.value(of: a) == 9)
    }

    @Test func addInputWithOptionsAndTokenMakesAnEdge() {
        struct Constant: Rule { var value: Int { 3 } }
        let graph = Graph(); let sg = graph.makeSubgraph()
        let source = graph.withCurrent(sg) { Attribute(value: 1) }
        let target = graph.withCurrent(sg) { Attribute(Constant()) }
        let other = graph.withCurrent(sg) { Attribute(Constant()) }
        _ = graph.value(of: target)
        _ = graph.value(of: other)
        target.addInput(source, options: [.unprefetched], token: 0)
        other.erased.addInput(source.erased, token: 1)
        #expect(graph.inputs(of: target.id).contains(source.id))
        #expect(graph.inputs(of: other.id).contains(source.id))
    }

    @Test func currentAttributeIsTheRunningRuleOrNil() {
        #expect(AnyAttribute.current == nil)
        let graph = Graph(); let sg = graph.makeSubgraph()
        let seen = Seen()
        let a = graph.withCurrent(sg) { Attribute(ReadsItself(seen: seen)) }
        _ = graph.value(of: a)
        #expect(AnyAttribute.current == nil)
    }

    @Test func anOptionalAttributeReportsChangesAndIsNilWhenEmpty() {
        let graph = Graph(); let sg = graph.makeSubgraph()
        let a = graph.withCurrent(sg) { Attribute(value: 4) }
        #expect(OptionalAttribute<Int>().changedValue() == nil)
        #expect(OptionalAttribute(a).changedValue()?.value == 4)
    }

    @Test func aStatefulRuleDoesNotSeeItsInitialValueInsideUpdateValue() { // api3b1: hv=false (native)
        struct Probe: StatefulRule {
            typealias Value = Int
            static var initialValue: Int? { 100 }
            mutating func updateValue() { value = hasValue ? -1 : 5 }
        }
        let graph = Graph(); let sg = graph.makeSubgraph()
        let a = graph.withCurrent(sg) { Attribute(Probe()) }
        #expect(graph.value(of: a) == 5)
    }

    @Test func readingTheValueOfAStatefulRuleWithNoValueStopsTheProgram() async { // api3b2: native traps even with initialValue
        await #expect(processExitsWith: .failure) {
            struct Reads: StatefulRule {
                typealias Value = Int
                static var initialValue: Int? { 100 }
                mutating func updateValue() { _ = value }
            }
            let graph = Graph(); let sg = graph.makeSubgraph()
            let a = graph.withCurrent(sg) { Attribute(Reads()) }
            _ = graph.value(of: a)
        }
    }

    @Test func forEachDefersTheInvalidationsAskedInsideItsCallbackAndDeliversThemMostRecentFirst() { // fup-e1
        let graph = Graph(); let sg = graph.makeSubgraph()
        let c1 = graph.makeSubgraph(), c2 = graph.makeSubgraph()
        var events: [String] = []
        _ = c1.addObserver { events.append("c1") }
        _ = c2.addObserver { events.append("c2") }
        let a = graph.withCurrent(sg) { Attribute(value: 1) }
        a.flags = AnyAttribute.Flags(rawValue: 1)
        var inCallback: [String] = []
        sg.forEach(AnyAttribute.Flags(rawValue: 1)) { _ in
            c1.invalidate(); c2.invalidate()
            inCallback = events
        }
        #expect(inCallback.isEmpty)
        #expect(events == ["c2", "c1"])
    }

    @Test func applyDoesNotDeliverInvalidationsRequestedByARuleThatRanInsideIt() { // fup-c
        struct Invalidates: Rule {
            let child: Subgraph
            var value: Int { child.invalidate(); return 1 }
        }
        let graph = Graph(); let sg = graph.makeSubgraph(); let child = graph.makeSubgraph()
        var observed = 0
        _ = child.addObserver { observed += 1 }
        let flagged = graph.withCurrent(sg) { Attribute(value: 1) }
        flagged.flags = AnyAttribute.Flags(rawValue: 1)
        _ = sg.apply { graph.value(of: Attribute(Invalidates(child: child))) }
        #expect(observed == 0)
        sg.forEach(AnyAttribute.Flags(rawValue: 1)) { _ in }
        #expect(observed == 1)
    }

    @Test func mutateBodyAsExternalRunsOnAValueAttribute() { // api8d: v=10
        let graph = Graph(); let sg = graph.makeSubgraph()
        let a = graph.withCurrent(sg) { Attribute(value: 10) }
        var ran = false
        a.mutateBody(as: External<Int>.self, invalidating: true) { _ in ran = true }
        #expect(ran)
        #expect(graph.value(of: a) == 10)
    }

    @Test func forEachWithNoMatchingFlagsDeliversNoPendingInvalidation() { // ver6c: obs=[0, 0]
        struct Invalidates: Rule {
            let child: Subgraph
            var value: Int { child.invalidate(); return 1 }
        }
        let graph = Graph(); let sg = graph.makeSubgraph(); let child = graph.makeSubgraph()
        var observed = 0
        _ = child.addObserver { observed += 1 }
        let r = graph.withCurrent(sg) { Attribute(Invalidates(child: child)) }
        _ = graph.value(of: r)
        sg.forEach(AnyAttribute.Flags(rawValue: 8)) { _ in }
        #expect(observed == 0)
    }

    struct InvalidatesOther: Rule {
        let other: Subgraph
        var value: Int { other.invalidate(); return 1 }
    }
    private func flagged(_ graph: Graph, in sg: Subgraph, _ raw: UInt8 = 0x08) -> Attribute<Int> {
        let a = graph.withCurrent(sg) { Attribute(value: 1) }
        a.flags = AnyAttribute.Flags(rawValue: raw)
        return a
    }

    @Test func theSummaryOfFlagsIncludesTheDescendantsAndSurvivesClearingUnlinkingAndRemoval() { // ver8c, ver8d, ver8e, ver9a, ver9d, ver9e
        let graph = Graph(); let s = graph.makeSubgraph(); let child = graph.makeSubgraph(); let grand = graph.makeSubgraph()
        s.addChild(child); child.addChild(grand)
        let a = flagged(graph, in: grand)
        let b = flagged(graph, in: grand, 0x10)
        let f = AnyAttribute.Flags(rawValue: 0x08), g = AnyAttribute.Flags(rawValue: 0x10)
        #expect(s.intersects(flags: f) && child.intersects(flags: f) && grand.intersects(flags: f))
        a.flags = []                                         // clearing does not reduce it
        #expect(s.intersects(flags: f) && s.intersects(flags: g))
        s.removeChild(child)                                 // unlinking does not reduce it
        #expect(s.intersects(flags: f))
        _ = b
    }

    @Test func aLinkedChildMarkedBeforeOrAfterEntersTheSummaryOfItsParent() { // ver8e1, ver8e2
        let graph = Graph(); let s1 = graph.makeSubgraph(); let c1 = graph.makeSubgraph()
        let s2 = graph.makeSubgraph(); let c2 = graph.makeSubgraph()
        _ = flagged(graph, in: c1)
        s1.addChild(c1)
        s2.addChild(c2)
        _ = flagged(graph, in: c2)
        #expect(s1.intersects(flags: AnyAttribute.Flags(rawValue: 0x08)))
        #expect(s2.intersects(flags: AnyAttribute.Flags(rawValue: 0x08)))
    }

    @Test func aChildThatWaitsToBeInvalidatedStillIntersectsAndOneThatDiedDoesNot() { // ver8g, ver9c, ver9f
        let graph = Graph(); let s = graph.makeSubgraph(); var child: Subgraph? = graph.makeSubgraph()
        s.addChild(child!)
        let a = flagged(graph, in: child!)
        let f = AnyAttribute.Flags(rawValue: 0x08)
        var observed = 0
        let other = graph.makeSubgraph()
        _ = other.addObserver { observed += 1 }
        let r = graph.withCurrent(s) { Attribute(InvalidatesOther(other: child!)) }
        _ = graph.value(of: r)                               // child is asked to die inside a rule: it is pending
        #expect(s.intersects(flags: f) && child!.intersects(flags: f))
        s.forEach(f) { _ in }                                // delivered here
        #expect(s.intersects(flags: f))
        #expect(!child!.intersects(flags: f))
        _ = (a, observed); child = nil
    }

    @Test func forEachDeliversEvenWhenNoAttributeIsVisitedIfTheSummaryIntersects() { // ver8c
        let graph = Graph(); let s = graph.makeSubgraph(); let child = graph.makeSubgraph(); let other = graph.makeSubgraph()
        s.addChild(child)
        _ = flagged(graph, in: child)
        var observed = 0
        _ = other.addObserver { observed += 1 }
        let r = graph.withCurrent(s) { Attribute(InvalidatesOther(other: other)) }
        _ = graph.value(of: r)
        s.removeChild(child)
        s.forEach(AnyAttribute.Flags(rawValue: 0x08)) { _ in }
        #expect(observed == 1)
    }

    class FieldsBase { var base = 1 }
    final class FieldsSub: FieldsBase { var sub = 2.0 }
    enum FieldsEnum { case payload(Int); case empty }
    struct FieldsStruct { var a = 1; var b = "x" }

    private func names(_ type: Any.Type, _ options: Metadata.ApplyOptions) -> ([String], Bool) {
        var out: [String] = []
        let ok = Metadata(type).forEachField(options: options) { name, offset, fieldType in
            out.append("\(String(cString: name))@\(offset):\(fieldType)"); return true
        }
        return (out, ok)
    }

    @Test func theFreeFunctionListsOnlyTheFieldsOfAStruct() { // ver11d1 to ver11d6
        func collect(_ type: Any.Type) -> [String] {
            var free: [String] = []
            forEachField(of: type) { name, _, _ in free.append(String(cString: name)) }
            return free
        }
        #expect(collect(FieldsStruct.self) == ["a", "b"])
        #expect(collect(FieldsSub.self).isEmpty)
        #expect(collect(FieldsEnum.self).isEmpty)
        #expect(collect((Int, String).self).isEmpty)
        #expect(collect(Optional<Int>.self).isEmpty)
    }

    @Test func metadataFieldsOfAClassAnEnumAndATuple() { // ver11d1 to ver11d4
        let cls = names(FieldsSub.self, .enumerateClassFields)
        #expect(cls.0 == ["base@16:Int", "sub@24:Double"])
        #expect(cls.1)
        let en = names(FieldsEnum.self, .enumerateEnumCases)
        #expect(en.0 == ["payload@0:Int"])
        #expect(en.1)
        let tuple = names((Int, String).self, [])
        #expect(tuple.0.isEmpty)
        #expect(!tuple.1)
    }

    enum FieldsMulti { case first(Int); case second(String); case none }
    enum FieldsGeneric<T> { case a(T); case b }

    @Test func enumCasesNumberThePayloadCasesAndResolveGenericPayloads() { // ver12d2
        #expect(names(FieldsMulti.self, .enumerateEnumCases).0 == ["first@0:Int", "second@1:String"])
        let generic = names(FieldsGeneric<Int>.self, .enumerateEnumCases)
        #expect(generic.0 == ["a@0:Int"])
        #expect(generic.1)
    }

    @Test func defaultOptionsOnAClassOrAnEnumGiveNothingAndFail() { // ver12d1
        let cls = names(FieldsSub.self, [])
        #expect(cls.0.isEmpty)
        #expect(!cls.1)
        let en = names(FieldsEnum.self, [])
        #expect(en.0.isEmpty)
        #expect(!en.1)
    }

    @Test func invalidationsAskedInsideAMainThreadHandlerBodyWaitForTheNextForEach() { // ver12a1
        let graph = Graph(); let s = graph.makeSubgraph(); let child = graph.makeSubgraph()
        _ = flagged(graph, in: s)
        var observed = 0
        _ = child.addObserver { observed += 1 }
        graph.withMainThreadHandler({ $0() }) { child.invalidate() }
        #expect(observed == 0)
        s.forEach(AnyAttribute.Flags(rawValue: 0x08)) { _ in }
        #expect(observed == 1)
    }

    @Test func aPendingInvalidationMarksOnlyItsSubgraphAndDroppingAChildDeliversIt() { // ver14b1, ver14b2
        let graph = Graph()
        var s0: SubgraphLease? = SubgraphLease(graph: graph), s1: SubgraphLease? = SubgraphLease(graph: graph)
        s0!.subgraph.addChild(s1!.subgraph)
        var events: [String] = []
        _ = s0!.subgraph.addObserver { events.append("s0") }
        _ = s1!.subgraph.addObserver { events.append("s1") }
        let other = SubgraphLease(graph: graph)
        let rule = graph.withCurrent(other.subgraph) { Attribute(InvalidatesOther(other: s0!.subgraph)) }
        _ = graph.value(of: rule)
        #expect(!s0!.subgraph.isValid)
        #expect(s1!.subgraph.isValid)
        s0 = nil
        #expect(events.isEmpty)
        s1 = nil
        #expect(events == ["s1", "s0"])
    }

    @Test func writingAValueAttributeThatHasInputsStopsTheProgram() async { // ver14b3b
        await #expect(processExitsWith: .failure) {
            let graph = Graph(); let sg = graph.makeSubgraph()
            let a = graph.withCurrent(sg) { Attribute(value: 1) }
            let b = graph.withCurrent(sg) { Attribute(value: 2) }
            b.addInput(a.erased)
            graph.setValue(3, for: b)
        }
    }

    @Test func forEachVisitsInTheReverseOfTheOrderTheFlagsWereSet() { // ver15b
        let graph = Graph(); let sg = graph.makeSubgraph()
        let attrs = (0..<5).map { _ in graph.withCurrent(sg) { Attribute(value: 0) } }
        let f = AnyAttribute.Flags(rawValue: 1)
        for i in [0, 2, 1, 4, 3] { attrs[i].flags = f }
        var order: [AnyAttribute] = []
        sg.forEach(f) { order.append($0) }
        #expect(order == [3, 4, 1, 2, 0].map { attrs[$0].erased })
    }
}
