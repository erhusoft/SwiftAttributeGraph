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
