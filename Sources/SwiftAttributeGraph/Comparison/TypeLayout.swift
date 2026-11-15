/// What the comparison needs to know about a type at run time, and the only place that reads the Swift runtime's type
/// metadata. Everything here runs when an attribute is created, never when a value is written.
///
/// Three things are *not* public Swift API and are isolated in this file, each with a test that fails if the runtime
/// stops behaving this way (`ComparisonResolutionTests.theLayoutReaderSeesTheFieldsOfStructsAndTuples`):
/// - `_isPOD(_:)`, from the standard library: whether a type is trivial (copying it is copying its bytes).
/// - The *kind* of a type: the first word of its metadata (`0x200` struct, `0x201` enum, `0x202` optional, `0x301`
///   tuple, `0x302` function, `0x303` existential; a class has a pointer there). Part of the stable ABI.
/// - The fields of a struct or tuple (name, offset, type), through the runtime's reflection entry points that the
///   standard library's own `_forEachField` uses.
enum TypeLayout {
    /// The shape of a type, as far as the comparison cares.
    enum Kind: Equatable {
        case structure, enumeration, optional, tuple, function, existential, reference, other
    }

    /// A stored field of a struct or tuple.
    struct Field {
        let offset: Int
        let type: Any.Type
    }

    static func kind(of type: Any.Type) -> Kind {
        let word = unsafeBitCast(type, to: UnsafePointer<UInt>.self).pointee
        switch word {
        case 0: return .reference                                       // Class metadata kind in non-ObjC runtime
        case 0x200: return .structure
        case 0x201: return .enumeration
        case 0x202: return .optional
        case 0x301: return .tuple
        case 0x302: return .function
        case 0x303: return .existential
        case 0x203, 0x300, 0x304, 0x305, 0x306: return .other
        default: return word < 0x1000 ? .other : .reference            // Class metadata with ObjC ISA pointer
        }
    }

    /// Whether the type is trivial: no references, no reference counting.
    static func isPOD(_ type: Any.Type) -> Bool {
        func open<T>(_: T.Type) -> Bool { _isPOD(T.self) }
        return _openExistential(type, do: open)
    }

    /// The stored fields of a struct or tuple, in declaration order, or `nil` for any other kind of type.
    static func fields(of type: Any.Type) -> [Field]? {
        let kind = kind(of: type)
        guard kind == .structure || kind == .tuple else { return nil }
        let count = recursiveChildCount(type)
        guard count >= 0 else { return nil }
        var fields: [Field] = []
        fields.reserveCapacity(count)
        for index in 0..<count {
            var metadata = FieldMetadata()
            let fieldType = recursiveChildMetadata(type, index: index, fieldMetadata: &metadata)
            metadata.freeName?(metadata.name)
            fields.append(Field(offset: recursiveChildOffset(type, index: index), type: fieldType))
        }
        return fields
    }
}

// MARK: - Runtime reflection entry points

/// The layout of the runtime's `_FieldReflectionMetadata`: a name, the function that frees it, and two flags.
private struct FieldMetadata {
    var name: UnsafePointer<CChar>? = nil
    var freeName: (@convention(c) (UnsafePointer<CChar>?) -> Void)? = nil
    var flags: Int = 0
}

@_silgen_name("swift_reflectionMirror_recursiveCount")
private func recursiveChildCount(_: Any.Type) -> Int

@_silgen_name("swift_reflectionMirror_recursiveChildMetadata")
private func recursiveChildMetadata(_: Any.Type, index: Int,
                                    fieldMetadata: UnsafeMutablePointer<FieldMetadata>) -> Any.Type

@_silgen_name("swift_reflectionMirror_recursiveChildOffset")
private func recursiveChildOffset(_: Any.Type, index: Int) -> Int
