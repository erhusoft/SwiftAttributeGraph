/// A read/write projection of storage. Construction follows the measured closure/state distinction;
/// SwiftUI's full dynamic-property update and reconciliation lifecycle is not implemented.
@propertyWrapper
public struct Binding<Value> {
    private let get: () -> Value
    private let set: (Value) -> Void

    /// Creates a binding with explicit accessors, calling `get` once during construction.
    /// Each subsequent `wrappedValue` read calls `get` again.
    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        self.init(projecting: get, set: set)
        _ = get()
    }

    /// Projects existing state storage without reading it during construction.
    init(projecting get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        self.get = get
        self.set = set
    }

    /// Reads or writes the projected storage.
    public var wrappedValue: Value {
        get { get() }
        nonmutating set { set(newValue) }
    }

    /// Returns this binding for forwarding to another view.
    public var projectedValue: Binding<Value> { self }
}
