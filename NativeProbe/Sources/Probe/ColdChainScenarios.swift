/// A never-evaluated chain whose first read is the last rule: every rule reads the previous one, so the reads nest.
/// The depth is deliberately moderate: both engines overflow the native stack on a cold chain of about 5,500 to
/// 8,700 levels in release, and our debug build from about 800 (see PROFUNDIDAD_FRIA_NATIVO_VS_MOTOR.md).
func coldChainDepth() {
    let d = Driver()
    defer { d.close() }
    let depth = 500
    let counts = Counts()
    var last = d.input(0)
    for _ in 0..<depth {
        let previous = last
        last = d.rule { counts.first += 1; return d.read(previous) + 1 }
    }
    precondition(counts.first == 0)
    let value = d.read(last)
    let firstRuns = counts.first
    let again = d.read(last)
    precondition(value == depth && again == depth && firstRuns == depth && counts.first == depth)
    print("cold-chain-depth|depth=\(depth)|value=\(value)|runs=\(firstRuns)|runsAfterSecondRead=\(counts.first)")
}
