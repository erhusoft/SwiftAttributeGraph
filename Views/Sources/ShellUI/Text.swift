/// Shell of `Text`. The slice has the string forms only (no `LocalizedStringKey`, no styling).
public struct Text: View {
    private let content: String

    public init<S: StringProtocol>(_ content: S) {
        self.content = String(content)
        ShellCoverage.record("Text")
    }

    public init(verbatim content: String) {
        self.content = content
        ShellCoverage.record("Text")
    }

    public typealias Body = Never
    public var body: Never { fatalError("Text is a primitive view") }
}
