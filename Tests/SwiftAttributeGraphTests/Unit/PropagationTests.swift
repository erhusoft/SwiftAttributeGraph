import Testing
@testable import SwiftAttributeGraph

/// Dirty propagation: who is marked when something is written. Parity E4, E5 and R3-6: the invalidation goes to the
/// readers of the written attribute, never to its owner or its siblings.
@Suite struct PropagationTests {
    @Test func aWriteDirtiesTheDependentsTransitivelyButNotTheSource() {
        let graph = Graph()
        let a = graph.makeInput(1)
        let b = graph.makeRule { a.value + 1 }
        let c = graph.makeRule { b.value + 1 }
        _ = graph.value(of: c)
        #expect(!graph.isDirty(b.id) && !graph.isDirty(c.id))

        graph.setValue(2, for: a)
        #expect(!graph.isDirty(a.id))
        #expect(graph.isDirty(b.id) && graph.isDirty(c.id))
    }

    @Test func anEqualWriteMarksNothing() {
        let graph = Graph()
        let a = graph.makeInput(1)
        let b = graph.makeRule { a.value + 1 }
        _ = graph.value(of: b)
        graph.setValue(1, for: a)
        #expect(!graph.isDirty(b.id), "E4: writing the same value does nothing")
    }

    @Test func siblingsOfTheWrittenAttributeAreNotTouched() {
        let graph = Graph()
        let first = graph.makeInput(1), second = graph.makeInput(2)
        let readsFirst = graph.makeRule { first.value }
        let readsSecond = graph.makeRule { second.value }
        _ = graph.value(of: readsFirst); _ = graph.value(of: readsSecond)
        graph.setValue(10, for: first)
        #expect(graph.isDirty(readsFirst.id))
        #expect(!graph.isDirty(readsSecond.id), "E5: only the readers of the written attribute are invalidated")
    }

    @Test func aRuleThatDoesNotReadAnAttributeIsNotDirtiedByIt() {
        let graph = Graph()
        let environment = graph.makeInput(0)
        let reader = graph.makeRule { environment.value }
        let bystander = graph.makeRule { 42 }
        _ = graph.value(of: reader); _ = graph.value(of: bystander)
        graph.setValue(1, for: environment)
        #expect(graph.isDirty(reader.id))
        #expect(!graph.isDirty(bystander.id), "E6: a node with no edge to the source is skipped")
    }

    @Test func aDependentAlreadyDirtyIsNotVisitedAgain() {
        let graph = Graph()
        let a = graph.makeInput(1)
        let b = graph.makeRule { a.value }
        let c = graph.makeRule { b.value }
        _ = graph.value(of: c)
        graph.setValue(2, for: a)
        graph.setValue(3, for: a)               // b and c are already dirty
        #expect(graph.value(of: c) == 3)
    }

    @Test func aWriteToAnAttributeNobodyReadsIsHarmless() {
        let graph = Graph()
        let a = graph.makeInput(1)
        graph.setValue(2, for: a)
        #expect(graph.value(of: a) == 2)
    }
}
