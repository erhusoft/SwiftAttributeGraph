extension Graph {
    /// Selectors of ``counter(for:)``: the 14 of `AGGraphCounterQueryType`, each checked against a native probe on
    /// macOS 15.8.3 [O] except where a case says `[?]`.
    ///
    /// The engine has no shared graph contexts (`AGGraphCreateShared`), so every graph has exactly one context and the
    /// "context" selectors repeat the graph's own value [?].
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
        /// Process-wide number of the graph's default context. A graph takes two consecutive numbers from one counter
        /// that starts at `1`: the graph first, its context next (`graphID` 1 and `contextID` 2 for the first graph of
        /// the process, 3 and 4 for the second). Releasing graphs, creating subgraphs or attributes does not consume or
        /// give back numbers [O]. Native `AGGraphCreateShared` adds a context that takes one more number and keeps the
        /// graph's `graphID` [O]; the engine does not model shared contexts, so its `makeContext()` takes none [?].
        case contextID
        /// Process-wide number of the graph, always the one just before ``contextID`` [O].
        case graphID
        /// `1` while a rule of this graph is running (also in a nested rule), `0` outside any update, inside
        /// `withoutUpdate` called outside a rule, and for a graph other than the one whose rule is running [O].
        /// Native has a per-thread and a per-context variant; with one context and one thread per graph they coincide
        /// [?].
        case contextThreadUpdating
        /// `1` while a rule of this graph is running, `0` otherwise; see ``contextThreadUpdating`` [O].
        case threadUpdating
        /// `1` after ``Graph/setNeedsUpdate()``; a second call does not add up, reading an input or writing does not
        /// clear it, and the next top-level read of a rule (clean or not, direct or through an indirect attribute)
        /// sets it back to `0`. Raised inside a rule it stays up when that update ends [O]. Native tracks it per
        /// context as well as per graph; with one context they coincide [?].
        case contextNeedsUpdate
        /// Same as ``contextNeedsUpdate`` for the graph as a whole [O].
        case needsUpdate
        /// Updates started on the main thread. Equal to ``updates`` in every probe, including graphs driven from a
        /// background `Thread`, so the engine returns ``updates`` and does not look at the thread [?].
        case mainThreadUpdates
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
        case .contextID: return graphCounterID + 1
        case .graphID: return graphCounterID
        case .contextThreadUpdating, .threadUpdating: return frames.isEmpty ? 0 : 1
        case .contextNeedsUpdate, .needsUpdate: return needsUpdateFlag ? 1 : 0
        case .mainThreadUpdates: return updateCount
        }
    }
}
