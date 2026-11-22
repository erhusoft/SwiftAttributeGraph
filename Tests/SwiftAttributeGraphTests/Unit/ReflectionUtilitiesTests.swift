import Testing
@testable import SwiftAttributeGraph

@Suite("ReflectionUtilitiesTests")
struct ReflectionUtilitiesTests {
    struct Person {
        var name: String
        var age: Int
        var isMember: Bool
    }

    enum SimpleEnum {
        case empty
        case single(Int)
    }

    enum MultiPayloadEnum {
        case text(String)
        case count(Int)
        case flag(Bool)
    }

    indirect enum Tree {
        case leaf
        case branch(Int, Tree, Tree)
    }

    @Test
    func testForEachFieldOnStruct() {
        var fields: [(name: String, offset: Int, type: Any.Type)] = []
        forEachField(of: Person.self) { cName, offset, fieldType in
            fields.append((String(cString: cName), offset, fieldType))
        }

        #expect(fields.count == 3)
        #expect(fields[0].name == "name")
        #expect(fields[0].offset == 0)
        #expect(Bool(fields[0].type == String.self))

        #expect(fields[1].name == "age")
        #expect(fields[1].offset == MemoryLayout<String>.stride)
        #expect(Bool(fields[1].type == Int.self))

        #expect(fields[2].name == "isMember")
        #expect(Bool(fields[2].type == Bool.self))
    }

    @Test
    func testForEachFieldOnEnum() {
        var count = 0
        forEachField(of: SimpleEnum.self) { _, _, _ in
            count += 1
        }
        #expect(count == 0)
    }

    @Test
    func testWithUnsafePointerToEnumCase() {
        var eEmpty = SimpleEnum.empty
        var executedEmpty = false
        let rEmpty = withUnsafeMutablePointer(to: &eEmpty) { ptr in
            withUnsafePointerToEnumCase(of: ptr) { _, _, _ in
                executedEmpty = true
            }
        }
        #expect(rEmpty == false)
        #expect(executedEmpty == false)

        var eSingle = SimpleEnum.single(42)
        var capturedTag: Int?
        var capturedType: Any.Type?
        var capturedValue: Int?
        let rSingle = withUnsafeMutablePointer(to: &eSingle) { ptr in
            withUnsafePointerToEnumCase(of: ptr) { tag, type, payload in
                capturedTag = tag
                capturedType = type
                capturedValue = payload.assumingMemoryBound(to: Int.self).pointee
            }
        }
        #expect(rSingle == true)
        #expect(capturedTag == 0)
        #expect(capturedType != nil && Bool(capturedType! == Int.self))
        #expect(capturedValue == 42)
    }

    @Test
    func testWithUnsafeMutablePointerToEnumCaseMutation() {
        var m = MultiPayloadEnum.count(100)
        let r = withUnsafeMutablePointer(to: &m) { ptr in
            withUnsafeMutablePointerToEnumCase(of: ptr) { tag, type, payload in
                #expect(tag == 1)
                #expect(Bool(type == Int.self))
                payload.assumingMemoryBound(to: Int.self).pointee = 200
            }
        }
        #expect(r == true)
        if case .count(let val) = m {
            #expect(val == 200)
        } else {
            Issue.record("Expected .count(200)")
        }
    }

    @Test
    func testIndirectEnumCaseInspectionAndMutation() {
        var tree = Tree.branch(10, .leaf, .leaf)
        let r = withUnsafeMutablePointer(to: &tree) { ptr in
            withUnsafeMutablePointerToEnumCase(of: ptr) { tag, type, payload in
                #expect(tag == 0)
                #expect(Bool(type == (Int, Tree, Tree).self))
                let tuplePtr = payload.assumingMemoryBound(to: (Int, Tree, Tree).self)
                tuplePtr.pointee.0 = 999
            }
        }
        #expect(r == true)
        if case let .branch(val, _, _) = tree {
            #expect(val == 999)
        } else {
            Issue.record("Expected .branch(999, ...)")
        }
    }
}
