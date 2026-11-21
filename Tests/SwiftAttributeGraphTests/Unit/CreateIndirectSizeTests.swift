import Testing
@testable import SwiftAttributeGraph

/// `AGGraphCreateIndirectAttribute2(attribute, size)` (`AGAttribute.createIndirect(self:size:)`). The declared size may
/// not exceed the source's value size: native AttributeGraph aborts with "invalid size for indirect attribute" when it
/// does (measured with the `indirect-size` probe in NativeProbe). A smaller or equal declared size reads the whole source
/// value, measured with `indirect-read`. The too-large case aborts the process, so it is covered by that probe, not here.
@Suite struct CreateIndirectSizeTests {
    private struct Block16: Equatable {
        var a: Int64
        var b: Int64
    }

    @Test func declaredSizeEqualToTheSourceSizeFollowsTheSource() {
        let graph = Graph()
        let source = graph.makeInput(Block16(a: 1, b: 2))
        let indirect = source.createIndirect(size: 16)
        #expect(graph.value(of: indirect) == Block16(a: 1, b: 2))
        graph.setValue(Block16(a: 3, b: 4), for: source)
        #expect(graph.value(of: indirect) == Block16(a: 3, b: 4))
    }

    @Test func smallerDeclaredSizeStillReadsTheWholeSourceValue() {
        let graph = Graph()
        let source = graph.makeInput(Block16(a: 0x1111, b: 0x2222))
        for size in [0, 8] {
            let indirect = source.createIndirect(size: size)
            #expect(graph.value(of: indirect) == Block16(a: 0x1111, b: 0x2222))
        }
    }

    @Test func declaredSizeOfAnIntSourceFollowsWrites() {
        let graph = Graph()
        let source = graph.makeInput(7)
        let indirect = source.createIndirect(size: 4)
        #expect(graph.value(of: indirect) == 7)
        graph.setValue(9, for: source)
        #expect(graph.value(of: indirect) == 9)
    }
}
