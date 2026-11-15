import SwiftAttributeGraph

/// Internal semantic harness, not a renderer. The caller explicitly mounts each body and replaces branch scopes.
/// It never walks a view tree or recursively evaluates child bodies.
final class ViewGraphScope {
    let graph: Graph
    let owner: Subgraph
    private var alive = true

    init(graph: Graph, parent: Subgraph? = nil) {
        self.graph = graph
        owner = graph.makeSubgraph(parent: parent)
        graph.observe(owner) { [weak self] in self?.alive = false }
    }

    func requireAlive() { precondition(alive, "View scope was unmounted") }

    func mount<V: View>(_ view: V) -> Attribute<V.Body> {
        requireAlive()
        return graph.withCurrent(owner) { graph.makeRule { view.body } }
    }

    func unmount() {
        guard alive else { return }
        graph.invalidate(owner)
    }
}
