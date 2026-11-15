#if USE_SHELL
import ShellUI
#else
import SwiftUI
#endif

/// Source compatibility sample; graph installation remains explicit in the semantic probe.
struct StateScreen: View {
    @State private var count = 0
    @State private var alternate = false
    var body: some View {
        VStack {
            StateLabel(value: $count)
            if alternate { Text("alternate") } else { Text("initial") }
            Button("Increment") { count += 1 }
            Button("Switch") { alternate.toggle() }
        }
    }
}

struct StateLabel: View {
    @Binding var value: Int
    var body: some View { Text("\(value)") }
}
