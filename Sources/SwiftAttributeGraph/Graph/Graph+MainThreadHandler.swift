extension Graph {
    /// The number of updates of main-thread rules (`Graph.mainUpdates` in native AttributeGraph): the same number as
    /// `counter(for: .mainThreadUpdates)`.
    public var mainUpdates: Int {
        Int(truncatingIfNeeded: counter(for: .mainThreadUpdates))
    }

    /// Runs `body` with `handler` installed (`Graph.withMainThreadHandler(_:do:)` in native AttributeGraph; oracle scenarios `h1`
    /// to `h9`, `f0` to `f7`, `c1` to `c7`).
    ///
    /// While it is installed, a dirty rule read from the top is updated inside `handler`: it is given a closure that does the
    /// update and must run it exactly once, on the thread the rule belongs to. Native stops the program when the closure does
    /// not run (the attribute has no value) and crashes when it runs twice; this stops for the first and does not guard the
    /// second. The handler is off while that closure runs, so rules read inside do not call it again, and a clean rule never
    /// calls it. Scopes nest: the inner handler is the one called, and the outer one comes back when the inner scope ends.
    public func withMainThreadHandler(_ handler: (() -> Void) -> Void, do body: () -> Void) {
        assertOwnThread()
        precondition(!isInvalidated, "invalidated graph")
        withoutActuallyEscaping(handler) { handler in
            let previous = mainThreadHandler
            mainThreadHandler = handler
            defer { mainThreadHandler = previous }
            body()
        }
    }
}
