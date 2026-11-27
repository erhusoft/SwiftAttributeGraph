import Testing
@testable import SwiftAttributeGraph

/// `Metadata.forEachField(options:do:)`. Oracle scenario `cov79-e-metadata-for-each-field`: for a struct with two `Int`
/// fields, native visits `left` at offset 0 and `right` at offset 8, both of type `Int`, and returns `true`.
@Suite struct MetadataTests {
    struct Pair { var left: Int; var right: Int }

    @Test func forEachFieldVisitsTheStoredFieldsOfAStruct() {
        var fields: [String] = []
        let completed = Metadata(Pair.self).forEachField(options: []) { name, offset, type in
            fields.append("\(String(cString: name)):\(offset):\(type == Int.self)")
            return true
        }

        #expect(completed)
        #expect(fields == ["left:0:true", "right:8:true"])
    }

    @Test func aMetadataIsTheTypeItWasMadeFrom() {
        #expect(ObjectIdentifier(Metadata(Int.self).type) == ObjectIdentifier(Int.self))
        #expect(Metadata(Int.self) == Metadata(Int.self))
        #expect(Metadata(Int.self) != Metadata(String.self))
        #expect(Set([Metadata(Int.self), Metadata(Int.self), Metadata(String.self)]).count == 2)
    }

    @Test func applyOptionsHaveTheNativeBits() {
        #expect(Metadata.ApplyOptions.enumerateClassFields.rawValue == 1)
        #expect(Metadata.ApplyOptions.continueAfterUnknownField.rawValue == 2)
        #expect(Metadata.ApplyOptions.enumerateEnumCases.rawValue == 4)
        #expect(Metadata.ApplyOptions.enumerateStructFields.rawValue == 0)
    }
}
