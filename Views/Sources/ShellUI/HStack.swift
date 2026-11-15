#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif

/// Shell of `HStack`: views arranged horizontally.
public struct HStack<Content: View>: View {
    private let alignment: VerticalAlignment
    private let spacing: CGFloat?
    private let content: Content

    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
        ShellCoverage.record("HStack")
    }

    public typealias Body = Never
    public var body: Never { fatalError("HStack is a primitive view") }
}
