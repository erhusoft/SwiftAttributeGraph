#if NATIVE_ATTRIBUTE_GRAPH
import AttributeGraph

typealias Handle<Value> = AttributeGraph.Attribute<Value>

private struct NativeRule<Value>: AttributeGraph.Rule {
    let body: () -> Value
    var value: Value { body() }
}

final class Driver {
    let graph = AttributeGraph.Graph()
    let scope: AttributeGraph.Subgraph
    init() { scope = AttributeGraph.Subgraph(graph: graph); precondition(graph.counter(for: .nodes) == 0) }
    func input<V>(_ value: V) -> Handle<V> { scope.apply { Handle(value: value) } }
    func rule<V>(_ body: @escaping () -> V) -> Handle<V> { scope.apply { Handle(NativeRule(body: body)) } }
    func read<V>(_ attribute: Handle<V>) -> V { attribute.value }
    func write<V>(_ value: V, to attribute: Handle<V>) { attribute.value = value }
    func close() {
        scope.invalidate()
        precondition(!scope.isValid && graph.counter(for: .nodes) == 0)
    }
}
#else
import SwiftAttributeGraph

typealias Handle<Value> = Attribute<Value>

final class Driver {
    let graph = Graph()
    let scope: Subgraph
    init() { scope = graph.makeSubgraph() }
    func input<V>(_ value: V) -> Handle<V> { graph.withCurrent(scope) { graph.makeInput(value) } }
    func rule<V>(_ body: @escaping () -> V) -> Handle<V> { graph.withCurrent(scope) { graph.makeRule(body) } }
    func read<V>(_ attribute: Handle<V>) -> V { graph.value(of: attribute) }
    func write<V>(_ value: V, to attribute: Handle<V>) { graph.setValue(value, for: attribute) }
    func close() {
        graph.invalidate(scope)
        precondition(graph.nodeCount == 0 && graph.edgeCount == 0 && graph.liveSubgraphCount == 1)
    }
}
#endif

final class Counts { var first = 0; var second = 0 }
final class Payload { let value: Int; init(_ value: Int) { self.value = value } }

func dynamicDependencies() {
    let d = Driver()
    defer { d.close() }
    let first = d.input(0), second = d.input(100), selector = d.input(0)
    let counts = Counts()
    let selected = d.rule {
        counts.first += 1
        return d.read(selector) == 0 ? d.read(first) : d.read(second)
    }
    precondition(counts.first == 0)
    var values = [d.read(selected)], runs = [counts.first]
    for step in 0..<8 {
        switch step {
        case 0, 1: d.write(1, to: first)
        case 2: d.write(1, to: selector)
        case 3: d.write(2, to: first)
        case 4: d.write(101, to: second)
        case 5: d.write(0, to: selector)
        case 6: d.write(102, to: second)
        default: d.write(3, to: first)
        }
        values.append(d.read(selected)); runs.append(counts.first)
    }
    precondition(values == [0, 1, 1, 100, 100, 101, 2, 2, 3])
    precondition(runs == [1, 2, 2, 3, 3, 4, 5, 5, 6])
    print("dynamic|values=\(values)|runs=\(runs)")
}

func equalityCut() {
    let d = Driver()
    defer { d.close() }
    let source = d.input(0)
    let counts = Counts()
    let middle = d.rule { counts.first += 1; return d.read(source) % 2 }
    let output = d.rule { counts.second += 1; return d.read(middle) + 10 }
    var values = [d.read(output)], middleRuns = [counts.first], outputRuns = [counts.second]
    for value in [2, 2, 3, 5, 6] {
        d.write(value, to: source)
        values.append(d.read(output)); middleRuns.append(counts.first); outputRuns.append(counts.second)
    }
    precondition(values == [10, 10, 10, 11, 11, 10])
    precondition(middleRuns == [1, 2, 2, 3, 4, 5] && outputRuns == [1, 1, 1, 2, 2, 3])
    print("cut|values=\(values)|middle=\(middleRuns)|output=\(outputRuns)")
}

func coalescedWrites() {
    let d = Driver()
    defer { d.close() }
    let source = d.input(0)
    let counts = Counts()
    let output = d.rule { counts.first += 1; return d.read(source) }
    precondition(counts.first == 0)
    _ = d.read(output)
    for value in 1...100 { d.write(value, to: source) }
    let before = counts.first
    let value = d.read(output)
    let after = counts.first
    d.write(101, to: source)
    d.write(100, to: source)
    let restored = d.read(output)
    precondition(value == 100 && restored == 100)
    precondition(before == 1 && after == 2 && counts.first == 3)
    print("lazy|beforeRead=\(before)|afterRead=\(after)|value=\(value)|restoredRuns=\(counts.first)")
}

func ownedLifetime() {
    let d = Driver()
    var payload: Payload? = Payload(7)
    weak var weakPayload = payload
    let input = d.input(payload!)
    payload = nil
    let output = d.rule { d.read(input).value }
    precondition(d.read(output) == 7 && weakPayload != nil)
    #if NATIVE_ATTRIBUTE_GRAPH
    let weakAttribute = AttributeGraph.WeakAttribute(input)
    precondition(weakAttribute.attribute != nil)
    #endif
    d.close()
    precondition(weakPayload == nil)
    #if NATIVE_ATTRIBUTE_GRAPH
    precondition(weakAttribute.attribute == nil)
    #endif
    print("lifetime|payloadReleased=true|scopeInvalidated=true|nodesReturnedToBaseline=true")
}

dynamicDependencies()
equalityCut()
coalescedWrites()
ownedLifetime()
