/// Options and type flags defining the behavioral characteristics of an attribute body
/// (`AGAttributeTypeFlags`, Swift name `_AttributeType.Flags`, in native AttributeGraph).
///
/// The bits are the ones of `AGAttributeTypeFlags.h`: the low two bits hold a comparison mode (the empty set is the bitwise one),
/// followed by `hasDestroySelf`, `mainThread`, `external` and `asyncThread`. Native values of `flags` for each kind of body were
/// measured on macOS 15.8.3 (oracle scenarios `f1` to `f9`).
public struct AttributeTypeFlags: OptionSet, Hashable, Sendable, CustomStringConvertible {
    /// The raw bits; see the static members for what each one means.
    public var rawValue: UInt32

    /// Creates the flags with the given raw value.
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Default empty flags.
    public static let none = AttributeTypeFlags([])

    /// The comparison mode `indirect` (raw 1).
    public static let comparisonModeIndirect = AttributeTypeFlags(rawValue: 1)
    /// The comparison mode `equatableUnlessPOD` (raw 2).
    public static let comparisonModeEquatableUnlessPOD = AttributeTypeFlags(rawValue: 2)
    /// The comparison mode `equatableAlways` (raw 3).
    public static let comparisonModeEquatableAlways = AttributeTypeFlags(rawValue: 3)
    /// The mask of the two comparison mode bits.
    public static let comparisonModeMask = AttributeTypeFlags(rawValue: 3)

    /// Body has its own destruction (`AGAttributeTypeFlagsHasDestroySelf`, bit 2).
    public static let hasDestroySelf = AttributeTypeFlags(rawValue: 1 << 2)
    /// Body runs on the main thread (`AGAttributeTypeFlagsMainThread`, bit 3).
    public static let mainThread = AttributeTypeFlags(rawValue: 1 << 3)
    /// Body is an external input (`AGAttributeTypeFlagsExternal`, bit 4).
    public static let external = AttributeTypeFlags(rawValue: 1 << 4)
    /// Body may run on an asynchronous thread (`AGAttributeTypeFlagsAsyncThread`, bit 5).
    public static let asyncThread = AttributeTypeFlags(rawValue: 1 << 5)

    /// Native prints the name of the C type (`AGAttributeTypeFlags(rawValue: 8)`).
    public var description: String { "AGAttributeTypeFlags(rawValue: \(rawValue))" }
}

/// The namespace native AttributeGraph gives the flags (`_AttributeType.Flags`).
public enum _AttributeType {
    /// The flags of an attribute type.
    public typealias Flags = AttributeTypeFlags
}

/// The name native AttributeGraph gives ``AttributeTypeFlags``.
public typealias AGAttributeTypeFlags = AttributeTypeFlags
/// The name native AttributeGraph gives ``ComparisonMode``.
public typealias AGComparisonMode = ComparisonMode
