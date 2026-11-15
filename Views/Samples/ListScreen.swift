#if USE_SHELL
import ShellUI
#else
import SwiftUI
#endif

struct Item: Identifiable {
    let id: Int
    let name: String
}

/// Second sample: stacks, lists, buttons and `if`/`else` in a builder. It must compile against real SwiftUI and the shells.
struct ListScreen: View {
    let items = [Item(id: 1, name: "One"), Item(id: 2, name: "Two"), Item(id: 3, name: "Three")]
    let showsFooter = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            List(items) { item in
                HStack(spacing: 4) {
                    Text(item.name)
                    Spacer()
                    Button("Open") { }
                }
            }
            VStack {
                ForEach(0..<3) { index in Text("n\(index)") }
                ForEach(items) { item in Text(item.name) }
                ForEach(["a", "b"], id: \.self) { name in Text(name) }
            }
            HStack {
                Spacer(minLength: 2)
                Text("end")
            }
            Button(action: { }) { Text("Go") }
            if showsFooter {
                Text("shown")
            } else {
                Text("hidden")
            }
        }
    }
}

/// Public so the tests can build it.
public func makeListScreenBody() -> some View { ListScreen().body }
