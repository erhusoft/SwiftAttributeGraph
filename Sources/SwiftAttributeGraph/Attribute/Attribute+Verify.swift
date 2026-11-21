extension Attribute {
    /// Stops the program unless the attribute holds a value of `type` (`AGGraphVerifyType` in native AttributeGraph). The
    /// native refusal is silent (an abort with no message, measured with `verify-wrong-type`).
    public func verify<T>(type: T.Type) {
        let graph = self.graph
        graph.assertOwnThread()
        precondition(graph.table.box(at: id.index) is TypedNode<T>,
                     "verify(type:): the attribute does not hold a value of type \(T.self)")
    }
}
