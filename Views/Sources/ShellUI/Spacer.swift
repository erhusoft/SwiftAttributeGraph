#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif

/// Shell of `Spacer`: flexible space.
public struct Spacer: View {
    public var minLength: CGFloat?

    public init(minLength: CGFloat? = nil) {
        self.minLength = minLength
        ShellCoverage.record("Spacer")
    }

    public typealias Body = Never
    public var body: Never { fatalError("Spacer is a primitive view") }
}
