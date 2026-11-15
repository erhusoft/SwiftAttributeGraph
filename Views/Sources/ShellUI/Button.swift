/// Shell of `Button`. The semantic probe can invoke the action; platform input is not implemented.
public struct Button<Label: View>: View {
    private let action: () -> Void
    private let label: Label

    public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
        ShellCoverage.record("Button")
    }

    func activate() { action() }

    public typealias Body = Never
    public var body: Never { fatalError("Button is a primitive view") }
}

extension Button where Label == Text {
    public init<S: StringProtocol>(_ title: S, action: @escaping () -> Void) {
        self.init(action: action) { Text(title) }
    }
}
