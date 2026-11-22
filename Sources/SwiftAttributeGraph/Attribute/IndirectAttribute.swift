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

/// A property wrapper and container that models an indirect attribute pointing dynamically to a source attribute.
///
/// Direct parity with native Apple `AttributeGraph.IndirectAttribute<Value>`.
@propertyWrapper
@dynamicMemberLookup
@frozen
public struct IndirectAttribute<Value>: Hashable, Equatable {
    /// The indirect attribute handle that wraps the redirection.
    public let attribute: Attribute<Value>

    /// Creates an indirect attribute targeting `source`.
    public init(source: Attribute<Value>) {
        self.attribute = source.createIndirect()
    }

    /// Creates an indirect attribute from an existing indirect `Attribute<Value>`.
    public init(attribute: Attribute<Value>) {
        self.attribute = attribute
    }

    /// The underlying identifier (`AGAttribute` handle) of this indirect attribute.
    public var identifier: AnyAttribute {
        AnyAttribute(id: attribute.id)
    }

    /// The projected value for property wrapper syntax (`$foo`).
    public var projectedValue: Attribute<Value> {
        attribute
    }

    /// Accesses or mutates the source attribute targeted by this indirect attribute.
    public var source: Attribute<Value> {
        get {
            guard let graph = GraphRegistry.graph(forTag: attribute.id.graphTag) else {
                return Attribute<Value>(id: AttributeID.nil)
            }
            return Attribute<Value>(id: graph.sourceImpl(of: AnyAttribute(id: attribute.id)).id)
        }
        set {
            guard let graph = GraphRegistry.graph(forTag: attribute.id.graphTag) else {
                preconditionFailure("setting source on indirect attribute after graph was deallocated")
            }
            graph.setSource(newValue, for: attribute)
        }
    }

    /// Accesses or modifies the producer dependency of this indirect attribute.
    public var dependency: AnyAttribute? {
        get {
            guard let graph = GraphRegistry.graph(forTag: attribute.id.graphTag) else {
                return nil
            }
            return graph.dependency(of: attribute)
        }
        set {
            guard let graph = GraphRegistry.graph(forTag: attribute.id.graphTag) else {
                preconditionFailure("setting dependency on indirect attribute after graph was deallocated")
            }
            graph.setDependency(newValue, for: attribute)
        }
    }

    /// Accesses or modifies the current resolved value of this indirect attribute.
    public var value: Value {
        get {
            guard let graph = GraphRegistry.graph(forTag: attribute.id.graphTag) else {
                preconditionFailure("reading value on indirect attribute after graph was deallocated")
            }
            return graph.value(of: attribute)
        }
        set {
            guard let graph = GraphRegistry.graph(forTag: attribute.id.graphTag) else {
                preconditionFailure("setting value on indirect attribute after graph was deallocated")
            }
            graph.setValue(newValue, for: attribute)
        }
    }

    /// The wrapped value for property wrapper syntax.
    public var wrappedValue: Value {
        get {
            value
        }
        set {
            value = newValue
        }
    }

    /// Dynamic member lookup projecting keypaths into focused attributes.
    public subscript<Member>(dynamicMember keyPath: KeyPath<Value, Member>) -> Attribute<Member> {
        attribute[keyPath: keyPath]
    }

    /// Resets the source attribute to its initial source or nil.
    public func resetSource() {
        guard let graph = GraphRegistry.graph(forTag: attribute.id.graphTag) else {
            return
        }
        graph.resetSource(for: attribute)
    }

    /// Returns the resolved value and whether it has changed according to `options`.
    public func changedValue(options: AGValueOptions = []) -> (value: Value, changed: Bool) {
        attribute.changedValue(options: options)
    }

    // MARK: - Equatable & Hashable

    public static func == (lhs: IndirectAttribute<Value>, rhs: IndirectAttribute<Value>) -> Bool {
        lhs.attribute == rhs.attribute
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(attribute)
    }
}
