extension Attribute {
    /// The value and whether it changed since the running rule last ran (`AGAttribute.changedValue` in native
    /// AttributeGraph). Outside a rule it is always `false`. Inside a rule the read records a dependency, as a plain
    /// read does.
    public func changedValue(options: AGValueOptions = []) -> (value: Value, changed: Bool) {
        let graph = self.graph
        let value = graph.value(of: self, options: Graph.ReadOptions(rawValue: options.rawValue))
        guard graph.evaluatingNode != Graph.noNode else { return (value, false) }
        return (value, graph.inputChanged(of: graph.evaluatingNode, source: id.index) ?? true)
    }
}
