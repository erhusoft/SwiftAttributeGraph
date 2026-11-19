// Finds the graph of a handle. An `AttributeID` or `SubgraphID` is a slot index plus a generation; the top 16 bits of the
// generation hold a *graph tag*, a process-wide number given to each graph when it is created. The registry maps a tag
// back to its graph (weakly) so `Attribute.graph` and `Subgraph.graph` work without the handle holding a reference.
//
// The registry is the only place where graphs from different threads meet, so it has its own lock. Everything else in
// the engine keeps the rule "one thread per graph".
//
// Windows (`SRWLOCK`) is written following the same shape as `ThreadLocalGraph` but has not been compiled on this
// machine; the `pthread` branch is the verified one.

#if os(Windows)
import WinSDK

private final class RegistryLock: @unchecked Sendable {
    private var lock = SRWLOCK()
    init() { InitializeSRWLock(&lock) }
    func withLock<T>(_ body: () -> T) -> T {
        AcquireSRWLockExclusive(&lock)
        defer { ReleaseSRWLockExclusive(&lock) }
        return body()
    }
}
#else
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

private final class RegistryLock: @unchecked Sendable {
    private let mutex: UnsafeMutablePointer<pthread_mutex_t>
    init() {
        mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
        mutex.initialize(to: pthread_mutex_t())
        pthread_mutex_init(mutex, nil)
    }
    func withLock<T>(_ body: () -> T) -> T {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return body()
    }
}
#endif

/// The process-wide table from graph tag to graph.
enum GraphRegistry {
    /// Largest tag: the tag lives in the top 16 bits of an ID's generation. Tag `0` means "no tag".
    static let maxTag: UInt32 = 0xFFFF

    private struct Slot {
        weak var graph: Graph?
    }

    private struct State {
        var slots: [Slot] = [Slot()]
        /// Tags handed back by graphs that were released, oldest first.
        var released: [UInt32] = []
        var releasedHead = 0
        var next: UInt32 = 1
        /// Next value of the process-wide identifier counter behind `graphID` and `contextID`.
        var nextCounterID: UInt64 = 1
    }

    private static let lock = RegistryLock()
    nonisolated(unsafe) private static var state = State()

    /// Reserves a tag for a graph that is being created. Fresh tags are handed out in order, so the tag of a released
    /// graph is not reused until all of them have been; returns `0` when no tag is left (the graph then has no tag and
    /// its handles cannot find it).
    static func reserveTag() -> UInt32 {
        lock.withLock {
            if state.next <= maxTag {
                let tag = state.next
                state.next += 1
                state.slots.append(Slot())
                return tag
            }
            if state.releasedHead < state.released.count {
                let tag = state.released[state.releasedHead]
                state.releasedHead += 1
                if state.releasedHead > 1024 {
                    state.released.removeFirst(state.releasedHead)
                    state.releasedHead = 0
                }
                return tag
            }
            return 0
        }
    }

    /// Reserves the two consecutive numbers a new graph shows through `counter(for: .graphID)` and
    /// `counter(for: .contextID)`: the first is the graph, the second its default context. Native AttributeGraph draws
    /// both from one process-wide counter that starts at `1` and never reuses a number, so the first graph is `1`/`2`,
    /// the second `3`/`4` and so on, also after graphs were released and whatever was created inside them [O].
    static func reserveCounterIDs() -> UInt64 {
        lock.withLock {
            let id = state.nextCounterID
            state.nextCounterID += 2
            return id
        }
    }

    /// Makes `graph` the owner of `tag`. Called once the graph is fully initialized.
    static func bind(tag: UInt32, to graph: Graph) {
        guard tag != 0 else { return }
        lock.withLock { state.slots[Int(tag)].graph = graph }
    }

    /// Gives the tag back when its graph is released.
    static func release(tag: UInt32) {
        guard tag != 0 else { return }
        lock.withLock {
            state.slots[Int(tag)].graph = nil
            state.released.append(tag)
        }
    }

    /// The live graph that owns `tag`, if any.
    static func graph(forTag tag: UInt32) -> Graph? {
        guard tag != 0, tag <= maxTag else { return nil }
        return lock.withLock { Int(tag) < state.slots.count ? state.slots[Int(tag)].graph : nil }
    }
}
