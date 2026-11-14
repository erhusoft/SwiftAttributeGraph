class TypedNode<Value: Equatable>: Node {
    var value: Value?

    init(owner: Int, value: Value?) {
        self.value = value
        super.init(owner: owner)
    }

    func store(_ new: Value) -> Bool {
        if let old = value, old == new { return false }
        value = new
        return true
    }
}
