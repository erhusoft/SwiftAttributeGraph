extension Graph {
    /// Selectors of ``counter(for:)``: the subset of `AGGraphCounterQueryType` that the engine reproduces.
    ///
    /// Native AttributeGraph has 14 selectors. The engine implements the ones whose value follows an event the engine
    /// also has, each checked against a native probe on macOS 15.8.3 [O]. The rest are not provided [?]:
    /// `contextID` and `graphID` (process-wide identifiers, `2`/`1` for the first graph and `4`/`3` for the second),
    /// `contextThreadUpdating` and `threadUpdating` (`1` inside an update on the main thread, `0` outside),
    /// `contextNeedsUpdate` and `needsUpdate` (`1` after `setNeedsUpdate`, back to `0` at the next read of a rule) and
    /// `mainThreadUpdates` (equal to `updates` in every probe, all of them on the main thread).
    public enum CounterQueryType: Sendable {
        /// Live attributes (`nodeCount`). Native AttributeGraph does not count indirect attributes here, the engine does
        /// (a rule plus an indirect attribute over it is `1` natively and `2` here) [O].
        case nodes
        /// Top-level reads of a rule attribute: a read outside any update that asks for the value of a rule, clean or
        /// not, directly or through an indirect attribute. Reading an input, or reading from inside a rule, is not a
        /// transaction [O].
        case transactions
        /// Updates started: one per top-level read that finds a dirty rule, plus one for every attribute that has no
        /// value yet and is first evaluated inside another update. Re-evaluating a dirty chain is one update, whatever
        /// its depth [O].
        case updates
        /// Value changes: every input created (with its initial value), every input write that differs, and every
        /// rule result that differs from the previous one (the first result counts) [O].
        case changes
        /// Attributes ever created, live or freed. Indirect attributes are counted here and not natively [O].
        case createdNodes
        /// Live subgraphs. The graph's root subgraph does not exist in native AttributeGraph and is not counted.
        case subgraphs
        /// Subgraphs ever created, live or freed, the root excluded.
        case createdSubgraphs
    }

    /// The value of a counter of the graph (`AGGraphGetCounter` in native AttributeGraph).
    ///
    /// Counters only grow, except ``CounterQueryType/nodes`` and ``CounterQueryType/subgraphs``, which are the number of
    /// live attributes and subgraphs. Native values for every selector in a fresh graph, after creating attributes,
    /// after a write and a read that re-evaluates a rule, and after invalidating a subgraph are in
    /// `docs/AUDITORIA-PARIDAD-MOTOR.md`.
    public func counter(for query: CounterQueryType) -> UInt64 {
        assertOwnThread()
        switch query {
        case .nodes: return UInt64(table.liveCount)
        case .transactions: return transactionCount
        case .updates: return updateCount
        case .changes: return changeCount
        case .createdNodes: return createdNodeCount
        case .subgraphs: return UInt64(subgraphs.liveCount - 1)
        case .createdSubgraphs: return UInt64(subgraphs.createdCount - 1)
        }
    }
}
