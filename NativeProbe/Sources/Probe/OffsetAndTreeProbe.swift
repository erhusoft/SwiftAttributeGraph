#if NATIVE_ATTRIBUTE_GRAPH
import AttributeGraph

/// `AGGraphCreateOffsetAttribute(attribute, offset)`: the size-less offset attribute (size = bytes to the end of the value).
@_silgen_name("AGGraphCreateOffsetAttribute")
private func c_AGGraphCreateOffsetAttribute(_ attribute: AnyAttribute, _ offset: Int) -> AnyAttribute
@_silgen_name("AGSubgraphShouldRecordTree")
private func c_AGSubgraphShouldRecordTree() -> Bool
@_silgen_name("AGSubgraphSetShouldRecordTree")
private func c_AGSubgraphSetShouldRecordTree()

@_silgen_name("AGGraphCreateOffsetAttribute2")
private func c_AGGraphCreateOffsetAttribute2(_ attribute: AnyAttribute, _ offset: Int, _ size: UInt64) -> AnyAttribute

private struct OffsetProbeBlock: BitwiseCopyable { var a: Int64; var b: Int64 }
private struct OffsetProbeBlock3: BitwiseCopyable { var a: Int64; var b: Int64; var c: Int64 }

/// Same as `offsetReaderRerunsAfterWrite`, over a 24-byte value {a, b, c}: the field reader reads Int64 at `offset`.
private func offsetReaderRerunsAfterWrite3(offset: Int, write: OffsetProbeBlock3) -> Int {
    let d = Driver()
    let source: Handle<OffsetProbeBlock3> = d.input(OffsetProbeBlock3(a: 1, b: 2, c: 3))
    let field = d.currentSubgraph.apply { c_AGGraphCreateOffsetAttribute(source.identifier, offset) }
    let counter = RunCounter()
    let reader: Handle<Int64> = d.rule {
        counter.n += 1
        return d.read(Handle<Int64>(identifier: field))
    }
    _ = d.read(reader)
    let before = counter.n
    d.write(write, to: source)
    _ = d.read(reader)
    return counter.n - before
}

private final class RunCounter { var n = 0 }

/// Runs the reader of a size-less offset attribute, then writes a new source value and reads again. Returns how many
/// times the reader ran after the write (0 means the write did not reach the reader).
private func offsetReaderRerunsAfterWrite(offset: Int, size: UInt64? = nil, write: OffsetProbeBlock) -> Int {
    let d = Driver()
    let source: Handle<OffsetProbeBlock> = d.input(OffsetProbeBlock(a: 1, b: 2))
    let field = d.currentSubgraph.apply {
        size.map { c_AGGraphCreateOffsetAttribute2(source.identifier, offset, $0) } ?? c_AGGraphCreateOffsetAttribute(source.identifier, offset)
    }
    let counter = RunCounter()
    let reader: Handle<Int64> = d.rule {
        counter.n += 1
        return d.read(Handle<Int64>(identifier: field))
    }
    _ = d.read(reader)
    let before = counter.n
    d.write(write, to: source)
    _ = d.read(reader)
    return counter.n - before
}
#endif

/// When launched as `Probe offset-tree`, prints the measurements for the size-less offset default and for the subgraph
/// tree-recording flag, then exits.
func runOffsetAndTreeProbeIfRequested() {
    guard CommandLine.arguments.count > 1, CommandLine.arguments[1] == "offset-tree" else { return }
    #if NATIVE_ATTRIBUTE_GRAPH
    // Source is {a, b}. Changing only `a` (bytes 0..<8) should not reach a field at offset 8 with 8 bytes (bytes 8..<16).
    let a0 = offsetReaderRerunsAfterWrite(offset: 0, write: OffsetProbeBlock(a: 5, b: 2))
    let a8 = offsetReaderRerunsAfterWrite(offset: 8, write: OffsetProbeBlock(a: 5, b: 2))
    let b8 = offsetReaderRerunsAfterWrite(offset: 8, write: OffsetProbeBlock(a: 1, b: 9))
    let explicit8 = offsetReaderRerunsAfterWrite(offset: 8, size: 8, write: OffsetProbeBlock(a: 5, b: 2))
    print("offset-explicit8of8|changeA=\(explicit8)")
    // 24-byte value {a, b, c}, change only `a`. Remaining-bytes default at offset 8 would be bytes 8..<24 (no rerun);
    // full-value default would rerun. At offset 16 the remaining-bytes default is bytes 16..<24 (no rerun).
    let v24off8 = offsetReaderRerunsAfterWrite3(offset: 8, write: OffsetProbeBlock3(a: 5, b: 2, c: 3))
    let v24off16 = offsetReaderRerunsAfterWrite3(offset: 16, write: OffsetProbeBlock3(a: 5, b: 2, c: 3))
    print("offset-default-24|offset8ChangeA=\(v24off8)|offset16ChangeA=\(v24off16)")
    let explicit0of16 = offsetReaderRerunsAfterWrite(offset: 0, size: 16, write: OffsetProbeBlock(a: 5, b: 2))
    print("offset-explicit0of16|changeA=\(explicit0of16)")
    print("offset-default|offset0ChangeA=\(a0)|offset8ChangeA=\(a8)|offset8ChangeB=\(b8)")
    let d = Driver()
    let before = d.currentSubgraph.apply { c_AGSubgraphShouldRecordTree() }
    d.currentSubgraph.apply { c_AGSubgraphSetShouldRecordTree() }
    let after = d.currentSubgraph.apply { c_AGSubgraphShouldRecordTree() }
    print("tree-record|beforeSet=\(before)|afterSet=\(after)")
    d.close()
    exit(0)
    #else
    exit(0)
    #endif
}
