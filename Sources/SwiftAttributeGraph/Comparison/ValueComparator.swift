/// Resolves a ``Comparison`` policy into a function for one value type. Called once per attribute, when it is created;
/// writing a value only calls the function that came out of here.
enum ValueComparator {
    /// The comparators already resolved by one graph, one per (value type, policy), each in the ``NodeType`` that the
    /// nodes of that type and policy share. Resolving a type walks its layout,
    /// which costs far more than creating an attribute, so a graph does it once per type.
    struct Cache {
        private struct Key: Hashable {
            let type: ObjectIdentifier
            let policy: Comparison
        }
        private var types: [Key: AnyObject] = [:]

        /// The node descriptor of `Value` under `policy`, created on first use.
        mutating func nodeType<Value>(_ policy: Comparison, for type: Value.Type) -> NodeType<Value> {
            let key = Key(type: ObjectIdentifier(Value.self), policy: policy)
            if let found = types[key] { return unsafeDowncast(found, to: NodeType<Value>.self) }
            let created = NodeType(isEqual: ValueComparator.make(policy, for: Value.self))
            types[key] = created
            return created
        }
    }

    static func make<Value>(_ policy: Comparison, for type: Value.Type) -> (Value, Value) -> Bool {
        switch policy {
        case .alwaysDifferent:
            return { _, _ in false }
        case .bits:
            return { bitwiseEqual($0, $1) }
        case .equatableUnlessPOD:
            if TypeLayout.isPOD(Value.self) { return planned(Value.self, mode: .view) }
            if let equal = equatableComparator(Value.self) { return equal }
            return { bitwiseEqual($0, $1) }
        case .viewValue:
            return planned(Value.self, mode: .view)
        case .stateWrite:
            return planned(Value.self, mode: .state)
        case .environment:
            let byState = planned(Value.self, mode: .state)
            return { bitwiseEqual($0, $1) || byState($0, $1) }
        }
    }

    private static func planned<Value>(_: Value.Type, mode: ComparisonPlan.Mode) -> (Value, Value) -> Bool {
        let size = MemoryLayout<Value>.size
        if size == 0 { return { _, _ in true } }
        let plan = ComparisonPlan.make(for: Value.self, mode: mode)
        if plan.operationCount == 1, case let .bytes(offset, count) = plan.operations[0], offset == 0, count == size {
            return { bitwiseEqual($0, $1) }                      // the whole value is bytes: the fast path of M0
        }
        return { left, right in
            withUnsafeBytes(of: left) { l in
                withUnsafeBytes(of: right) { r in plan.equal(l.baseAddress!, r.baseAddress!) }
            }
        }
    }

    /// `==` of `Value` if it is `Equatable`; `nil` otherwise.
    private static func equatableComparator<Value>(_: Value.Type) -> ((Value, Value) -> Bool)? {
        guard let type = Value.self as? any Equatable.Type else { return nil }
        func open<E: Equatable>(_: E.Type) -> (Value, Value) -> Bool {
            { left, right in
                withUnsafePointer(to: left) { l in
                    withUnsafePointer(to: right) { r in
                        UnsafeRawPointer(l).assumingMemoryBound(to: E.self).pointee
                            == UnsafeRawPointer(r).assumingMemoryBound(to: E.self).pointee
                    }
                }
            }
        }
        return open(type)
    }
}
