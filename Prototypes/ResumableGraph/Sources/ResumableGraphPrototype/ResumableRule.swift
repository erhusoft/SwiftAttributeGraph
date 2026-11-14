protocol ResumableRule {
    associatedtype Value: Equatable
    static var initialValue: Value? { get }
    mutating func resume(_ context: inout RuleContext<Value>) -> RuleStep
}

extension ResumableRule {
    static var initialValue: Value? { nil }
}
