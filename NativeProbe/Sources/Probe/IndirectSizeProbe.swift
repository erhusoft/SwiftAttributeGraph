import Darwin
#if NATIVE_ATTRIBUTE_GRAPH
import AttributeGraph

/// `AGGraphCreateIndirectAttribute2(attribute, size)`: the indirect attribute that also states the size of the value it
/// projects. The size-less `AGGraphCreateIndirectAttribute` is the one `Driver.indirect` uses.
@_silgen_name("AGGraphCreateIndirectAttribute2")
private func c_AGGraphCreateIndirectAttribute2(_ attribute: AnyAttribute, _ size: Int) -> AnyAttribute
#endif

/// Value types whose `MemoryLayout.size` is exactly the size under test. Native AttributeGraph aborts with
/// "invalid size for indirect attribute: <size> vs <value size>" when the stated size differs from the source's size, so
/// each size needs a source of that size, not an `Int64`.
private struct SizeProbeBlock2: BitwiseCopyable { var a: Int64; var b: Int64 }
private struct SizeProbeBlock4: BitwiseCopyable { var a, b, c, d: Int64 }
private struct SizeProbeBlock5: BitwiseCopyable { var a, b, c, d, e: Int64 }
private struct SizeProbeBlock18: BitwiseCopyable { var a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17: Int64 }
/// A field of a larger value: the offset attribute projects `value`, which is `T`-sized, at offset 8.
private struct SizeProbeHolder<T: BitwiseCopyable>: BitwiseCopyable { var tag: Int64; var value: T }

#if NATIVE_ATTRIBUTE_GRAPH
/// Creates one indirect attribute of size `MemoryLayout<T>.size` over an input, a rule, or a field of type `T`.
private func probeIndirectSize<T: BitwiseCopyable>(_ type: T.Type, _ kind: String, _ d: Driver, value: T, stated: Int) -> AnyAttribute {
    let source: AnyAttribute
    switch kind {
    case "input":
        source = d.input(value).identifier
    case "rule":
        let rule: Handle<T> = d.rule { value }
        source = rule.identifier
    case "offset":
        let holder: Handle<SizeProbeHolder<T>> = d.input(SizeProbeHolder(tag: 1, value: value))
        let field: Handle<T> = d.offsetIndirect(holder, keyPath: \SizeProbeHolder<T>.value)
        source = field.identifier
    default:
        exit(2)
    }
    return d.currentSubgraph.apply { c_AGGraphCreateIndirectAttribute2(source, stated) }
}
#endif

/// When launched as `Probe indirect-size <size> <input|rule|offset>`, creates one indirect attribute of that size over
/// that kind of source, prints one line, and exits. Native AttributeGraph aborts the process for an invalid combination,
/// so each combination runs in its own process; the exit status is the result.
func runIndirectSizeProbeIfRequested() {
    let arguments = CommandLine.arguments
    guard arguments.count > 3, arguments[1] == "indirect-size" else { return }
    guard let stated = Int(arguments[2]) else { exit(2) }
    let kind = arguments[3]
    // Optional fifth argument: the size of the source value, when it differs from the stated size (mismatch probes).
    let sourceSize = arguments.count > 4 ? (Int(arguments[4]) ?? stated) : stated
    #if NATIVE_ATTRIBUTE_GRAPH
    let d = Driver()
    let created: AnyAttribute
    switch sourceSize {
    case 2: created = probeIndirectSize(Int16.self, kind, d, value: 2, stated: stated)
    case 4: created = probeIndirectSize(Int32.self, kind, d, value: 4, stated: stated)
    case 8: created = probeIndirectSize(Int64.self, kind, d, value: 8, stated: stated)
    case 16: created = probeIndirectSize(SizeProbeBlock2.self, kind, d, value: SizeProbeBlock2(a: 1, b: 2), stated: stated)
    case 32: created = probeIndirectSize(SizeProbeBlock4.self, kind, d, value: SizeProbeBlock4(a: 1, b: 2, c: 3, d: 4), stated: stated)
    case 40: created = probeIndirectSize(SizeProbeBlock5.self, kind, d, value: SizeProbeBlock5(a: 1, b: 2, c: 3, d: 4, e: 5), stated: stated)
    case 144:
        created = probeIndirectSize(SizeProbeBlock18.self, kind, d, value: SizeProbeBlock18(
            a0: 0, a1: 1, a2: 2, a3: 3, a4: 4, a5: 5, a6: 6, a7: 7, a8: 8, a9: 9, a10: 10, a11: 11,
            a12: 12, a13: 13, a14: 14, a15: 15, a16: 16, a17: 17), stated: stated)
    default: exit(2)
    }
    print("indirect-size|stated=\(stated)|sourceSize=\(sourceSize)|source=\(kind)|created=true")
    _ = created
    d.close()
    exit(0)
    #else
    print("indirect-size|stated=\(stated)|source=\(kind)|skipped=own-engine-has-no-size-variant")
    exit(0)
    #endif
}

#if NATIVE_ATTRIBUTE_GRAPH
/// Reads the indirect attribute of declared `stated` size over an input of `T` and returns the bytes it reads back.
private func readIndirectSize<T: BitwiseCopyable>(_ type: T.Type, _ d: Driver, value: T, stated: Int) -> [UInt8] {
    let input: Handle<T> = d.input(value)
    let created = d.currentSubgraph.apply { c_AGGraphCreateIndirectAttribute2(input.identifier, stated) }
    let read: T = d.read(Handle<T>(identifier: created))
    return withUnsafeBytes(of: read) { Array($0) }
}
#endif

/// When launched as `Probe indirect-read <stated> <sourceSize>`, prints the bytes read back through an indirect attribute
/// of declared size `stated` over an input of `sourceSize` bytes (16 or 32), filled with 1...N per 8-byte word.
func runIndirectReadProbeIfRequested() {
    let arguments = CommandLine.arguments
    guard arguments.count > 3, arguments[1] == "indirect-read" else { return }
    guard let stated = Int(arguments[2]), let sourceSize = Int(arguments[3]) else { exit(2) }
    #if NATIVE_ATTRIBUTE_GRAPH
    let d = Driver()
    let bytes: [UInt8]
    switch sourceSize {
    case 16: bytes = readIndirectSize(SizeProbeBlock2.self, d, value: SizeProbeBlock2(a: 0x1111, b: 0x2222), stated: stated)
    case 32: bytes = readIndirectSize(SizeProbeBlock4.self, d, value: SizeProbeBlock4(a: 0x1111, b: 0x2222, c: 0x3333, d: 0x4444), stated: stated)
    default: exit(2)
    }
    print("indirect-read|stated=\(stated)|sourceSize=\(sourceSize)|bytes=\(bytes.map { String($0, radix: 16) }.joined(separator: " "))")
    d.close()
    exit(0)
    #else
    exit(0)
    #endif
}
