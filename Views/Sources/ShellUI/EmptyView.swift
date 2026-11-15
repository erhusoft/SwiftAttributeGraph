/// A view that shows nothing.
public struct EmptyView: View {
    public init() {}
    public typealias Body = Never
    public var body: Never { fatalError("EmptyView is a primitive view") }
}
