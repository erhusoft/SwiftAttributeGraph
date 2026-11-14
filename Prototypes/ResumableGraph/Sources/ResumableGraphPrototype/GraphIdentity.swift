// Handles retain this token, never the graph, so a released graph's address cannot alias a later graph.
final class GraphIdentity: Equatable {
    static func == (left: GraphIdentity, right: GraphIdentity) -> Bool { left === right }
}
