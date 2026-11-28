/// The names native AttributeGraph gives the tuple types in Swift (`AGTupleType.Swift` renames them `TupleType`, `UnsafeTuple` and `UnsafeMutableTuple`).
public typealias TupleType = AGTupleType
public typealias UnsafeTuple = AGUnsafeTuple
public typealias UnsafeMutableTuple = AGUnsafeMutableTuple

extension AGTupleType {
    /// The options of copying an element (`TupleType.CopyOptions`).
    public typealias CopyOptions = AGTupleCopyOptions
}
