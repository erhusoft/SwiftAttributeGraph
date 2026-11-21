extension Attribute {
    /// Brings the attribute up to date if it is dirty, without recording a dependency (`AGAttribute.updateValue` in native
    /// AttributeGraph). Same effect as ``Graph/updateValue(of:)``.
    public func updateValue() {
        graph.updateValue(of: self)
    }

    /// Marks a rule dirty so it runs again on its next read, even if none of its inputs changed
    /// (`AGAttribute.invalidateValue` in native AttributeGraph). Same effect as ``Graph/invalidateValue(of:)``.
    public func invalidateValue() {
        graph.invalidateValue(of: self)
    }
}
