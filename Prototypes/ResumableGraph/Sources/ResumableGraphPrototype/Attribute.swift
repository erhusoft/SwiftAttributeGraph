struct Attribute<Value: Equatable> {
    let index: Int
    let graph: GraphIdentity
    var erased: AnyAttribute { AnyAttribute(index: index, graph: graph) }
}
