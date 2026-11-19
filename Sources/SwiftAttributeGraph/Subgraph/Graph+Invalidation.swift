/// Cancels a notice registered with ``Graph/observe(_:onInvalidate:)-(Subgraph,_)``.
public final class SubgraphObservationToken {
    private weak var graph: Graph?
    private let subgraph: SubgraphID
    private let id: Int

    init(graph: Graph, subgraph: SubgraphID, id: Int) {
        self.graph = graph
        self.subgraph = subgraph
        self.id = id
    }

    /// Stops the notice. Calling it twice, or after the subgraph died, does nothing.
    public func cancel() {
        guard let graph, graph.subgraphs.isLive(subgraph) else { return }
        graph.subgraphObservers[subgraph.index]?.removeAll { $0.id == id }
        if graph.subgraphObservers[subgraph.index]?.isEmpty ?? false { graph.subgraphObservers[subgraph.index] = nil }
    }
}

extension Graph {
    /// Calls `onInvalidate` once, when the subgraph is about to be freed (because it or an ancestor was invalidated).
    ///
    /// The notice comes before anything is freed, so the callback can still read what the subgraph owns. For several
    /// subgraphs invalidated together, parents are notified before their children and children are visited in reverse
    /// creation order (matching native AttributeGraph). If the invalidation was asked for from inside a rule or during
    /// `withoutSubgraphInvalidation`, the notices are delivered when the outermost scope ends, never inside it.
    @discardableResult
    public func observe(_ subgraph: Subgraph, onInvalidate: @escaping () -> Void) -> SubgraphObservationToken {
        assertOwnThread()
        precondition(subgraphs.isLive(subgraph.id), "observe: the subgraph was invalidated")
        let id = nextObserverID
        nextObserverID += 1
        subgraphObservers[subgraph.id.index, default: []].append(Observer(id: id, callback: onInvalidate))
        return SubgraphObservationToken(graph: self, subgraph: subgraph.id, id: id)
    }

    /// Frees the subgraph, every subgraph below it and every attribute they own. The root cannot be invalidated.
    ///
    /// Called outside a rule, it frees them before returning, after telling the observers (see
    /// ``observe(_:onInvalidate:)-(Subgraph,_)``). Called from inside a rule, or from a notice, it marks the subgraphs as
    /// *falling*: nothing can be created in them, `isValid` and `WeakAttribute` report them as invalidated immediately,
    /// direct `Attribute` handles stay readable until the outermost update ends so the update in progress finishes
    /// coherently, and the freeing happens when the outermost update ends. Invalidating a subgraph that is already
    /// falling does nothing.
    ///
    /// Rules outside the set that read what it owned have those input edges detached, keeping their cached value until
    /// another live input dirties them (matching native AttributeGraph).
    public func invalidate(_ subgraph: Subgraph) {
        assertOwnThread()
        precondition(subgraph != rootSubgraph, "invalidate: the root subgraph cannot be invalidated")
        precondition(subgraphs.isLive(subgraph.id), "invalidate: the subgraph was already invalidated")
        if subgraphs.isFalling(index: subgraph.id.index) { return }

        if evaluatingNode != Graph.noNode || isInvalidating || deferringSubgraphInvalidationDepth > 0 {
            let plan = subgraphs.invalidationPlan(from: subgraph.id.index)
            for index in plan.toInvalidate { subgraphs.setFalling(index: index, true) }
            for (p, c) in plan.detachedEdges { subgraphs.removeChild(c, from: p) }
            deferredInvalidations.append(subgraph)
            return
        }
        perform(subgraph)
        flushDeferredInvalidations()
    }

