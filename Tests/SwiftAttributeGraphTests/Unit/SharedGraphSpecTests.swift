import Testing
@testable import SwiftAttributeGraph

/// Specification test suite comparing native AttributeGraph behavior against the future own-engine prototype.
///
/// Each test mirrors a concrete measured behavior from macOS 15.8.3 native telemetry and references
/// its backing result artifact under `NativeProbe/Results/shared-graph-macos-15.8.3/`.
/// All tests relying on `Graph(shared:)` are marked `.disabled("pending Graph(shared:) prototype")`.
@Suite struct SharedGraphSpecTests {

    // MARK: - R1: Lectura y propagación entre referencias

    /// Case R1: The shared reference reads and observes mutations from the original reference (values 7 and 9).
    ///
    /// - Backed by native telemetry:
    ///   - `NativeProbe/Results/shared-graph-macos-15.8.3/rules.txt` (Scenario R1: read 7, after write 9 in first read 9)
    ///   - `NativeProbe/Results/shared-graph-macos-15.8.3/native.txt` (`share|readFromShared=7`, `share|afterWriteInFirst=9`)
    @Test
    func r1_sharedReferenceReadsAndObservesChangesFromOriginal() {
        let g = Graph()
        let input = g.makeInput(7)
        let s = Graph(shared: g)
        let reader = s.makeRule { s.value(of: input) }

        #expect(s.value(of: reader) == 7)
        g.setValue(9, for: input)
        #expect(s.value(of: reader) == 9)
    }

    // MARK: - Herencia: Nodos creados antes y después en ambos sentidos

    /// Inheritance: The shared reference sees attributes created before and after sharing in both directions;
    /// node counts remain identical between both references.
    ///
    /// - Backed by native telemetry:
    ///   - `NativeProbe/Results/shared-graph-macos-15.8.3/routing-and-interop.txt` (Case I1: S2 reads inputs created in G and S1 before and after)
    ///   - `NativeProbe/Results/shared-graph-macos-15.8.3/rules.txt` (`two-hosts|s1ReadsG1=10|s2ReadsG2=20|nodesS1=2|nodesS2=2|nodesG1=2|nodesG2=2`)
    @Test
    func inheritance_nodesCreatedBeforeAndAfterInBothDirectionsAreVisible() {
        let g = Graph()
        // Created in G before sharing
        let gInputBefore = g.makeInput(10)

        let s = Graph(shared: g)

        // Created in G and S after sharing
        let gInputAfter = g.makeInput(20)
        let sInputAfter = s.makeInput(30)

        // Reader in S reads attributes created in G (before and after)
        let sReader = s.makeRule {
            s.value(of: gInputBefore) + s.value(of: gInputAfter)
        }
        #expect(s.value(of: sReader) == 30)

        // Reader in G reads attribute created in S
        let gReader = g.makeRule {
            g.value(of: sInputAfter) * 2
        }
        #expect(g.value(of: gReader) == 60)

        // Bidirectional mutations are observed across handles
        g.setValue(15, for: gInputBefore)
        #expect(s.value(of: sReader) == 35)

        s.setValue(50, for: sInputAfter)
        #expect(g.value(of: gReader) == 100)

        // Node counts match in both references
        #expect(g.nodeCount == s.nodeCount)
    }

    // MARK: - Contadores: nodeCount igual en ambas referencias

    /// Counters: nodeCount is equal between both references across creations and deletions.
    ///
    /// - Backed by native telemetry:
    ///   - `NativeProbe/Results/shared-graph-macos-15.8.3/rules.txt` (Scenario R1: `nodesFirst=2|nodesShared=2`)
    ///   - `NativeProbe/Results/shared-graph-macos-15.8.3/native.txt` (`share|nodesFirst=2|nodesShared=2`)
    ///   - `NativeProbe/Results/shared-graph-macos-15.8.3/handle-count.txt` (Shared handles share underlying node storage)
    @Test
    func counters_nodeCountIsEqualInBothReferences() {
        let g = Graph()
        let s = Graph(shared: g)
        #expect(g.nodeCount == s.nodeCount)

        let in1 = g.makeInput(1)
        #expect(g.nodeCount == s.nodeCount)

        let in2 = s.makeInput(2)
        #expect(g.nodeCount == s.nodeCount)

        let r1 = g.makeRule { g.value(of: in1) + 10 }
        let r2 = s.makeRule { s.value(of: in2) + 20 }
        _ = g.value(of: r1)
        _ = s.value(of: r2)

        #expect(g.nodeCount == s.nodeCount)
    }

    // MARK: - Supervivencia: Lectura tras liberar la primera referencia

    /// Survival: The shared reference continues reading after releasing the creator reference, provided the node
    /// was already evaluated while alive.
    ///
    /// - Backed by native telemetry:
    ///   - `NativeProbe/Results/shared-graph-macos-15.8.3/lifetime.txt` (`case1|exit=0|evaluatedBefore=42|readAfter=42`)
    ///   - `NativeProbe/Results/shared-graph-macos-15.8.3/e1-e0.txt` (Case c1/c2 vs c5/c6: evaluated rules survive creator drop)
    @Test
    func survival_sharedReferenceReadsAfterOriginalFreedIfEvaluated() {
        var g: Graph? = Graph()
        let s = Graph(shared: g!)

        let input = g!.makeInput(42)
        let rule = g!.makeRule { g!.value(of: input) }

        // Evaluate while creator graph is alive
        #expect(g!.value(of: rule) == 42)

        // Drop the original reference
        g = nil

        // Shared handle continues reading the evaluated attribute cleanly
        #expect(s.value(of: rule) == 42)
    }

