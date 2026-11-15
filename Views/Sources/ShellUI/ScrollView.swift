/// Shell of `ScrollView`. Layout, clipping, scrolling and drawing are not written: this exists so code that uses it compiles.
public struct ScrollView<Content: View>: View {
    private let axes: Axis.Set
    private let showsIndicators: Bool
    private let content: Content

    public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.content = content()
        ShellCoverage.record("ScrollView")
    }

    public typealias Body = Never
    public var body: Never { fatalError("ScrollView is a primitive view") }
}
