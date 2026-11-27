/// The runtime metadata of a Swift type (`AttributeGraph.Metadata` in native AttributeGraph).
///
/// Only what the engine needs is here: creating one from a type, reading the type back, equality and hashing, a
/// description, and enumerating the stored fields. Native also exposes the kind, enum tags and signature of the type.
public struct Metadata: Hashable, CustomStringConvertible, @unchecked Sendable {
    /// The type this metadata describes.
    public let type: Any.Type

    /// Creates the metadata of `type`.
    public init(_ type: Any.Type) {
        self.type = type
    }

    /// How ``forEachField(options:do:)`` walks a type (`AGTypeApplyOptions` in native AttributeGraph).
    public struct ApplyOptions: OptionSet, Sendable {
        /// The raw option bits.
        public let rawValue: UInt32

        /// Creates the options from their raw bits.
        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        /// Enumerate the stored fields of a struct (the default, no bit set).
        public static let enumerateStructFields: ApplyOptions = []
        /// Enumerate the stored fields of a class.
        public static let enumerateClassFields = ApplyOptions(rawValue: 1 << 0)
        /// Keep going when a field has a type that cannot be described.
        public static let continueAfterUnknownField = ApplyOptions(rawValue: 1 << 1)
        /// Enumerate the cases of an enum.
        public static let enumerateEnumCases = ApplyOptions(rawValue: 1 << 2)
    }

    /// Calls `body` with the name, byte offset and type of each stored field, stopping early when it returns `false`
    /// (`Metadata.forEachField(options:do:)` in native AttributeGraph). Returns `true` if every field was visited.
    ///
    /// Verified against native only for a struct with the default options (oracle scenario
    /// `cov79-e-metadata-for-each-field`). The class, enum and unknown-field options are accepted but not measured yet.
    @discardableResult
    public func forEachField(
        options: ApplyOptions,
        do body: (UnsafePointer<Int8>, Int, Any.Type) -> Bool
    ) -> Bool {
        var completed = true
        forEachStoredField(of: type) { name, offset, fieldType in
            guard completed else { return }
            if !body(name, offset, fieldType) { completed = false }
        }
        return completed
    }

    /// Whether both metadata describe the same type.
    public static func == (lhs: Metadata, rhs: Metadata) -> Bool {
        lhs.type == rhs.type
    }

    /// Hashes the identity of the type.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(type))
    }

    /// The name of the type.
    public var description: String {
        String(describing: type)
    }
}

/// The module-level `forEachField(of:do:)`, reachable by a name that the `Metadata` method of the same name does not hide.
private func forEachStoredField(of type: Any.Type, do body: (UnsafePointer<CChar>, Int, Any.Type) -> Void) {
    forEachField(of: type, do: body)
}
