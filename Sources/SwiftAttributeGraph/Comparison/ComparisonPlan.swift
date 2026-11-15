/// A precomputed way of comparing two values of one type, built when an attribute is created.
///
/// The plan lists, for the fields of the type, which bytes to compare and which fields to compare with `==`. Padding
/// bytes are in no operation, so they never count. Adjacent byte ranges are merged: a trivial struct is a single range.
/// The plan is built by walking the *type* (its nesting is fixed and small), never the data.
struct ComparisonPlan {
    /// How the leaves of a type are compared (`docs/DISENO-M2.md` §2).
    enum Mode {
        /// A trivial leaf is compared by its bytes even if it is `Equatable` (the properties of a view).
        case view
        /// Every `Equatable` leaf is compared with `==`, trivial ones included (`@State` writes and the environment).
        case state
    }

    /// One step of a comparison.
    enum Operation {
        case bytes(offset: Int, count: Int)
        case custom(offset: Int, compare: (UnsafeRawPointer, UnsafeRawPointer) -> Bool)
    }

    let operations: [Operation]

    /// The number of steps; a trivial struct without padding has one.
    var operationCount: Int { operations.count }

    /// Whether the two values (given by the address of their storage) are equal under the plan.
    func equal(_ left: UnsafeRawPointer, _ right: UnsafeRawPointer) -> Bool {
        for operation in operations {
            switch operation {
            case let .bytes(offset, count):
                if !bytesEqual(left + offset, right + offset, count) { return false }
            case let .custom(offset, compare):
                if !compare(left + offset, right + offset) { return false }
            }
        }
        return true
    }

    // MARK: Building

    static func make<Value>(for type: Value.Type, mode: Mode) -> ComparisonPlan {
        var builder = Builder(mode: mode)
        builder.append(type, at: 0)
        return ComparisonPlan(operations: builder.finished())
    }

    private struct Builder {
        let mode: Mode
        var operations: [Operation] = []

        mutating func append(_ type: Any.Type, at offset: Int) {
            func open<X>(_: X.Type) { appendTyped(X.self, at: offset) }
            _openExistential(type, do: open)
        }

        private mutating func appendTyped<X>(_: X.Type, at offset: Int) {
            let size = MemoryLayout<X>.size
            if size == 0 { return }
            let kind = TypeLayout.kind(of: X.self)
            let pod = TypeLayout.isPOD(X.self)

            if mode == .view && pod {
                if appendFields(of: X.self, kind: kind, at: offset) { return }
                operations.append(.bytes(offset: offset, count: size))
                return
            }
            if let equal = equatableOperation(X.self) {
                if mode == .state && pod && isIntegerLike(X.self) {
                    operations.append(.bytes(offset: offset, count: size))      // for these `==` is the bytes
                } else {
                    operations.append(.custom(offset: offset, compare: equal))
                }
                return
            }
            switch kind {
            case .structure, .tuple:
                if appendFields(of: X.self, kind: kind, at: offset) { return }
                operations.append(.bytes(offset: offset, count: size))
            case .enumeration, .optional:
                if mode == .view && pod {
                    operations.append(.bytes(offset: offset, count: size))
                } else {
                    operations.append(.custom(offset: offset, compare: enumOperation(X.self, mode: mode)))
                }
            case .existential:
                operations.append(.custom(offset: offset, compare: dynamicOperation(X.self, mode: mode)))
            default:
                // References (identity), functions (pointer and context), metatypes: the bytes.
                operations.append(.bytes(offset: offset, count: size))
            }
        }

        /// Appends the fields of a struct or tuple. `false` if the type has none to walk.
        private mutating func appendFields(of type: Any.Type, kind: TypeLayout.Kind, at offset: Int) -> Bool {
            guard kind == .structure || kind == .tuple, let fields = TypeLayout.fields(of: type), !fields.isEmpty else {
                return false
            }
            for field in fields { append(field.type, at: offset + field.offset) }
            return true
        }

