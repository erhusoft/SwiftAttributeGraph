

/// Options and type flags defining the behavioral characteristics of an attribute body
/// (`AGAttributeTypeFlags` in native AttributeGraph).
public struct AttributeTypeFlags: OptionSet, Hashable, Sendable {
    public var rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Default empty flags.
    public static let none = AttributeTypeFlags([])

    /// Body requires dynamic destruction cleanup.
    public static let dynamicDestruction = AttributeTypeFlags(rawValue: 1 << 0)

    /// Body participates in tree recording.
    public static let recordTree = AttributeTypeFlags(rawValue: 1 << 1)
}

public typealias AGAttributeTypeFlags = AttributeTypeFlags
public typealias AGComparisonMode = ComparisonMode
