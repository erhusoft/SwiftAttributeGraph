/// The two directions of a layout.
public enum Axis: Int8, CaseIterable, Hashable, Sendable {
    case horizontal, vertical

    /// A set of axes.
    public struct Set: OptionSet, Sendable {
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public static let horizontal = Set(rawValue: 1 << 0)
        public static let vertical = Set(rawValue: 1 << 1)
    }
}
