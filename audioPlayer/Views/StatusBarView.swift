import SwiftUI

struct StatusBarView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(viewModel.logs) { entry in
                        Text(entry.formatted)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(logColor(for: entry.level))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .id(entry.id)
                    }
                }
            }
            .frame(height: 80)
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: viewModel.logs.count) {
                if let last = viewModel.logs.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func logColor(for level: LogLevel) -> Color {
        switch level {
        case .info: return .primary
        case .warning: return .orange
        case .error: return .red
        }
    }
}
