@usableFromInline
enum ReadResult<Value> {
    case ready(Value)
    case pending
}
