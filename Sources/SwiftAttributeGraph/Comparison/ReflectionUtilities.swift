import Foundation

/// The layout of the runtime's `_FieldReflectionMetadata`: a name, the function that frees it, and two flags.
struct FieldReflectionMetadata {
    var name: UnsafePointer<CChar>? = nil
    var freeName: (@convention(c) (UnsafePointer<CChar>?) -> Void)? = nil
    var flags: Int = 0
}

@_silgen_name("swift_reflectionMirror_recursiveCount")
func recursiveChildCount(_: Any.Type) -> Int

@_silgen_name("swift_reflectionMirror_recursiveChildMetadata")
func recursiveChildMetadata(_: Any.Type, index: Int,
                            fieldMetadata: UnsafeMutablePointer<FieldReflectionMetadata>) -> Any.Type

@_silgen_name("swift_reflectionMirror_recursiveChildOffset")
func recursiveChildOffset(_: Any.Type, index: Int) -> Int

/// Iterates through the declared stored fields of `type`, invoking `body` with the field name,
/// byte offset, and type metadata (`AttributeGraph.forEachField(of:do:)`).
public func forEachField(
    of type: Any.Type,
    do body: (UnsafePointer<CChar>, Int, Any.Type) -> Void
) {
    // Native lists only the fields of a struct here: a class, an enum and a tuple give nothing [O, `ver11d1` to `ver11d4`].
    guard MetadataKind(of: type) == .structure else { return }
    forEachRuntimeField(of: type, do: body)
}

/// The kind of a type's metadata, read from its first word.
enum MetadataKind {
    case structure, enumeration, optional, tuple, `class`, other

    init(of type: Any.Type) {
        let word = unsafeBitCast(type, to: UnsafePointer<Int>.self).pointee
        switch word {
        case 0x200: self = .structure
        case 0x201: self = .enumeration
        case 0x202: self = .optional
        case 0x301: self = .tuple
        case let w where w > 0x7FF: self = .class
        default: self = .other
        }
    }
}

/// The fields the runtime reports for `type`, in declaration order (a class lists those of its superclasses first).
func forEachRuntimeField(
    of type: Any.Type,
    do body: (UnsafePointer<CChar>, Int, Any.Type) -> Void
) {
    let count = recursiveChildCount(type)
    for i in 0..<count {
        var metadata = FieldReflectionMetadata()
        let fieldType = recursiveChildMetadata(type, index: i, fieldMetadata: &metadata)
        let offset = recursiveChildOffset(type, index: i)
        if let name = metadata.name {
            body(name, offset, fieldType)
            if let free = metadata.freeName {
                free(name)
            }
        }
    }
}

private struct ValueWitnessTable {
    var p0, p1, p2, p3, p4, p5, p6, p7: UnsafeRawPointer
    var size: Int
    var stride: Int
    var flags: UInt32
    var extraInhabitantCount: UInt32
    var getEnumTag: @convention(c) (UnsafeRawPointer, UnsafeRawPointer) -> UInt32
    var destructiveProjectEnumData: @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer) -> Void
    var destructiveInjectEnumTag: @convention(c) (UnsafeMutableRawPointer, UInt32, UnsafeRawPointer) -> Void
}

/// Inspects the active case of an enum pointer, invoking `body` with its tag, payload type, and raw payload pointer.
///
/// Returns `true` if the enum currently contains a payload case, or `false` if it is an empty case.
/// Traps if `A` is not an enum type.
@discardableResult
public func withUnsafePointerToEnumCase<A>(
    of pointer: UnsafeMutablePointer<A>,
    do body: (Int, Any.Type, UnsafeRawPointer) -> Void
) -> Bool {
    let mirror = Mirror(reflecting: pointer.pointee)
    guard mirror.displayStyle == .enum else {
        preconditionFailure("not an enum type: \(A.self)")
    }
    guard let child = mirror.children.first else {
        return false
    }

    let meta = unsafeBitCast(A.self, to: UnsafePointer<UnsafePointer<ValueWitnessTable>>.self)
    let vwt = meta[-1].pointee
    let raw = UnsafeMutableRawPointer(pointer)
    let metaRaw = unsafeBitCast(A.self, to: UnsafeRawPointer.self)

    let tag = Int(vwt.getEnumTag(raw, metaRaw))
    vwt.destructiveProjectEnumData(raw, metaRaw)
    defer {
        vwt.destructiveInjectEnumTag(raw, UInt32(tag), metaRaw)
    }

    let payloadType = type(of: child.value)

    var payloadPtr: UnsafeRawPointer = UnsafeRawPointer(raw)
    let rawMeta = unsafeBitCast(A.self, to: UnsafeRawPointer.self)
    let descPtr = rawMeta.advanced(by: 8).assumingMemoryBound(to: UnsafeRawPointer.self).pointee
    let fieldsOffset = descPtr.advanced(by: 16).assumingMemoryBound(to: Int32.self).pointee
    let fieldsPtr = descPtr.advanced(by: 16 + Int(fieldsOffset))
    let recordPtr = fieldsPtr.advanced(by: 16 + tag * 12)
    let flags = recordPtr.assumingMemoryBound(to: UInt32.self).pointee
    let isIndirectCase = (flags & 1) != 0

    if isIndirectCase {
        let boxPtr = raw.assumingMemoryBound(to: UnsafeRawPointer.self).pointee
        payloadPtr = boxPtr.advanced(by: 16)
    }

    body(tag, payloadType, payloadPtr)
    return true
}

