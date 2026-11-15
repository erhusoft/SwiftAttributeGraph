/// Options controlling which neighbor edges ``Graph/breadthFirstSearch(from:options:_:)`` traverses (`AGSearchOptions`
/// in native AttributeGraph).
public struct SearchOptions: OptionSet, Hashable, Sendable {
    /// The underlying option bitmask.
    public var rawValue: UInt32

    /// Creates a search options set from its raw bitmask.
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Traverse input edges (attributes read by each visited node).
    public static let searchInputs = SearchOptions(rawValue: 1 << 0)

    /// Traverse output edges (attributes that read each visited node).
    public static let searchOutputs = SearchOptions(rawValue: 1 << 1)
}
