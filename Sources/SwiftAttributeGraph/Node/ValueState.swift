/// The state bits of an attribute's value, the engine's counterpart of Apple's `AGValueState`.
///
/// Only the bits the engine models are present. Apple's main-thread bits (`mainThread`, `requiresMainThread`) have no
/// meaning here because a graph is used from one thread (see the `ValueStateTests` note).
public struct ValueState: OptionSet, Sendable {
    /// The raw bits, with the same values as Apple's `AGValueState`.
    public let rawValue: UInt8

    /// Creates a state from its raw bits.
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    /// The value may be out of date: a source changed since it last ran (`AGValueStateDirty`).
    public static let dirty = ValueState(rawValue: 1 << 0)
    /// The rule must run on its next update even if no input changed (`AGValueStatePending`).
    public static let pending = ValueState(rawValue: 1 << 1)
    /// The attribute holds a value (`AGValueStateValueExists`).
    public static let valueExists = ValueState(rawValue: 1 << 3)
    /// The value was changed by its own rule during evaluation (`AGValueStateSelfModified`).
    public static let selfModified = ValueState(rawValue: 1 << 7)
}
