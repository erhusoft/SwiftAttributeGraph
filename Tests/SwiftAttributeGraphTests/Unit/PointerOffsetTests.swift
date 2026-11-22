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

@Suite("PointerOffsetTests")
struct PointerOffsetTests {
    struct Sample {
        var a: Int
        var b: Double
        var c: String
    }

    @Test
    func pointerOffsetBasics() {
        let defaultOffset = PointerOffset<Sample, Sample>()
        #expect(defaultOffset.byteOffset == 0)

        var offset = PointerOffset<Sample, Double>(byteOffset: 8)
        #expect(offset.byteOffset == 8)
        offset.byteOffset = 16
        #expect(offset.byteOffset == 16)
        #expect(offset.description.contains("PointerOffset"))
    }

    @Test
    func pointerOffsetAddition() {
        struct Inner {
            var val: Int
        }
        struct Outer {
            var pad: Int
            var inner: Inner
        }

        let o1 = PointerOffset<Outer, Inner>(byteOffset: 8)
        let o2 = PointerOffset<Inner, Int>(byteOffset: 0)
        let combined = o1 + o2
        #expect(combined.byteOffset == 8)
    }

    @Test
    func invalidScenePointer() {
        let ptr = PointerOffset<Sample, Sample>.invalidScenePointer()
        #expect(Int(bitPattern: ptr) == 1)
    }

    @Test
    func pointerOffsetOfAndOffsetClosures() {
        let calculated = PointerOffset<Sample, Double>.offset { base in
            PointerOffset<Sample, Double>.of(&base.b)
        }
        let expected = MemoryLayout<Sample>.offset(of: \Sample.b)!
        #expect(calculated.byteOffset == expected)
    }

    @Test
    func unsafePointerExtensions() {
        var sample = Sample(a: 10, b: 20.5, c: "hello")
        let bOffset = PointerOffset<Sample, Double>.offset { PointerOffset<Sample, Double>.of(&$0.b) }

        withUnsafePointer(to: sample) { ptr in
            let bPtr: UnsafePointer<Double> = ptr + bOffset
            #expect(bPtr.pointee == 20.5)
            #expect(ptr[offset: bOffset] == 20.5)
        }

        withUnsafeMutablePointer(to: &sample) { ptr in
            let bPtr: UnsafeMutablePointer<Double> = ptr + bOffset
            #expect(bPtr.pointee == 20.5)
            #expect(ptr[offset: bOffset] == 20.5)
            ptr[offset: bOffset] = 99.9
        }
        #expect(sample.b == 99.9)
    }

    @Test
    func attributeApplyingOffset() {
        let graph = Graph()
        let sample = Sample(a: 42, b: 3.14, c: "test")
        let attr = graph.makeInput(sample)

        let bOffset = PointerOffset<Sample, Double>.offset { PointerOffset<Sample, Double>.of(&$0.b) }
        let bAttr = attr.applying(offset: bOffset)
        #expect(graph.value(of: bAttr) == 3.14)

        let cAttr: Attribute<String> = attr[offset: { (base: inout Sample) in PointerOffset<Sample, String>.of(&base.c) }]
        #expect(graph.value(of: cAttr) == "test")
    }
}
