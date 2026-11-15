/// Which shells were used. A shell is an API type whose behaviour is not written yet: it exists so that code that uses it
/// compiles, and it says so when it is used. Not thread safe: one UI thread, like the engine.
public enum ShellCoverage {
    nonisolated(unsafe) public static var strict = false
    nonisolated(unsafe) private(set) public static var counts: [String: Int] = [:]

    /// Records that a shell was used. In strict mode the program stops with the name of the shell.
    public static func record(_ name: String) {
        if strict { fatalError("\(name) is not implemented yet (ShellCoverage.strict)") }
        counts[name, default: 0] += 1
    }

    public static func reset() { counts = [:] }

    /// One line per shell used, sorted by name: `Text: 4`.
    public static func report() -> String {
        counts.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
    }
}
