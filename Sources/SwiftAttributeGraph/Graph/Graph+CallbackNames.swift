extension Graph {
    /// Registers `callback` on the default context: it runs for an invalidation that reaches this context through a
    /// cross-context edge (`Graph.onInvalidation` in native AttributeGraph, over `AGGraphSetInvalidationCallback`). Writes
    /// inside one context never call it.
    public func onInvalidation(_ callback: @escaping (AnyAttribute) -> Void) {
        defaultUpdateContext.setInvalidationCallback(callback)
    }
}
