//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftAttributeGraph open source project
//
// Copyright (c) 2024 Apple Inc. and the SwiftAttributeGraph project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

/// A type-erased optional attribute reference (`AttributeGraph.AnyOptionalAttribute`).
///
/// Unlike ``AnyWeakAttribute``, an `AnyOptionalAttribute` holds an attribute reference that
/// can be assigned directly or converted from a typed ``OptionalAttribute``.
public struct AnyOptionalAttribute: Hashable, CustomStringConvertible, Sendable {
    /// The underlying attribute handle, or `nil` if empty.
    public var attribute: AnyAttribute?

    /// The raw identifier representing this optional attribute (`AGAttribute`).
    /// Returns `attribute` if non-nil, or a sentinel null attribute if empty.
    public var identifier: AnyAttribute {
        get {
            attribute ?? AnyAttribute(id: AttributeID.nil)
        }
        set {
            if newValue.id == AttributeID.nil {
                attribute = nil
            } else {
                attribute = newValue
            }
        }
    }

    /// Creates an empty optional attribute.
    public init() {
        self.attribute = nil
    }

    /// Creates an optional attribute wrapping a strong `AnyAttribute`.
    public init(_ attribute: AnyAttribute) {
        self.attribute = attribute
    }

    /// Creates an optional attribute wrapping an optional `AnyAttribute?`.
    public init(_ attribute: AnyAttribute?) {
        self.attribute = attribute
    }

    /// Creates an optional attribute from an untyped weak reference.
    public init(_ weak: AnyWeakAttribute) {
        self.attribute = weak.attribute
    }

    /// Creates an optional attribute from a typed ``OptionalAttribute``.
    public init<Value>(_ optional: OptionalAttribute<Value>) {
        self.attribute = optional.attribute?.erased
    }

    /// The currently evaluating attribute wrapped as an `AnyOptionalAttribute`,
    /// or empty if no attribute is updating on this thread (`AnyOptionalAttribute.current`).
    public static var current: AnyOptionalAttribute {
        if let current = Graph.currentAttribute {
            return AnyOptionalAttribute(current)
        }
        return AnyOptionalAttribute()
    }

    /// Reinterprets the untyped reference as a typed `OptionalAttribute<Value>`.
    public func unsafeCast<Value>(to type: Value.Type = Value.self) -> OptionalAttribute<Value> {
        if let attribute {
            return OptionalAttribute<Value>(Attribute<Value>(id: attribute.id))
        }
        return OptionalAttribute<Value>()
    }

    /// Transforms the wrapped `AnyAttribute` if present, or returns `nil` if empty.
    public func map<T>(_ transform: (AnyAttribute) -> T) -> T? {
        attribute.map(transform)
    }

    /// Textual description matching Apple's formatting.
    public var description: String {
        if let attribute {
            return "AnyOptionalAttribute(\(attribute))"
        }
        return "nil"
    }
}
