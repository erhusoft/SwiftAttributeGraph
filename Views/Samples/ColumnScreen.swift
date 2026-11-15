#if USE_SHELL
import ShellUI
#else
import SwiftUI
#endif

/// A sample screen written as a SwiftUI app would write it. This exact file must compile against real SwiftUI and against
/// the shells (`Scripts/check-compat.sh`). It uses only the first slice: Text, VStack, ScrollView and padding.
struct ColumnScreen: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Title")
            ScrollView {
                VStack {
                    Text("Row 1")
                    Text("Row 2")
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(verbatim: "wide")
            }
        }
        .padding()
        .padding(4)
    }
}

/// Public so the tests can build it.
public func makeColumnScreenBody() -> some View { ColumnScreen().body }
