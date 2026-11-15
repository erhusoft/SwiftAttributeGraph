/// Shell of `ZStack`: views layered on top of each other.
public struct ZStack<Content: View>: View {
    private let alignment: Alignment
    private let content: Content

    public init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.content = content()
        ShellCoverage.record("ZStack")
    }

    public typealias Body = Never
    public var body: Never { fatalError("ZStack is a primitive view") }
}
