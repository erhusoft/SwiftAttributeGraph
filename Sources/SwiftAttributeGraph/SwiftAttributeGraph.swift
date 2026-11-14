/// SwiftAttributeGraph: a reactive attribute-graph engine for declarative UI.
///
/// The engine is being written from scratch following `docs/PLAN-MOTOR.md`. It has no external dependencies and
/// knows nothing about views, layout or rendering: those live in the UI project that will depend on it.
public enum SwiftAttributeGraph {
    /// The engine version. It stays below 1.0 until every item of `docs/PLAN-MOTOR.md` is done.
    public static let version = "0.0.1"
}
