

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WinSDK)
import WinSDK
#endif

/// A typed byte offset representation between a base type `A` and a member type `B`.
///
/// Direct parity with native Apple `AttributeGraph.PointerOffset<A, B>`.
@frozen
public struct PointerOffset<A, B>: Equatable, Hashable, Sendable {
    /// The byte offset from base `A` to member `B`.
    public var byteOffset: Int

    /// Creates a pointer offset with an explicit byte offset.
    @inlinable
    public init(byteOffset: Int) {
        self.byteOffset = byteOffset
    }

    /// Combines two offsets transitively (`A -> B` and `B -> C` into `A -> C`).
    @inlinable
    public static func + <C>(lhs: PointerOffset<A, B>, rhs: PointerOffset<B, C>) -> PointerOffset<A, C> {
        PointerOffset<A, C>(byteOffset: lhs.byteOffset + rhs.byteOffset)
    }

    /// Native sentinel pointer used to measure struct member offsets.
    /// In native AttributeGraph on 64-bit platforms, this returns pointer value 1.
    @inlinable
    public static func invalidScenePointer() -> UnsafeMutablePointer<A> {
        UnsafeMutableRawPointer(bitPattern: 1)!.assumingMemoryBound(to: A.self)
    }

    /// Determines the offset of member `B` within base `A` by inspecting the address of `member`
    /// relative to the base pointer provided in `invalidScenePointer()` or `offset(_:)`.
    @inlinable
    public static func of(_ member: inout B) -> PointerOffset<A, B> {
        let memberAddr = withUnsafePointer(to: &member) { Int(bitPattern: $0) }
        let baseAddr = Int(bitPattern: invalidScenePointer())
        return PointerOffset<A, B>(byteOffset: memberAddr - baseAddr)
    }

    /// Measures the pointer offset to a member by evaluating a closure on an invalid/sentinel pointer base.
    @inlinable
    public static func offset(_ body: (inout A) -> PointerOffset<A, B>) -> PointerOffset<A, B> {
        body(&invalidScenePointer().pointee)
    }
}

extension PointerOffset where A == B {
    /// Creates an identity offset of 0 bytes between identical types.
    @inlinable
    public init() {
        self.init(byteOffset: 0)
    }
}

extension PointerOffset: CustomStringConvertible {
    /// A description with both types and the byte offset, such as `PointerOffset<Pair, Int>(8)`.
    public var description: String {
        "PointerOffset<\(A.self), \(B.self)>(\(byteOffset))"
    }
}

// MARK: - Pointer Arithmetic Extensions

extension UnsafePointer {
    /// Advances this pointer by the typed offset.
    @inlinable
    public static func + <Member>(lhs: UnsafePointer<Pointee>, rhs: PointerOffset<Pointee, Member>) -> UnsafePointer<Member> {
        let raw = UnsafeRawPointer(lhs).advanced(by: rhs.byteOffset)
        return raw.assumingMemoryBound(to: Member.self)
    }

    /// Accesses the member at the specified pointer offset.
    @inlinable
    public subscript<Member>(offset offset: PointerOffset<Pointee, Member>) -> Member {
        unsafeAddress {
            UnsafePointer<Member>(self + offset)
        }
    }
}

extension UnsafeMutablePointer {
    /// Advances this mutable pointer by the typed offset.
    @inlinable
    public static func + <Member>(lhs: UnsafeMutablePointer<Pointee>, rhs: PointerOffset<Pointee, Member>) -> UnsafeMutablePointer<Member> {
        let raw = UnsafeMutableRawPointer(lhs).advanced(by: rhs.byteOffset)
        return raw.assumingMemoryBound(to: Member.self)
    }

    /// Accesses or modifies the member at the specified pointer offset.
    @inlinable
    public subscript<Member>(offset offset: PointerOffset<Pointee, Member>) -> Member {
        unsafeAddress {
            UnsafePointer<Member>(self + offset)
        }
        nonmutating unsafeMutableAddress {
            UnsafeMutablePointer<Member>(self + offset)
        }
    }
}

// MARK: - Attribute Extensions

extension Attribute {
    /// Subscript to project a member attribute via a pointer offset closure.
    @inlinable
    public subscript<Member>(offset offset: (inout Value) -> PointerOffset<Value, Member>) -> Attribute<Member> {
        let pOffset = PointerOffset<Value, Member>.offset(offset)
        return applying(offset: pOffset)
    }

    /// Projects a member attribute given a concrete `PointerOffset`.
    public func applying<Member>(offset: PointerOffset<Value, Member>) -> Attribute<Member> {
        guard let graph = GraphRegistry.graph(forTag: id.graphTag) else {
            preconditionFailure("applying(offset:) called after graph was deallocated")
        }
        return graph.makeProjectedAttribute(of: self, project: { source in
            withUnsafePointer(to: source) { ptr in
                (ptr + offset).pointee
            }
        }, isEqual: { _, _ in false })
    }
}
