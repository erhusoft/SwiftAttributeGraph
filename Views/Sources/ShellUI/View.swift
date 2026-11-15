/// A piece of user interface. Shell of the SwiftUI protocol: only the shape, no rendering.
public protocol View {
    associatedtype Body: View
    @ViewBuilder var body: Self.Body { get }
}

/// `Never` is the body of primitive views, as in SwiftUI.
extension Never: View {
    public typealias Body = Never
    public var body: Never { fatalError("Never has no body") }
}
