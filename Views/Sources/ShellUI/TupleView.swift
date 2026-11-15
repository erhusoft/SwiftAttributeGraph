/// Several views side by side, as `ViewBuilder` produces them.
public struct TupleView<T>: View {
    public var value: T
    public init(_ value: T) { self.value = value }
    public typealias Body = Never
    public var body: Never { fatalError("TupleView is a primitive view") }
}
