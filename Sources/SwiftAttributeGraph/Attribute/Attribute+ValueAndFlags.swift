extension Attribute {
    /// The value and its flags (`AGAttribute.valueAndFlags` in native AttributeGraph). The `changed` flag is the one
    /// ``changedValue(options:)`` reports; outside a rule the flags are empty.
    public func valueAndFlags(options: AGValueOptions = []) -> (value: Value, flags: AGChangedValueFlags) {
        let read = changedValue(options: options)
        return (read.value, read.changed ? .changed : [])
    }
}