/// Inspects and allows mutation of the active case of an enum pointer, invoking `body` with its tag, payload type, and mutable raw payload pointer.
///
/// Returns `true` if the enum currently contains a payload case, or `false` if it is an empty case.
/// Traps if `A` is not an enum type.
@discardableResult
public func withUnsafeMutablePointerToEnumCase<A>(
    of pointer: UnsafeMutablePointer<A>,
    do body: (Int, Any.Type, UnsafeMutableRawPointer) -> Void
) -> Bool {
    let mirror = Mirror(reflecting: pointer.pointee)
    guard mirror.displayStyle == .enum else {
        preconditionFailure("not an enum type: \(A.self)")
    }
    guard let child = mirror.children.first else {
        return false
    }

    let meta = unsafeBitCast(A.self, to: UnsafePointer<UnsafePointer<ValueWitnessTable>>.self)
    let vwt = meta[-1].pointee
    let raw = UnsafeMutableRawPointer(pointer)
    let metaRaw = unsafeBitCast(A.self, to: UnsafeRawPointer.self)

    let tag = Int(vwt.getEnumTag(raw, metaRaw))
    vwt.destructiveProjectEnumData(raw, metaRaw)
    defer {
        vwt.destructiveInjectEnumTag(raw, UInt32(tag), metaRaw)
    }

    let payloadType = type(of: child.value)

    var payloadPtr: UnsafeMutableRawPointer = raw
    let rawMeta = unsafeBitCast(A.self, to: UnsafeRawPointer.self)
    let descPtr = rawMeta.advanced(by: 8).assumingMemoryBound(to: UnsafeRawPointer.self).pointee
    let fieldsOffset = descPtr.advanced(by: 16).assumingMemoryBound(to: Int32.self).pointee
    let fieldsPtr = descPtr.advanced(by: 16 + Int(fieldsOffset))
    let recordPtr = fieldsPtr.advanced(by: 16 + tag * 12)
    let flags = recordPtr.assumingMemoryBound(to: UInt32.self).pointee
    let isIndirectCase = (flags & 1) != 0

    if isIndirectCase {
        let boxPtr = raw.assumingMemoryBound(to: UnsafeMutableRawPointer.self).pointee
        payloadPtr = boxPtr.advanced(by: 16)
    }

    body(tag, payloadType, payloadPtr)
    return true
}



/// Calls `body` with the name, position among the payload cases and payload type of each case of the enum `type` that carries a payload, in
/// declaration order (`AGTypeApplyEnumData`-style enumeration, `Metadata.forEachField(options: .enumerateEnumCases)`;
/// native lists `payload@0:Int` for `enum { case payload(Int); case empty }`, oracle scenario `ver11d3`). Returns `false` when
/// `body` stopped it or a payload type could not be resolved.
func forEachEnumPayloadCase(of type: Any.Type, do body: (UnsafePointer<CChar>, Int, Any.Type) -> Bool) -> Bool {
    let meta = unsafeBitCast(type, to: UnsafeRawPointer.self)
    let descriptor = meta.advanced(by: 8).assumingMemoryBound(to: UnsafeRawPointer.self).pointee
    let fieldsOffset = descriptor.advanced(by: 16).assumingMemoryBound(to: Int32.self).pointee
    let fields = descriptor.advanced(by: 16 + Int(fieldsOffset))
    let count = Int(fields.advanced(by: 12).assumingMemoryBound(to: UInt32.self).pointee)
    let genericArguments = meta.advanced(by: 16).assumingMemoryBound(to: UnsafeRawPointer?.self)
    var payloadIndex = 0               // the number native prints after `@` is the position among the payload cases (`ver12d2`)
    for index in 0..<count {
        let record = fields.advanced(by: 16 + index * 12)
        let typeField = record.advanced(by: 4)
        let typeOffset = typeField.assumingMemoryBound(to: Int32.self).pointee
        guard typeOffset != 0 else { continue }                       // a case without payload
        let nameField = record.advanced(by: 8)
        let nameOffset = nameField.assumingMemoryBound(to: Int32.self).pointee
        let namePointer = nameField.advanced(by: Int(nameOffset)).assumingMemoryBound(to: CChar.self)
        let mangled = typeField.advanced(by: Int(typeOffset)).assumingMemoryBound(to: UInt8.self)
        var length = 0
        while mangled[length] != 0 {
            let byte = mangled[length]
            length += 1
            if byte >= 0x01 && byte <= 0x17 { length += 4 } else if byte >= 0x18 && byte <= 0x1F { length += 8 }
        }
        guard let payload = _getTypeByMangledNameInContext(mangled, UInt(length), genericContext: descriptor, genericArguments: UnsafeRawPointer(genericArguments)) else { return false }
        if !body(namePointer, payloadIndex, payload) { return false }
        payloadIndex += 1
    }
    return true
}


/// The size and alignment native uses to place a body in the page of a node. A type that is not bitwise takable (one with a `weak` reference, for
/// instance) or that is larger than 128 bytes is kept apart and the node holds a pointer of 8 bytes (decompiled `Graph::add_attribute`; oracle
/// `ver25`: bodies from 136 bytes up give the capacity of a node with a pointer).
func nativeBodyLayout<T>(of type: T.Type) -> (size: Int, alignment: Int) {
    let size = MemoryLayout<T>.size
    let metadata = unsafeBitCast(type, to: UnsafePointer<UnsafePointer<ValueWitnessTableFlags>>.self)
    let nonBitwiseTakable = metadata[-1].pointee.flags & 0x100000 != 0
    if nonBitwiseTakable || size > 128 { return (8, 8) }
    return (size, MemoryLayout<T>.alignment)
}

/// The value witness table up to its flags, as `ValueWitnessTable` in `withUnsafePointerToEnumCase` lays it out.
struct ValueWitnessTableFlags {
    var p0, p1, p2, p3, p4, p5, p6, p7: UnsafeRawPointer
    var size: Int
    var stride: Int
    var flags: UInt32
}
