import SwiftUI

struct ToolbarView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { viewModel.openFolder() }) {
                Label("打开文件夹", systemImage: "folder.badge.plus")
            }

            Divider().frame(height: 20)

            Button(action: { viewModel.exportSelectedSegments() }) {
                Label("导出选中", systemImage: "square.and.arrow.up")
            }
            .disabled(viewModel.selectedSegments.isEmpty)
            .help("导出选中的段落")

            Button(action: { viewModel.exportAllSegments() }) {
                Label("导出全部", systemImage: "square.and.arrow.up.on.square")
            }
            .disabled(viewModel.segments.isEmpty)
            .help("导出所有段落")

            Divider().frame(height: 20)

            Label("灵敏度", systemImage: "slider.horizontal.3")
                .font(.caption)
            Slider(value: Binding(
                get: { Double(viewModel.sensitivityFactor) },
                set: { viewModel.sensitivityFactor = Float($0); viewModel.reanalyzeSegments() }
            ), in: 1...5, step: 0.5)
            .frame(width: 120)
            Text(String(format: "%.1fx", viewModel.sensitivityFactor))
                .font(.caption.monospacedDigit())
                .frame(width: 40)

            Divider().frame(height: 20)

            Button(action: {}) {
                Image(systemName: "gearshape")
            }
            .help("设置")

            Spacer()

            Text("\(viewModel.segments.count) 个段落")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
