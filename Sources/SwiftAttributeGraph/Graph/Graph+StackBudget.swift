#if canImport(Darwin)
import Darwin
#endif

extension Graph {
    /// Bytes of native stack that must stay free below a nested rule update. Below this, the engine stops with a message
    /// instead of overflowing the stack.
    static let defaultStackMarginBytes = 64 * 1024

    /// Bytes left on the stack of the calling thread, or nil when the platform cannot report it.
    ///
    /// Stacks grow downwards: the stack top is the highest address, and the lowest usable address is the top minus the
    /// stack size. The marker is a local whose address sits at the current depth.
    func nativeStackRemainingBytes() -> Int? {
        #if canImport(Darwin)
        let thread = pthread_self()
        let top = Int(bitPattern: pthread_get_stackaddr_np(thread))
        let size = pthread_get_stacksize_np(thread)
        var marker: UInt8 = 0
        let current = withUnsafeMutablePointer(to: &marker) { Int(bitPattern: $0) }
        return current - (top - size)
        #else
        return nil
        #endif
    }

    /// True when a nested update started now would leave less stack than ``stackMarginBytes``.
    func nestedUpdateWouldExhaustStack() -> Bool {
        guard let remaining = nativeStackRemainingBytes() else { return false }
        return remaining < stackMarginBytes
    }
}
