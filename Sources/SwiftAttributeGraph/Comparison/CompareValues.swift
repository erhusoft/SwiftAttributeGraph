/// Compares two values with a comparison mode (`compareValues(_:_:mode:)` in native AttributeGraph; default
/// `.equatableAlways`). Warm behaviour: the layout is taken as ready, as with `fetchLayoutsSynchronously`. Known difference:
/// for a struct holding a `String` with its own partial `==`, native `.equatableAlways` compares by bytes and this function
/// uses the `==`.
public func compareValues<Value>(_ lhs: Value, _ rhs: Value, mode: ComparisonMode = .equatableAlways) -> Bool {
    ValueComparator.make(.comparison(mode), for: Value.self)(lhs, rhs)
}

/// Compares two values with the mode in the low byte of `options` (`compareValues(_:_:options:)` in native AttributeGraph).
/// A value without a mode the engine models is compared bitwise.
public func compareValues<Value>(_ lhs: Value, _ rhs: Value, options: ComparisonOptions) -> Bool {
    // Measured on macOS 15.8: without copy-on-write (bit 8), mode 3 compares a POD by its bytes; with it, by `==`.
    if options.mode == .equatableAlways, !options.contains(.copyOnWrite), TypeLayout.isPOD(Value.self) {
        return bitwiseEqual(lhs, rhs)
    }
    return compareValues(lhs, rhs, mode: options.mode ?? .bitwise)
}
