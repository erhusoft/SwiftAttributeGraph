/// The result of an `if`/`else` in a builder: one of two views.
public struct _ConditionalContent<TrueContent: View, FalseContent: View>: View {
    enum Storage { case first(TrueContent), second(FalseContent) }
    let storage: Storage
    public typealias Body = Never
    public var body: Never { fatalError("_ConditionalContent is a primitive view") }
}

/// An optional view is a view: it is how an `if` without `else` builds.
extension Optional: View where Wrapped: View {
    public typealias Body = Never
    public var body: Never { fatalError("Optional is a primitive view") }
}
