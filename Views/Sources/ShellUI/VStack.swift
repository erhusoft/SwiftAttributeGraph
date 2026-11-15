#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif

/// Shell of `VStack`: views arranged vertically.
public struct VStack<Content: View>: View {
    private let alignment: HorizontalAlignment
    private let spacing: CGFloat?
    private let content: Content

    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
        ShellCoverage.record("VStack")
    }

    public typealias Body = Never
    public var body: Never { fatalError("VStack is a primitive view") }
}
