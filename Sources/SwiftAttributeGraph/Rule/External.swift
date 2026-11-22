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

/// An attribute body representing an externally provided value
/// (`AttributeGraph.External`).
public struct External<Value>: _AttributeBody, CustomStringConvertible {
    public init() {}

    public static func _update(_ pointer: UnsafeMutableRawPointer, attribute: AnyAttribute) {
        // External attributes are updated via direct mutation rather than rule execution
    }

    public var description: String {
        "External<\(Value.self)>"
    }
}

/// Type-erased representation of an external attribute body
/// (`AttributeGraph._External`).
public struct _External: _AttributeBody, CustomStringConvertible {
    public init() {}

    public var description: String {
        "_External"
    }
}
