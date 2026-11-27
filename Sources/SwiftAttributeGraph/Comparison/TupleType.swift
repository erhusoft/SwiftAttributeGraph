//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftAttributeGraph open source project
//
// Copyright (c) 2026 Jonathan Anderson and the SwiftAttributeGraph project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WinSDK)
import WinSDK
#endif

/// Options configuring element copy / move operations within tuple buffers.
@frozen
public struct AGTupleCopyOptions: OptionSet, Sendable {
    public let rawValue: UInt32

    @inlinable
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

/// Representation of a tuple or homogeneous type layout for element-wise reflection and buffer operations.
///
/// Direct parity with native Apple `AGTupleType`.
public struct AGTupleType: Sendable {
    @usableFromInline
    final class Storage: @unchecked Sendable {
        @usableFromInline
        let types: [Any.Type]
        @usableFromInline
        let offsets: [Int]
        @usableFromInline
        let totalSize: Int

        init(types: [Any.Type]) {
            self.types = types
            var currentOffset = 0
            var computedOffsets = [Int]()
            computedOffsets.reserveCapacity(types.count)
            for _ in types {
                let alignment = MemoryLayout<Int>.alignment
                let remainder = currentOffset % alignment
                if remainder != 0 {
                    currentOffset += (alignment - remainder)
                }
                computedOffsets.append(currentOffset)
                currentOffset += MemoryLayout<Int>.size
            }
            self.offsets = computedOffsets
            self.totalSize = currentOffset
        }
    }

    @usableFromInline
    let storage: Storage

    /// Creates a tuple type representing a single type.
    @inlinable
    public init(_ type: Any.Type) {
        self.init([type])
    }

    /// Creates a tuple type representing a sequence of types.
    public init(_ types: [Any.Type]) {
        self.storage = Storage(types: types)
    }

    /// The number of elements in the tuple type.
    @inlinable
    public var count: Int {
        storage.types.count
    }

    /// Whether the tuple type has no elements.
    @inlinable
    public var isEmpty: Bool {
        storage.types.isEmpty
    }

    /// The index range covering all elements.
    @inlinable
    public var indices: Range<Int> {
        0..<storage.types.count
    }

    /// The single underlying type if this tuple type contains exactly one type, or the synthesized tuple type.
    @inlinable
    public var type: Any.Type {
        if storage.types.count == 1 {
            return storage.types[0]
        }
        return Any.self
    }

    /// Returns the element type at the given index.
    @inlinable
    public func type(at index: Int) -> Any.Type {
        precondition(index >= 0 && index < storage.types.count, "invalid index: \(index)")
        return storage.types[index]
    }

    /// Computes the byte offset of the element at the specified index.
    @inlinable
    public func offset<T>(at index: Int, as: T.Type = T.self) -> Int {
        precondition(index >= 0 && index < storage.offsets.count, "invalid index: \(index)")
        return storage.offsets[index]
    }

    /// Copies an element from the buffer into a target pointer.
    public func getElement<T>(
        in buffer: UnsafeMutableRawPointer,
        at index: Int,
        to target: UnsafeMutablePointer<T>,
        options: AGTupleCopyOptions = []
    ) {
        precondition(index >= 0 && index < storage.types.count, "index out of range: \(index)")
        precondition(T.self == storage.types[index], "element type mismatch")
        let offset = storage.offsets[index]
        let src = buffer.advanced(by: offset).assumingMemoryBound(to: T.self)
        target.initialize(to: src.pointee)
    }

    /// Copies an element from a source pointer into the buffer.
    public func setElement<T>(
        in buffer: UnsafeMutableRawPointer,
        at index: Int,
        from source: UnsafePointer<T>,
        options: AGTupleCopyOptions = []
    ) {
        precondition(index >= 0 && index < storage.types.count, "index out of range: \(index)")
        precondition(T.self == storage.types[index], "element type mismatch")
        let offset = storage.offsets[index]
        let dest = buffer.advanced(by: offset).assumingMemoryBound(to: T.self)
        dest.pointee = source.pointee
    }
}

/// An immutable view into a tuple buffer.
///
/// Direct parity with native Apple `AGUnsafeTuple`.
public struct AGUnsafeTuple {
    @usableFromInline
    let tupleType: AGTupleType
    @usableFromInline
    let buffer: UnsafeRawPointer

    @inlinable
    public init(tupleType: AGTupleType, buffer: UnsafeRawPointer) {
        self.tupleType = tupleType
        self.buffer = buffer
    }

    @inlinable
    public init(_ mutable: AGUnsafeMutableTuple) {
        self.tupleType = mutable.tupleType
        self.buffer = UnsafeRawPointer(mutable.buffer)
    }