        /// Sorts nothing (fields come in order) and merges byte ranges that touch.
        func finished() -> [Operation] {
            var merged: [Operation] = []
            for operation in operations {
                if case let .bytes(offset, count) = operation,
                   case let .bytes(previousOffset, previousCount)? = merged.last,
                   previousOffset + previousCount == offset {
                    merged[merged.count - 1] = .bytes(offset: previousOffset, count: previousCount + count)
                } else {
                    merged.append(operation)
                }
            }
            return merged
        }
    }
}

// MARK: - Leaves

/// `==` of an `Equatable` type, read through the storage of two values; `nil` if the type is not `Equatable`.
private func equatableOperation<X>(_: X.Type) -> ((UnsafeRawPointer, UnsafeRawPointer) -> Bool)? {
    guard let equatable = X.self as? any Equatable.Type else { return nil }
    return makeEquatableOperation(equatable)
}

private func makeEquatableOperation<E: Equatable>(_: E.Type) -> (UnsafeRawPointer, UnsafeRawPointer) -> Bool {
    { left, right in left.assumingMemoryBound(to: E.self).pointee == right.assumingMemoryBound(to: E.self).pointee }
}

/// Types whose `==` is the comparison of their bytes, so the bytes can be compared directly.
private func isIntegerLike<X>(_: X.Type) -> Bool { X.self is any FixedWidthInteger.Type || X.self == Bool.self }

/// The comparison of an existential (`Any`, `any P`): the dynamic types must be equal and the values are compared with
/// the rules of the mode for that dynamic type. The plan of each dynamic type is built once and kept.
private func dynamicOperation<X>(_: X.Type, mode: ComparisonPlan.Mode) -> (UnsafeRawPointer, UnsafeRawPointer) -> Bool {
    let cache = DynamicPlans(mode: mode)
    return { left, right in
        let a: Any = left.assumingMemoryBound(to: X.self).pointee
        let b: Any = right.assumingMemoryBound(to: X.self).pointee
        return cache.equal(a, b)
    }
}

/// The comparison of a non-`Equatable` enum or optional: first checks raw bytes, then compares the active case name
/// and associated payload using the mode's comparison rules.
private func enumOperation<X>(_: X.Type, mode: ComparisonPlan.Mode) -> (UnsafeRawPointer, UnsafeRawPointer) -> Bool {
    let size = MemoryLayout<X>.size
    let cache = DynamicPlans(mode: mode)
    return { left, right in
        if bytesEqual(left, right, size) { return true }
        let a = left.assumingMemoryBound(to: X.self).pointee
        let b = right.assumingMemoryBound(to: X.self).pointee
        let mirrorA = Mirror(reflecting: a)
        let mirrorB = Mirror(reflecting: b)
        let childA = mirrorA.children.first
        let childB = mirrorB.children.first
        if let childA, let childB {
            guard childA.label == childB.label else { return false }
            return cache.equal(childA.value, childB.value)
        }
        return childA == nil && childB == nil && String(describing: a) == String(describing: b)
    }
}

/// The plans already built for the dynamic types seen by one existential leaf. One graph, one thread: no locking.
private final class DynamicPlans {
    let mode: ComparisonPlan.Mode
    private var plans: [ObjectIdentifier: ComparisonPlan] = [:]

    init(mode: ComparisonPlan.Mode) { self.mode = mode }

    func equal(_ a: Any, _ b: Any) -> Bool {
        guard type(of: a) == type(of: b) else { return false }
        // Open the dynamic *type* (opening the `Any` value itself would hand back `Any` again).
        func compare<A>(_: A.Type) -> Bool {
            let key = ObjectIdentifier(A.self)
            let plan: ComparisonPlan
            if let known = plans[key] {
                plan = known
            } else {
                plan = ComparisonPlan.make(for: A.self, mode: mode)
                plans[key] = plan
            }
            let left = a as! A
            let right = b as! A
            return withUnsafeBytes(of: left) { l in
                withUnsafeBytes(of: right) { r in
                    l.count == 0 || plan.equal(l.baseAddress!, r.baseAddress!)
                }
            }
        }
        return _openExistential(type(of: a), do: compare)
    }
}
