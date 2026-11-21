extension Graph {
    /// Registers `callback` on the default context: it runs when that context has pending update work (`Graph.onInvalidation`
    /// and `Graph.onUpdate` in native AttributeGraph, over `AGGraphSetUpdateCallback`). In a single context it does not run
    /// for writes or ``setNeedsUpdate()``; the multi-context case is covered by `shared-context-update-callback`.
    public func onUpdate(_ callback: @escaping () -> Void) {
        defaultUpdateContext.setUpdateCallback(callback)
    }

    /// Registers `callback` on the default context for invalidations that reach it through a cross-context edge (see
    /// `setInvalidationCallback`). Writes inside one context never call it.
    public func onInvalidation(_ callback: @escaping (AnyAttribute) -> Void) {
        defaultUpdateContext.setInvalidationCallback(callback)
    }
}