    /// Defers the physical freeing and observer callbacks of any ``invalidate(_:)`` calls executed inside `body` until
    /// the outermost `withoutSubgraphInvalidation` scope (and any active evaluation) completes.
    ///
    /// Invalidated subgraphs are marked invalid (`isValid == false`) immediately, while their attributes stay alive and
    /// readable by `WeakAttribute` until `body` returns (matching `Subgraph.withoutSubgraphInvalidation` in native
    /// AttributeGraph).
    public func withoutSubgraphInvalidation<T>(_ body: () -> T) -> T {
        assertOwnThread()
        deferringSubgraphInvalidationDepth += 1
        defer {
            deferringSubgraphInvalidationDepth -= 1
            if deferringSubgraphInvalidationDepth == 0 && evaluatingNode == Graph.noNode && !deferredInvalidations.isEmpty {
                flushDeferredInvalidations()
            }
        }
        return body()
    }

    /// Runs the invalidations that were asked for while a rule was running. Called when the outermost update ends.
    func flushDeferredInvalidations() {
        guard !isInvalidating, evaluatingNode == Graph.noNode, deferringSubgraphInvalidationDepth == 0 else { return }
        var next = 0
        while next < deferredInvalidations.count {
            let subgraph = deferredInvalidations[next]
            next += 1
            if subgraphs.isLive(subgraph.id) { perform(subgraph) }       // an ancestor may have freed it already
        }
        deferredInvalidations.removeAll(keepingCapacity: true)
    }

    private func perform(_ root: Subgraph) {
        isInvalidating = true
        defer { isInvalidating = false }

        let plan = subgraphs.invalidationPlan(from: root.id.index)
        for index in plan.toInvalidate { subgraphs.setFalling(index: index, true) }
        for (p, c) in plan.detachedEdges { subgraphs.removeChild(c, from: p) }
        let order = Array(plan.toInvalidate.reversed())                 // children before parents

        // 1. The notices, with everything still alive and readable (parents before children, reverse child creation order).
        for index in order.reversed() {
            guard let callbacks = subgraphObservers.removeValue(forKey: index) else { continue }
            for observer in callbacks { observer.callback() }
        }

        // 2. Detach the owned attributes from their neighbours outside the set before any slot is freed.
        // Falling also includes separately queued invalidations; only this set is freed by this call.
        let freeing = Set(order)
        var owned: [UInt32] = []
        for index in order { owned += subgraphs.takeMembers(of: index) }
        for node in owned {
            let n = Int(node)
            for edge in table.inputs[n] where !freeing.contains(table.owner(at: edge.source)) {
                removeOutput(node, from: edge.source, at: edge.positionInOutputs)
            }
            for dependent in table.outputs[n] where !freeing.contains(table.owner(at: dependent)) {
                let dep = Int(dependent)
                table.inputs[dep].removeAll { $0.source == node }
                if table.state[dep] & NodeState.indirect != 0,
                   let indBox = table.box(at: dependent) as? AnyIndirectNode {
                    if indBox.dependency?.index == node {
                        indBox.dependency = nil
                    }
                    if indBox.source.index == node {
                        indBox.source = indBox.initialSource
                        indBox.sourceRedirected = false
                        let initial = indBox.initialSource
                        if table.isLive(initial) && !freeing.contains(table.owner(at: initial.index)) {
                            let s = Int(initial.index)
                            indBox.sourceSeenVersion = table.state[s] & NodeState.hasValue != 0 ? table.versions[s] : 0
                        }
                    }
                    rebuildIndirectEdges(for: dependent)
                    let s = Int(indBox.source.index)
                    let depDirty = indBox.dependency.map { table.isLive($0) && table.state[Int($0.index)] & NodeState.dirty != 0 } ?? false
                    let srcDirty = table.isLive(indBox.source) && !freeing.contains(table.owner(at: indBox.source.index)) && table.state[s] & NodeState.dirty != 0
                    if depDirty || srcDirty {
                        table.state[dep] |= NodeState.dirty
                    } else {
                        table.state[dep] &= ~NodeState.dirty
                    }
                }
            }
        }

        // 3. Free the attributes, then the subgraphs.
        for node in owned {
            observers[node] = nil
            table.free(index: node)
        }
        for index in order { subgraphs.release(index: index) }

        flushNotifications()
    }
}
