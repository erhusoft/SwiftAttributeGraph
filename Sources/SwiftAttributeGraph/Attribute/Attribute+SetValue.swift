extension Attribute {
    /// Writes a new value and returns whether it changed (`AGAttribute.setValue` in native AttributeGraph). A write of an
    /// equal value returns `false` and does not dirty the readers.
    @discardableResult
    public func setValue(_ value: Value) -> Bool {
        let graph = self.graph
        let before = graph.version(of: id)
        graph.setValue(value, for: self)
        return graph.version(of: id) != before
    }
}
