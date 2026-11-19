// The only file of the engine that touches platform thread-local storage.
//
// A graph belongs to one thread. While a rule runs, the engine stores the graph in a thread-local slot so that
// `Attribute.value` can find it without a global dictionary: the SwiftGraph tracking study (G5) measured an 18×
// gain from replacing `threadDictionary` with a native slot. The slot holds an *unretained* pointer: the graph is
// alive for the whole time a rule of it runs.
//
// Windows (`TlsAlloc`) is the verified path. The `pthread` branch follows the same shape but has not been compiled
// on this machine.

#if os(Windows)
import WinSDK

private let slot: DWORD = {
    let index = TlsAlloc()
    precondition(index != 0xFFFF_FFFF, "TlsAlloc failed: no thread-local slot available")
    return index
}()

private func rawGet() -> UnsafeMutableRawPointer? { TlsGetValue(slot) }
private func rawSet(_ pointer: UnsafeMutableRawPointer?) { _ = TlsSetValue(slot, pointer) }

private let subgraphSlot: DWORD = {
    let index = TlsAlloc()
    precondition(index != 0xFFFF_FFFF, "TlsAlloc failed: no thread-local slot available")
    return index
}()

private func rawGetSubgraph() -> UnsafeMutableRawPointer? { TlsGetValue(subgraphSlot) }
private func rawSetSubgraph(_ pointer: UnsafeMutableRawPointer?) { _ = TlsSetValue(subgraphSlot, pointer) }

/// A number that identifies the calling thread.
func currentThreadToken() -> UInt64 { UInt64(GetCurrentThreadId()) }

#else
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

private let key: pthread_key_t = {
    var created = pthread_key_t()
    precondition(pthread_key_create(&created, nil) == 0, "pthread_key_create failed")
    return created
}()

private func rawGet() -> UnsafeMutableRawPointer? { pthread_getspecific(key) }
private func rawSet(_ pointer: UnsafeMutableRawPointer?) { _ = pthread_setspecific(key, pointer) }

private let subgraphKey: pthread_key_t = {
    var created = pthread_key_t()
    precondition(pthread_key_create(&created, nil) == 0, "pthread_key_create failed")
    return created
}()

private func rawGetSubgraph() -> UnsafeMutableRawPointer? { pthread_getspecific(subgraphKey) }
private func rawSetSubgraph(_ pointer: UnsafeMutableRawPointer?) { _ = pthread_setspecific(subgraphKey, pointer) }

/// A number that identifies the calling thread.
func currentThreadToken() -> UInt64 {
    #if canImport(Darwin)
    return UInt64(UInt(bitPattern: pthread_self()))      // `pthread_t` is a pointer on Darwin
    #else
    return UInt64(pthread_self())                         // `pthread_t` is an integer on Linux
    #endif
}
#endif

/// The graph whose rule is running on this thread, if any.
enum ThreadLocalGraph {
    /// The graph that is evaluating a rule on this thread, or `nil` outside a rule.
    @inline(__always)
    static func current() -> Graph? {
        guard let pointer = rawGet() else { return nil }
        return Unmanaged<Graph>.fromOpaque(pointer).takeUnretainedValue()
    }

    /// Installs `graph` as the current one and returns the previous one so the caller can restore it.
    @inline(__always)
    static func install(_ graph: Graph?) -> Graph? {
        let previous = current()
        rawSet(graph.map { Unmanaged.passUnretained($0).toOpaque() })
        return previous
    }
}

/// The subgraph that `Graph.withCurrent(_:_:)` or `Subgraph.current` made current on this thread, if any. Rules do not
/// touch it.
///
/// The slot holds the subgraph's packed ID (never `0`, because generations start at 1) in a pointer-sized value, so it
/// needs no allocation. The ID is meaningful only while the subgraph is valid: `Subgraph.current` checks that.
enum ThreadLocalSubgraph {
    /// The packed ID of the current subgraph, or `0` when there is none.
    @inline(__always)
    static func get() -> UInt64 { UInt64(UInt(bitPattern: rawGetSubgraph())) }

    /// Replaces the packed ID of the current subgraph (`0` for none) and returns the previous one.
    @inline(__always)
    @discardableResult
    static func exchange(_ rawValue: UInt64) -> UInt64 {
        let previous = get()
        rawSetSubgraph(UnsafeMutableRawPointer(bitPattern: UInt(truncatingIfNeeded: rawValue)))
        return previous
    }
}
