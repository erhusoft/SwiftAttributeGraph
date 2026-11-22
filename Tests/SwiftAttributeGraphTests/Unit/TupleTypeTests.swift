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

import Testing
@testable import SwiftAttributeGraph

@Suite("TupleTypeTests")
struct TupleTypeTests {
    @Test
    func tupleTypeSingleElement() {
        let t = AGTupleType(Int.self)
        #expect(t.count == 1)
        #expect(t.type == Int.self)
        #expect(t.type(at: 0) == Int.self)
        #expect(t.offset(at: 0, as: Int.self) == 0)
        #expect(!t.isEmpty)
        #expect(t.indices == 0..<1)
    }

    @Test
    func tupleTypeMultipleElements() {
        let t = AGTupleType([Int.self, Double.self])
        #expect(t.count == 2)
        #expect(t.type(at: 0) == Int.self)
        #expect(t.type(at: 1) == Double.self)
        #expect(t.offset(at: 0, as: Int.self) == 0)
        #expect(t.offset(at: 1, as: Double.self) == MemoryLayout<Int>.size)
        #expect(!t.isEmpty)
        #expect(t.indices == 0..<2)
    }

    @Test
    func tupleTypeEmpty() {
        let t = AGTupleType([])
        #expect(t.count == 0)
        #expect(t.isEmpty)
        #expect(t.indices == 0..<0)
    }

    @Test
    func withUnsafeTupleBuffer() {
        let t = AGTupleType([Int.self, Double.self])
        withUnsafeTuple(of: t, count: 3) { tuple in
            #expect(tuple.count == 2)
            #expect(!tuple.isEmpty)
            #expect(tuple.indices == 0..<2)

            tuple.initialize(at: 0, to: 42)
            tuple.initialize(at: 1, to: 3.14)

            let intVal: Int = tuple[0]
            let dblVal: Double = tuple[1]
            #expect(intVal == 42)
            #expect(dblVal == 3.14)

            tuple[0] = 100
            #expect(tuple[0] == 100)

            let ptrInt = tuple.address(of: 0, as: Int.self)
            #expect(ptrInt.pointee == 100)

            let ptrDbl = tuple.address(of: 1, as: Double.self)
            #expect(ptrDbl.pointee == 3.14)

            tuple.deinitialize(at: 0)
            tuple.deinitialize(at: 1)
        }
    }

    @Test
    func unsafeTupleReadAccess() {
        let t = AGTupleType([String.self])
        withUnsafeTuple(of: t, count: 1) { mutableTuple in
            mutableTuple.initialize(at: 0, to: "hello")
            let immutable = AGUnsafeTuple(mutableTuple)
            #expect(immutable.count == 1)
            #expect(!immutable.isEmpty)
            #expect(immutable.indices == 0..<1)
            let s: String = immutable[0]
            #expect(s == "hello")
            let sSingle: String = immutable[]
            #expect(sSingle == "hello")
            mutableTuple.deinitialize()
        }
    }
}
