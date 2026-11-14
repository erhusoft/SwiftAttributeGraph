import Testing
@testable import SwiftAttributeGraph

/// Random trees of subgraphs against a simple model: what is alive, and which readers are left dirty.
/// Operations: make a subgraph under a random one; make an input; make a rule that reads an earlier input and read
/// it; invalidate a random subgraph, directly or from inside a rule. After every operation the engine and the model
/// agree on the live nodes and subgraphs, on which attribute IDs resolve, and on which readers lost an input.
@Suite struct SubgraphOracleTests {
    private struct Generator {
        var state: UInt64
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 32) % UInt64(bound))
        }
    }

    private struct ModelSubgraph { var parent: Int?; var alive = true }
    private struct ModelAttribute { var owner: Int; var alive = true; var isRule = false; var source: Int? }

    @Test func randomTreesMatchTheModel() {
        for seed in 1...12 {
            var random = Generator(state: UInt64(seed) &* 7919)
            let graph = Graph()
            var subgraphs = [ModelSubgraph(parent: nil)]            // 0 is the root
            var handles: [Subgraph] = [graph.rootSubgraph]
            var attributes: [ModelAttribute] = []
            var inputs: [Attribute<Int>] = []                         // for every model attribute: an input handle or a rule handle
            var ids: [AttributeID] = []
            var rules: [Int: Attribute<Int>] = [:]

            func descendants(of root: Int) -> [Int] {
                var result = [root], i = 0
                while i < result.count {
                    for (index, s) in subgraphs.enumerated() where s.alive && s.parent == result[i] { result.append(index) }
                    i += 1
                }
                return result
            }
            func liveSubgraphs() -> [Int] { subgraphs.indices.filter { subgraphs[$0].alive } }

            func invalidateInModel(_ target: Int) -> Set<Int> {
                let doomed = Set(descendants(of: target))
                for s in doomed { subgraphs[s].alive = false }
                var lostInput: Set<Int> = []
                for index in attributes.indices where attributes[index].alive && doomed.contains(attributes[index].owner) {
                    attributes[index].alive = false
                }
                for index in attributes.indices where attributes[index].alive && attributes[index].isRule {
                    if let source = attributes[index].source, !attributes[source].alive { lostInput.insert(index) }
                }
                return lostInput
            }

            var expectedDirty: Set<Int> = []
            for step in 0..<150 {
                let live = liveSubgraphs()
                switch random.next(6) {
                case 0:                                                // a subgraph under a random live one
                    let parent = live[random.next(live.count)]
                    handles.append(graph.makeSubgraph(parent: handles[parent]))
                    subgraphs.append(ModelSubgraph(parent: parent))
                case 1, 2:                                              // an input
                    let owner = live[random.next(live.count)]
                    let value = random.next(100)
                    let input = graph.withCurrent(handles[owner]) { graph.makeInput(value) }
                    attributes.append(ModelAttribute(owner: owner))
                    inputs.append(input); ids.append(input.id)
                case 3:                                                // a rule that reads a live input, run once
                    let sources = attributes.indices.filter { attributes[$0].alive && !attributes[$0].isRule }
                    guard !sources.isEmpty else { continue }
                    let source = sources[random.next(sources.count)]
                    let owner = live[random.next(live.count)]
                    let read = inputs[source]
                    let rule = graph.withCurrent(handles[owner]) { graph.makeRule { read.value + 1 } }
                    _ = graph.value(of: rule)
                    attributes.append(ModelAttribute(owner: owner, isRule: true, source: source))
                    inputs.append(rule); ids.append(rule.id); rules[attributes.count - 1] = rule
                default:                                               // invalidate, directly or from inside a rule
                    let candidates = live.filter { $0 != 0 }
                    guard !candidates.isEmpty else { continue }
                    let target = candidates[random.next(candidates.count)]
                    let handle = handles[target]
                    if random.next(2) == 0 {
                        graph.invalidate(handle)
                    } else {
                        let trigger = graph.makeRule { () -> Int in graph.invalidate(handle); return 0 }
                        _ = graph.value(of: trigger)
                        attributes.append(ModelAttribute(owner: 0, isRule: true, source: nil))
                        inputs.append(trigger); ids.append(trigger.id)
                    }
                    expectedDirty.formUnion(invalidateInModel(target))
                }

                let liveNodes = attributes.filter(\.alive).count
                #expect(graph.nodeCount == liveNodes, "seed \(seed) step \(step): live nodes")
                #expect(graph.liveSubgraphCount == liveSubgraphs().count, "seed \(seed) step \(step): live subgraphs")
                for (index, attribute) in attributes.enumerated() {
                    #expect(graph.contains(ids[index]) == attribute.alive, "seed \(seed) step \(step): attribute \(index)")
                }
                for (index, subgraph) in subgraphs.enumerated() {
                    #expect(graph.isLive(handles[index]) == subgraph.alive, "seed \(seed) step \(step): subgraph \(index)")
                }
                for index in expectedDirty where attributes[index].alive {
                    #expect(graph.isDirty(ids[index]), "seed \(seed) step \(step): reader \(index) must be dirty")
                }
            }
            // Everything below the root goes away; nothing is left but the root.
            for s in liveSubgraphs().filter({ $0 != 0 && subgraphs[$0].parent == 0 }) { graph.invalidate(handles[s]) }
            #expect(graph.liveSubgraphCount == 1 && graph.nodeCount == attributes.indices.filter { attributes[$0].alive && attributes[$0].owner == 0 }.count)
        }
    }
}
