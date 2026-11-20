extension Graph {
    /// Runs `body` with `deadline` in effect, then restores the previous deadline, also when nested (the innermost
    /// deadline decides). Native AttributeGraph: `AGGraphSetDeadline` / `AGGraphGetDeadline`, which take mach ticks.
    public func withDeadline<T>(_ deadline: ContinuousClock.Instant, _ body: () -> T) -> T {
        assertOwnThread()
        let previous = self.deadline
        self.deadline = deadline
        defer { self.deadline = previous }
        return body()
    }

    /// Whether the current deadline has passed; `false` when no deadline is in effect
    /// (`AGGraphHasDeadlinePassed` in native AttributeGraph).
    public var hasDeadlinePassed: Bool {
        guard let deadline else { return false }
        return ContinuousClock.now > deadline
    }

    /// Cancels the running update when the deadline has passed, and does nothing otherwise. Like native
    /// `AGGraphCancelUpdateIfNeeded`, a rule that does not call it is never cancelled by a passed deadline.
    /// Must run inside an update: outside one the program stops, as native AttributeGraph does.
    public func cancelUpdateIfNeeded() {
        assertOwnThread()
        precondition(!frames.isEmpty, "cancelUpdateIfNeeded: no update is currently running")
        if hasDeadlinePassed { cancelUpdate() }
    }
}
