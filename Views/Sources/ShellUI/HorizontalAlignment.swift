/// How views are aligned along the horizontal axis.
public struct HorizontalAlignment: Equatable, Sendable {
    private let id: Int8
    private init(_ id: Int8) { self.id = id }
    public static let leading = HorizontalAlignment(0)
    public static let center = HorizontalAlignment(1)
    public static let trailing = HorizontalAlignment(2)
}
