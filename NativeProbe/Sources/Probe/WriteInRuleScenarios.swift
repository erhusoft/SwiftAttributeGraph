#if NATIVE_ATTRIBUTE_GRAPH
import AttributeGraph
#else
import SwiftAttributeGraph
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// Graph writes made from inside a rule that is tracking its reads. Adapted from the in-rule mutation probes measured
// against Apple's AttributeGraph.framework: `invalidateValue` traps there ("setting value during update"), so it runs
// isolated (`Probe write-in-rule-invalidate-value`); the two accepted variants join the compared sequence.

private struct WriteInRuleScaledRule: Rule {
    var source: Handle<Int>
    var factor: Int
    var value: Int { source.value * factor }
}

/// A rule invalidates an unrelated clean rule whose captured state it changed, outside `withoutUpdate`: native aborts.
/// Only run isolated (`Probe write-in-rule-invalidate-value`); the process is expected to stop before the last line.
func writeInRuleInvalidateValue() {
    let d = Driver()
    let x = d.input(1)
    let trigger = d.input(false)
    var salt = 10
    let salted = d.rule { () -> Int in d.read(x) + salt }
    let down = d.rule { () -> Int in d.read(salted) * 2 }
    let writer = d.rule { () -> Int in
        if d.read(trigger) {
            salt = 50
            d.invalidateValue(of: salted)
        }
        return 0
    }
    _ = d.read(down); _ = d.read(writer)
    d.write(true, to: trigger)
    print("write-in-rule-invalidate-value|before-write-in-rule")
    fflush(stdout)
    _ = d.read(writer)
    print("write-in-rule-invalidate-value|accepted")
    d.close()
}

/// The same invalidation inside `withoutUpdate`: accepted, the target runs again on its next read.
func writeInRuleInvalidateValueWithoutUpdate() {
    let d = Driver()
    defer { d.close() }
    let x = d.input(1)
    let trigger = d.input(false)
    var salt = 10
    var log: [String] = []
    let salted = d.rule { () -> Int in
        log.append("s")
        return d.read(x) + salt
    }
    let writer = d.rule { () -> Int in
        log.append("w")
        if d.read(trigger) {
            salt = 50
            d.withoutUpdate { d.invalidateValue(of: salted) }
            log.append("invalidate-salted-without-update")
        }
        return 0
    }
    var values = [d.read(salted), d.read(writer)]
    d.write(true, to: trigger)
    values.append(d.read(writer))
    values.append(d.read(salted))
    print("write-in-rule-invalidate-value-without-update|values=\(values)|log=\(log)")
}

/// A rule mutates, invalidating, the body of a rule it has just read: it keeps this update's value, stays dirty and
/// runs again on its next read.
func writeInRuleMutateBodyInvalidating() {
    let d = Driver()
    defer { d.close() }
    let x = d.input(3)
    let scaled = d.typedRule(WriteInRuleScaledRule(source: x, factor: 10))
    var log: [String] = []
    var runs = 0
    var armed = true
    let r = d.rule { () -> Int in
        runs += 1
        log.append("r\(runs)")
        let v = d.read(scaled)
        if armed {
            armed = false
            d.mutateBody(of: scaled, as: WriteInRuleScaledRule.self, invalidating: true) { $0.factor = 20 }
            log.append("mutate-scaled")
        }
        return v
    }
    var values = [d.read(r)]
    values.append(d.read(r))
    values.append(d.read(r))
    values.append(d.read(scaled))
    values.append(d.read(r))
    print("write-in-rule-mutate-body-invalidating|values=\(values)|runs=\(runs)|log=\(log)")
}

/// When the probe is launched as `Probe <scenario>`, runs only that scenario and exits.
func runIsolatedScenarioIfRequested() {
    let arguments = CommandLine.arguments
    guard arguments.count > 1, arguments[1].hasPrefix("write-in-rule-") else { return }
    switch arguments[1] {
    case "write-in-rule-invalidate-value": writeInRuleInvalidateValue()
    case "write-in-rule-invalidate-value-without-update": writeInRuleInvalidateValueWithoutUpdate()
    case "write-in-rule-mutate-body-invalidating": writeInRuleMutateBodyInvalidating()
    default:
        print("unknown-scenario|\(arguments[1])")
        exit(2)
    }
    exit(0)
}