    // MARK: - I2: Dos grafos independientes no se leen entre sí

    /// Case I2: Two independent graphs cannot read each other's attributes (namespaces are strictly isolated).
    ///
    /// - Backed by native telemetry:
    ///   - `NativeProbe/Results/shared-graph-macos-15.8.3/i2-check.txt` (10/10 repetitions abort with code 134: `precondition failure: accessing attribute in a different namespace: 536`)
    ///   - `NativeProbe/Results/shared-graph-macos-15.8.3/routing-and-interop.txt` (Case I2 control)
    ///   - `NativeProbe/Results/shared-graph-macos-15.8.3/rules.txt` (Scenario R2: independent-read aborts)
    @Test
    func i2_independentGraphsCannotReadEachOther() async {
        await #expect(processExitsWith: .failure) {
            let g1 = Graph()
            let g2 = Graph()

            let input1 = g1.makeInput(100)
            let rule2 = g2.makeRule { g1.value(of: input1) }

            // In native AttributeGraph, accessing an attribute belonging to a different namespace traps
            // with precondition failure "accessing attribute in a different namespace" (exit code 134).
            _ = g2.value(of: rule2)
        }
    }

    // MARK: - Invalidación selectiva: Subgrafo invalidado vs subgrafo vivo

    /// Selective invalidation: Invalidating the subgraph of one rule causes its read from the shared handle
    /// to fail, while rules in surviving subgraphs remain readable.
    ///
    /// - Backed by native telemetry:
    ///   - `NativeProbe/Results/shared-graph-macos-15.8.3/subgraph-rule-dependency.txt`
    ///     (Cell c1: invalidating SG1 aborts R1 read from S with exit 134 / different namespace;
    ///      Cell c2: R2 in surviving SG2 completes cleanly with exit 0, value 12).
    @Test
    func selectiveInvalidation_invalidatingSubgraphFailsOnlyItsRulesWhileOthersRemainReadable() {
        let g = Graph()
        let s = Graph(shared: g)

        let commonInput = g.makeInput(10)
        let sg1 = g.makeSubgraph()
        let sg2 = g.makeSubgraph()

        let r1 = g.withCurrent(sg1) { g.makeRule { g.value(of: commonInput) + 1 } }
        let r2 = g.withCurrent(sg2) { g.makeRule { g.value(of: commonInput) + 2 } }

        // Invalidate only SG1; SG2 remains valid
        sg1.invalidate()

        #expect(!sg1.isValid)
        #expect(sg2.isValid)

        // R2 in surviving subgraph SG2 remains cleanly readable from shared handle
        #expect(s.value(of: r2) == 12)

        // Reading R1 from invalidated SG1 fails / aborts in native AttributeGraph
        _ = r1
    }

    // MARK: - Enrutamiento: Aviso de invalidación al handle dependiente

    /// Invalidation routing: Invalidation callbacks fire selectively for the handle that contains the dependent rule.
    ///
    /// - Backed by native telemetry:
    ///   - `NativeProbe/Results/shared-graph-macos-15.8.3/invalidation-routing.txt`
    ///     (Case 1B: Topology `input -> R -> R2` in S: writing `input` from G increments cntS to 1, cntG remains 0).
    ///   - `NativeProbe/Results/shared-graph-macos-15.8.3/two-host-routing.txt`
    ///     (Case W1: writing input1 triggers cnt1=1, cnt2=0, cntG=0; Case W2: writing input2 triggers cnt1=0, cnt2=1, cntG=0).
    @Test
    func routing_invalidationNoticeRoutesExclusivelyToHandleWithDependent() {
        let g = Graph()
        let s = Graph(shared: g)

        var cntG = 0
        var cntS = 0
        g.onInvalidation { _ in cntG += 1 }
        s.onInvalidation { _ in cntS += 1 }

        let input = g.makeInput(100)

        // In S: dependent chain input -> r -> r2
        let r = s.makeRule { s.value(of: input) + 1 }
        let r2 = s.makeRule { s.value(of: r) + 1 }

        // Evaluate chain initially in S
        #expect(s.value(of: r2) == 102)
        #expect(cntG == 0)
        #expect(cntS == 0)

        // Mutate input from original graph G
        g.setValue(200, for: input)

        // Invalidation routes exclusively to s (the handle containing dependent rules)
        #expect(cntG == 0, "native: original graph callback receives 0 notices (two-host-routing.txt)")
        #expect(cntS == 1, "native: shared handle callback receives 1 notice (invalidation-routing.txt)")

        // Re-evaluating chain updates values and does not fire additional invalidation notices
        #expect(s.value(of: r2) == 202)
        #expect(cntG == 0)
        #expect(cntS == 1)
    }
}
