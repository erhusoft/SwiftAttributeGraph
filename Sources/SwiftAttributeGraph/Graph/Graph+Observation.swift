/// One registered observer of an attribute.
struct Observer {
    let id: Int
    let callback: () -> Void
}

/// Cancels an observation made with ``Graph/observe(_:onInvalidate:)``.
public final class ObservationToken {
    private weak var graph: Graph?
    private let attribute: AttributeID
    private let id: Int

    init(graph: Graph, attribute: AttributeID, id: Int) {
        self.graph = graph
        self.attribute = attribute
        self.id = id
    }

    /// Stops the notifications. Calling it twice, or after the attribute died, does nothing.
    public func cancel() { graph?.removeObserver(id: id, of: attribute) }
}

extension Graph {
    /// Calls `onInvalidate` when the attribute becomes dirty (or, for an input, when its value changes).
    ///
    /// The call is made once per "dirty period": after it, the attribute must be read again before it can notify
    /// again. Notifications are delivered when the outermost batch ends, never in the middle of a write, and
    /// the callback may read and write the graph.
    @discardableResult
    public func observe(_ attribute: AnyAttribute, onInvalidate: @escaping () -> Void) -> ObservationToken {
        assertOwnThread()
        precondition(table.isLive(attribute.id), "observe: the attribute is dead")
        let id = nextObserverID
        nextObserverID += 1
        observers[attribute.id.index, default: []].append(Observer(id: id, callback: onInvalidate))
        table.state[Int(attribute.id.index)] |= NodeState.observed
        return ObservationToken(graph: self, attribute: attribute.id, id: id)
    }

    func removeObserver(id: Int, of attribute: AttributeID) {
        guard table.isLive(attribute) else { return }
        let index = attribute.index
        observers[index]?.removeAll { $0.id == id }
        if observers[index]?.isEmpty ?? true {
            observers[index] = nil
            table.state[Int(index)] &= ~NodeState.observed
        }
    }

    /// Runs `body` and delivers the notifications it caused once, when the outermost batch ends.
    public func withBatch<T>(_ body: () -> T) -> T {
        assertOwnThread()
        batchDepth += 1
        defer {
            batchDepth -= 1
            if batchDepth == 0 {
                flushNotifications()
                flushUpdateCallbackIfReady()
            }
        }
        return body()
    }

    func queueNotification(_ node: UInt32) {
        let n = Int(node)
        guard table.state[n] & NodeState.notifyQueued == 0 else { return }
        table.state[n] |= NodeState.notifyQueued
        pendingNotifications.append(node)
    }

    /// Delivers the queued notifications unless a batch is open or delivery is already running (a callback that
    /// writes queues more notifications, which the running loop picks up).
    func flushNotifications() {
        guard batchDepth == 0, !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }
        while !pendingNotifications.isEmpty {
            let batch = pendingNotifications
            pendingNotifications.removeAll(keepingCapacity: true)
            for node in batch {
                let n = Int(node)
                guard table.isLive(index: node), table.state[n] & NodeState.notifyQueued != 0 else { continue }
                table.state[n] &= ~NodeState.notifyQueued
                for observer in observers[node] ?? [] { observer.callback() }
            }
        }
    }
}
