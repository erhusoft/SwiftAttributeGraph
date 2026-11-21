extension Attribute {
    /// Brings the attribute up to date now, so a dirty rule runs here and the next read does not run it again
    /// (`AGGraphPrefetchValue`, `prefetchValue()` in native AttributeGraph). Same effect as ``Graph/updateValue(of:)``
    /// for a rule.
    public func prefetchValue() {
        graph.updateValue(of: self)
    }
}
