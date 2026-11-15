/// How views are aligned along the vertical axis.
public struct VerticalAlignment: Equatable, Sendable {
    private let id: Int8
    private init(_ id: Int8) { self.id = id }
    public static let top = VerticalAlignment(0)
    public static let center = VerticalAlignment(1)
    public static let bottom = VerticalAlignment(2)
    public static let firstTextBaseline = VerticalAlignment(3)
    public static let lastTextBaseline = VerticalAlignment(4)
}
