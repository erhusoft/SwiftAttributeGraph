/// A rule that projects a member of `root` using a key path (matching native `AttributeGraph.Focus`).
///
/// Because `Focus` is a ``Rule``, its output value goes through the attribute's comparison policy: when `root`
/// changes only in other fields and the projected member at `keyPath` remains equal, downstream dependents of the
/// `Focus` attribute are cut.
public struct Focus<Root, Value>: Rule, _AttributeBody, CustomStringConvertible {
    /// The source attribute being projected.
    public var root: Attribute<Root>
    /// The key path extracting `Value` from `Root`.
    public var keyPath: KeyPath<Root, Value>

    /// Creates a key-path projection rule from `root` and `keyPath`.
    public init(root: Attribute<Root>, keyPath: KeyPath<Root, Value>) {
        self.root = root
        self.keyPath = keyPath
    }

    /// Reads `root` in the current graph and returns the projected member.
    public var value: Value {
        root.value[keyPath: keyPath]
    }

    /// A human-readable description of the focus rule.
    public var description: String {
        "Focus(\(root.id), \(keyPath))"
    }
}

extension Graph {
    /// Creates a rule attribute that projects `keyPath` from `root`, in the current subgraph.
    ///
    /// Changes to `root` that leave `root[keyPath: keyPath]` equal under `comparison` do not raise the projected
    /// attribute's version, cutting downstream dependents.
    public func makeFocus<Root, Value>(_ root: Attribute<Root>, keyPath: KeyPath<Root, Value>,
                                       comparison: ValuePolicy = .viewValue) -> Attribute<Value> {
        assertOwnThread()
        precondition(table.isLive(root.id), "makeFocus: the root attribute is dead")
        return makeRule(Focus(root: root, keyPath: keyPath), comparison: comparison)
    }
}
