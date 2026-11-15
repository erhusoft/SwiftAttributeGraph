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

    /// The row closures of `List` and `ForEach` are not called (nothing renders), so only what the screen builds directly counts.
    @Test func theSecondSampleRecordsStacksListsAndButtons() {
        ShellCoverage.reset()
        _ = makeListScreenBody()
        let used = ShellCoverage.counts
        #expect(used["ZStack"] == 1 && used["List"] == 1 && used["VStack"] == 1 && used["HStack"] == 1)
        #expect(used["ForEach"] == 4)          // three written by the screen and the one `List` builds for its rows
        #expect(used["Button"] == 1 && used["Spacer"] == 1)
        #expect(used["Text"] == 3)             // "end", "Go" and the branch of `if` that is taken
    }

    @Test func listAndForEachDoNotCallTheirRowClosuresWithoutARenderer() {
        ShellCoverage.reset()
        nonisolated(unsafe) var calls = 0
        _ = ForEach([1, 2, 3], id: \.self) { (n: Int) -> Text in calls += 1; return Text("\(n)") }
        #expect(calls == 0)
    }

    @Test func alignmentsAndTheirNamesExist() {
        #expect(VerticalAlignment.top != VerticalAlignment.bottom)
        #expect(Alignment.topLeading != Alignment.bottomTrailing)
        #expect(Alignment.center == Alignment.center)
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
