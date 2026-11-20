/// A process-wide unique identifier, the counterpart of `AGMakeUniqueID` (`makeUniqueID()` in native AttributeGraph).
/// IDs are non-zero and consecutive, and they are the same for every graph, so an ID never repeats in the process.
/// Safe to call from any thread.
public func makeUniqueID() -> UInt {
    GraphRegistry.makeUniqueID()
}
