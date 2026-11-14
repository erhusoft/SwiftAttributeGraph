/// Resolves a ``Comparison`` policy into a function for one value type. Called once per attribute, when it is created;
/// writing a value only calls the function that came out of here.
enum ValueComparator {
    /// The comparators already resolved by one graph, one per (value type, policy). Resolving a type walks its layout,
    /// which costs far more than creating an attribute, so a graph does it once per type.
    struct Cache {
        private struct Key: Hashable {
            let type: ObjectIdentifier
            let policy: Comparison
        }
        private final class Box<Value> {
            let isEqual: (Value, Value) -> Bool
            init(_ isEqual: @escaping (Value, Value) -> Bool) { self.isEqual = isEqual }
        }
        private var boxes: [Key: AnyObject] = [:]

        mutating func comparator<Value>(_ policy: Comparison, for type: Value.Type) -> (Value, Value) -> Bool {
            let key = Key(type: ObjectIdentifier(Value.self), policy: policy)
            if let box = boxes[key] { return unsafeDowncast(box, to: Box<Value>.self).isEqual }
            let isEqual = ValueComparator.make(policy, for: Value.self)
            boxes[key] = Box(isEqual)
            return isEqual
        }
    }

    static func make<Value>(_ policy: Comparison, for type: Value.Type) -> (Value, Value) -> Bool {
        switch policy {
        case .alwaysDifferent:
            return { _, _ in false }
        case .bits:
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
}
