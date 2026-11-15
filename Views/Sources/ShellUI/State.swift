import SwiftAttributeGraph

/// Experimental state storage. The semantic probe installs it explicitly before mounting a body.
/// Automatic property discovery, view identity and SwiftUI's full DynamicProperty lifecycle are not implemented.
@propertyWrapper
public struct State<Value> {
    private final class Storage {
        var initial: Value?
        weak var graph: Graph?
        var attribute: Attribute<Value>?
        var alive = true
        init(_ value: Value) { initial = value }

        var value: Value {
            get {
                guard let attribute else { return initial! }
                precondition(alive, "State belongs to an unmounted view")
                guard let graph else { preconditionFailure("State's graph was released") }
                return graph.value(of: attribute)
            }
            set {
                guard let attribute else { initial = newValue; return }
                precondition(alive, "State belongs to an unmounted view")
                guard let graph else { preconditionFailure("State's graph was released") }
                graph.setValue(newValue, for: attribute)
            }
        }
    }

    private let storage: Storage

    /// Creates storage with its initial value; installation into a graph is explicit in this prototype.
    public init(wrappedValue: Value) { storage = Storage(wrappedValue) }

    /// Reads state, recording a dependency when a graph-backed body is evaluating, or writes it lazily.
    public var wrappedValue: Value {
        get { storage.value }
        nonmutating set { storage.value = newValue }
    }

    /// Creates a binding that shares this state's storage without reading its value.
    public var projectedValue: Binding<Value> {
        Binding(projecting: { storage.value }, set: { storage.value = $0 })
    }

    var attributeID: AttributeID? { storage.attribute?.id }

    func install(in scope: ViewGraphScope) {
        precondition(storage.attribute == nil, "State is already installed")
        scope.requireAlive()
        storage.attribute = scope.graph.withCurrent(scope.owner) { scope.graph.makeInput(storage.initial!) }
        storage.graph = scope.graph
        storage.initial = nil // the owning subgraph is now the only persistent owner of the value
        scope.graph.observe(scope.owner) { [weak storage] in storage?.alive = false }
    }
}
