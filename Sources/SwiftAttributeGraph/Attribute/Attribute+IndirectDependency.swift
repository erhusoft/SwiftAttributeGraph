extension Attribute {
    /// Attaches or detaches the producer `dependency` of this indirect attribute (Apple's setter of
    /// `AGAttribute._indirectDependency`, `AGGraphSetIndirectDependency`). Same behaviour as ``Graph/setDependency(_:for:)``.
    public func setIndirectDependency(_ dependency: AnyAttribute?) {
        graph.setDependency(dependency, for: self)
    }
}
