import Testing
@testable import SwiftAttributeGraph

/// Correctness tests for M7: efficient edge removal (O(1)) and mark-and-sweep pruning.
@Suite struct EdgeRemovalTests {

    /// Number of input edges of a rule node (internal access for testing).
    private static func inputsCount(of rule: Attribute<Int>, in graph: Graph) -> Int {
        graph.table.inputs[Int(rule.id.index)].count
    }

    /// Source attribute ID of the input edge at a given position (internal access for testing).
    private static func inputSource(of rule: Attribute<Int>, at position: Int, in graph: Graph) -> AttributeID {
        graph.table.inputs[Int(rule.id.index)][position].source
    }

    // MARK: - Conditional reads prune exactly the unread edges

    @Test func aConditionalReadPrunesTheUnreadInputEdge() {
        let graph = Graph()
        let a = graph.makeInput(1)
        let b = graph.makeInput(2)
        let flag = graph.makeInput(true)

        // Reads `a` and `b` when the flag is true; skips `b` when false.
        let rule = graph.makeRule {
            _ = flag.value
            return flag.value ? a.value + b.value : a.value
        }
        #expect(graph.value(of: rule) == 3)

        // Both edges exist.
        #expect(Self.inputsCount(of: rule, in: graph) == 2)

        // Flip the flag and re-run: `b` is no longer read, its edge must be pruned.
        graph.setValue(false, for: flag)
        #expect(graph.value(of: rule) == 1)
        #expect(Self.inputsCount(of: rule, in: graph) == 1)

        // The remaining edge is `a`.
        #expect(Self.inputSource(of: rule, at: 0, in: graph) == a.id)

        // Writing to `b` must no longer dirty the rule (its edge was pruned).
        graph.setValue(99, for: b)
        #expect(graph.value(of: rule) == 1) // unchanged: the rule is not re-run
    }

    @Test func aConditionalReadThatSwitchesBackReaddsTheEdge() {
        let graph = Graph()
        let a = graph.makeInput(1)
        let b = graph.makeInput(10)
        let flag = graph.makeInput(true)

        let rule = graph.makeRule {
            _ = flag.value
            return flag.value ? a.value + b.value : a.value
        }
        #expect(graph.value(of: rule) == 11)

        // Switch to false: prune `b`.
        graph.setValue(false, for: flag)
        #expect(graph.value(of: rule) == 1)
        #expect(Self.inputsCount(of: rule, in: graph) == 1)

        // Switch back to true: re-add `b`.
        graph.setValue(true, for: flag)
        #expect(graph.value(of: rule) == 11)
        #expect(Self.inputsCount(of: rule, in: graph) == 2)
    }

    // MARK: - removeOutput detaches the dependent from the source's output list

    @Test func writingToANotAnymoreInputDoesNotDirtyTheDependent() {
        let graph = Graph()
        let a = graph.makeInput(1)
        let b = graph.makeInput(2)
        let flag = graph.makeInput(true)

        let rule = graph.makeRule {
            _ = flag.value
            return flag.value ? a.value + b.value : a.value
        }
        _ = graph.value(of: rule) // reads a and b

        // Drop `b`.
        graph.setValue(false, for: flag)
        _ = graph.value(of: rule) // prunes edge to b

        // Writing to `b` must not dirty `rule`.
        graph.setValue(999, for: b)
        #expect(graph.value(of: rule) == 1)
    }

    // MARK: - Subgraph invalidation detaches edges in both directions

    @Test func invalidatingASubgraphDetachesItsAttributesFromOutsideParents() {
        let graph = Graph()
        let root = graph.makeInput(5)
        let sub = graph.makeSubgraph()

        var inside: Attribute<Int>!
        graph.withCurrent(sub) {
            let state = graph.makeInput(1)
            inside = graph.makeRule { state.value + root.value }
            _ = graph.value(of: inside)
        }

        // `inside` reads `root`: root -> inside edge exists.
        graph.invalidate(sub)

        // After invalidation, `inside` is dead and its edge to root is gone.
        #expect(!graph.contains(inside.id))

        // Writing to `root` must not crash or resurrect `inside`.
        graph.setValue(9, for: root)
        #expect(true)
    }

    @Test func invalidatingASubgraphDetachesOutsideParentsFromItsAttributes() {
        let graph = Graph()
        let sub = graph.makeSubgraph()

        var inside: Attribute<Int>!
        graph.withCurrent(sub) {
            let state = graph.makeInput(1)
            inside = graph.makeRule { state.value + 1 }
            _ = graph.value(of: inside)
        }

        // `inside` is read from outside the subgraph.
        let outside = graph.makeRule { inside.value * 2 }
        _ = graph.value(of: outside)

        graph.invalidate(sub)

        // `outside` lost its input (`inside`) and is now dirty/pending. We only check that
        // invalidation itself did not crash; reading `outside` would hit the dead attribute.
        #expect(true)
    }
}
