/// A copy of a value, with a pointer that lives as long as the holder.
private final class OutputScratch<Value> {
    let pointer: UnsafeMutablePointer<Value>
    init(_ value: Value) {
        pointer = .allocate(capacity: 1)
        pointer.initialize(to: value)
    }
    deinit {
        pointer.deinitialize(count: 1)
        pointer.deallocate()
    }
}

extension Graph {
    /// The graph and the node of the attribute that is evaluating on this thread, or the program stops (native: `no attribute
    /// updating`; outside an update it crashes with no message on macOS 15.8.3).
    private static func evaluatingAttribute() -> (Graph, UInt32) {
        guard let graph = ThreadLocalGraph.current(), graph.evaluatingNode != Graph.noNode else {
            preconditionFailure("no attribute updating")
        }
        return (graph, graph.evaluatingNode)
    }

    /// A pointer to the current value of the attribute that is evaluating, or `nil` if it has none yet
    /// (`Graph.outputValue()` in native AttributeGraph; oracle scenarios `o1`, `o2`, `o9`).
    ///
    /// It is `nil` in the first run, holds what ``setOutputValue(_:)`` wrote, and in a later run starts as the value the previous
    /// run left. Inside a rule read by another it refers to the rule that is running. The pointer is valid until the outermost
    /// update ends.
    public static func outputValue<Value>() -> UnsafePointer<Value>? {
        let (graph, node) = evaluatingAttribute()
        guard let box = graph.table.box(at: node) as? TypedNode<Value> else {
            preconditionFailure("invalid value type for attribute: \(node) (saw \(graph.table.box(at: node).valueType), expected \(Value.self))")
        }
        guard let value = box.value else { return nil }
        let scratch = OutputScratch(value)
        graph.outputScratch.append(scratch)
        return UnsafePointer(scratch.pointer)
    }

    /// Writes the value of the attribute that is evaluating (`Graph.setOutputValue(_:)` in native AttributeGraph; oracle scenarios
    /// `o1` to `o11`).
    ///
    /// The value goes through the attribute's comparison: an equal one changes nothing, and so does not run what reads the
    /// attribute; a different one counts as a change once, however many writes the body makes, and the last write wins. What a
    /// rule returns after writing replaces the written value. A value of another type than the attribute's stops the program
    /// (`invalid value type for attribute`).
    public static func setOutputValue<Value>(_ value: UnsafePointer<Value>) {
        let (graph, node) = evaluatingAttribute()
        guard let box = graph.table.box(at: node) as? TypedNode<Value> else {
            preconditionFailure("invalid value type for attribute: \(node) (saw \(graph.table.box(at: node).valueType), expected \(Value.self))")
        }
        if box.store(value.pointee) { graph.outputWrites.insert(node) }
    }
}