    @inlinable
    public var count: Int {
        tupleType.count
    }

    @inlinable
    public var isEmpty: Bool {
        tupleType.isEmpty
    }

    @inlinable
    public var indices: Range<Int> {
        tupleType.indices
    }

    @inlinable
    public func address<T>(as type: T.Type = T.self) -> UnsafePointer<T> {
        address(of: 0, as: type)
    }

    @inlinable
    public func address<T>(of index: Int, as type: T.Type = T.self) -> UnsafePointer<T> {
        let offset = tupleType.offset(at: index, as: type)
        return buffer.advanced(by: offset).assumingMemoryBound(to: type)
    }

    @inlinable
    public subscript<T>() -> T {
        self[0]
    }

    @inlinable
    public subscript<T>(index: Int) -> T {
        unsafeAddress {
            address(of: index, as: T.self)
        }
    }
}

/// A mutable view into a tuple buffer.
///
/// Direct parity with native Apple `AGUnsafeMutableTuple`.
public struct AGUnsafeMutableTuple {
    @usableFromInline
    let tupleType: AGTupleType
    @usableFromInline
    let buffer: UnsafeMutableRawPointer

    @inlinable
    public init(tupleType: AGTupleType, buffer: UnsafeMutableRawPointer) {
        self.tupleType = tupleType
        self.buffer = buffer
    }

    @inlinable
    public init(with tupleType: AGTupleType) {
        let totalSize = max(tupleType.storage.totalSize, 16)
        let raw = UnsafeMutableRawPointer.allocate(byteCount: totalSize, alignment: 16)
        self.init(tupleType: tupleType, buffer: raw)
    }

    @inlinable
    public var count: Int {
        tupleType.count
    }

    @inlinable
    public var isEmpty: Bool {
        tupleType.isEmpty
    }

    @inlinable
    public var indices: Range<Int> {
        tupleType.indices
    }

    @inlinable
    public func address<T>(as type: T.Type = T.self) -> UnsafeMutablePointer<T> {
        address(of: 0, as: type)
    }

    @inlinable
    public func address<T>(of index: Int, as type: T.Type = T.self) -> UnsafeMutablePointer<T> {
        let offset = tupleType.offset(at: index, as: type)
        return buffer.advanced(by: offset).assumingMemoryBound(to: type)
    }

    @inlinable
    public subscript<T>() -> T {
        get { self[0] }
        nonmutating set { self[0] = newValue }
    }

    @inlinable
    public subscript<T>(index: Int) -> T {
        unsafeAddress {
            UnsafePointer(address(of: index, as: T.self))
        }
        nonmutating unsafeMutableAddress {
            address(of: index, as: T.self)
        }
    }

    @inlinable
    public func initialize<T>(at index: Int, to value: T) {
        address(of: index, as: T.self).initialize(to: value)
    }

    /// Destroys the element at `index` with its own type, so a reference-counted element is released
    /// (`AGUnsafeMutableTuple.deinitialize(at:)` in native AttributeGraph).
    @inlinable
    public func deinitialize(at index: Int) {
        let type = tupleType.type(at: index)
        let address = buffer.advanced(by: tupleType.offset(at: index, as: Any.self))
        Self.destroy(type, at: address)
    }

    /// Opens the element type so the value at `address` is deinitialized as that type.
    @usableFromInline
    static func destroy<T>(_ type: T.Type, at address: UnsafeMutableRawPointer) {
        address.assumingMemoryBound(to: T.self).deinitialize(count: 1)
    }

    @inlinable
    public func deinitialize() {
        for i in indices {
            deinitialize(at: i)
        }
    }

    @inlinable
    public func deallocate(initialized: Bool = true) {
        if initialized {
            deinitialize()
        }
        buffer.deallocate()
    }
}

/// Executes a closure passing a mutable unsafe tuple buffer.
///
/// Direct parity with native Apple `AttributeGraph.withUnsafeTuple(of:count:_:)`.
public func withUnsafeTuple(
    of tupleType: AGTupleType,
    count: Int,
    _ body: (AGUnsafeMutableTuple) -> Void
) {
    let elementSize = max(tupleType.storage.totalSize, 16)
    let totalBytes = max(elementSize * count, 16)
    withUnsafeTemporaryAllocation(byteCount: totalBytes, alignment: 16) { buffer in
        guard let base = buffer.baseAddress else {
            preconditionFailure("memory allocation failure")
        }
        let tuple = AGUnsafeMutableTuple(tupleType: tupleType, buffer: base)
        body(tuple)
    }
}
