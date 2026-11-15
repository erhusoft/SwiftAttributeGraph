import Testing
@testable import ShellUI
@testable import Samples

@Suite(.serialized) struct SliceTests {
    @Test func theSampleScreenBuildsAndRecordsWhatItUsed() {
        ShellCoverage.reset()
        _ = makeColumnScreenBody()
        let used = ShellCoverage.counts
        #expect(used["Text"] == 4)
        #expect(used["VStack"] == 2)
        #expect(used["ScrollView"] == 2)
        #expect(used["padding"] == 2)
    }

    @Test func aShellThatIsNotImplementedReportsItself() {
        ShellCoverage.reset()
        _ = Text("x")
        #expect(ShellCoverage.report().contains("Text: 1"))
    }

    @Test func strictModeStopsTheProgramWithTheNameOfTheShell() async {
        await #expect(processExitsWith: .failure) {
            ShellCoverage.strict = true
            _ = ScrollView { Text("x") }
        }
    }

    @Test func axisSetsAndAlignmentsMatchTheNames() {
        let both: Axis.Set = [.horizontal, .vertical]
        #expect(both.contains(.horizontal) && both.contains(.vertical))
        #expect(HorizontalAlignment.leading != HorizontalAlignment.trailing)
        #expect(Edge.Set.all.contains(.top))
    }
}
