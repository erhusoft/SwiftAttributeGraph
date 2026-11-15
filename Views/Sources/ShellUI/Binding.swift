/// A read/write projection of storage. This experimental slice supports closure-based bindings only.
@propertyWrapper
public struct Binding<Value> {
    private let get: () -> Value
    private let set: (Value) -> Void

    /// Creates a binding with explicit accessors.
    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
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
