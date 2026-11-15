#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif

/// The view that `padding` returns.
public struct _PaddingView<Content: View>: View {
    let content: Content
    let edges: Edge.Set
    let length: CGFloat?
    public typealias Body = Never
    public var body: Never { fatalError("padding is a primitive modifier") }
}

extension View {
    /// Shell of `padding(_:_:)`.
    public func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View {
        ShellCoverage.record("padding")
        return _PaddingView(content: self, edges: edges, length: length)
    }

    /// Shell of `padding(_:)`.
    public func padding(_ length: CGFloat) -> some View {
        ShellCoverage.record("padding")
        return _PaddingView(content: self, edges: .all, length: length)
    }
}
