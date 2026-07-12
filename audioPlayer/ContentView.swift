import SwiftUI

struct ContentView: View {
    @State private var viewModel = AppViewModel()

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView()

            Divider()

            HSplitView {
                SidebarView()
                    .frame(minWidth: 200, idealWidth: 250)

                MainPlayerView()
                    .frame(minWidth: 400)
            }

            Divider()

            StatusBarView()
        }
        .environment(viewModel)
        .frame(minWidth: 800, minHeight: 500)
    }
}

#Preview {
    ContentView()
}
