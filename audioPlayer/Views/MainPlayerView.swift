import SwiftUI

/// Main player area, arranged vertically as a compact recorder-style layout:
/// file name + big time → waveform → short progress + time ruler → controls.
struct MainPlayerView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            // 1 — Top bar: file name + big current time
            topInfoBar
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)

            Divider()

            // 2 — Waveform (main area)
            WaveformView()
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

            Divider()

            // 3 — Short progress slider + 10s time ruler
            progressAndRuler
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)

            // 4 — Playback controls
            PlaybackBar()
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        }
        .overlay {
            if viewModel.isLoadingWaveform {
                ProgressView("分析中...")
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Top info bar

    private var topInfoBar: some View {
        HStack {
            Text(viewModel.selectedFile?.name ?? "未选择文件")
                .font(.body)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text(viewModel.isDraggingPlayhead
                ? viewModel.dragTimeDisplay
                : viewModel.currentTimeDisplay
            )
            .font(.system(size: 60, weight: .thin, design: .monospaced))
            .foregroundColor(.primary)
            .fixedSize()

            Spacer()
            Spacer().frame(width: 40) // balance the file name on the left
        }
    }

    // MARK: - Progress + ruler

    private var progressAndRuler: some View {
        VStack(spacing: 0) {
            // Short progress bar
            Slider(
                value: Binding(
                    get: { viewModel.progress },
                    set: { viewModel.seek(to: $0) }
                ),
                in: 0...1
            )
            .disabled(viewModel.duration == 0)
            .frame(maxWidth: 280)

            // 10s time ruler
            TimeRulerView(duration: viewModel.duration)
                .frame(height: 20)
                .padding(.top, 2)
        }
    }
}

// MARK: - Time ruler (10s labels)

private struct TimeRulerView: View {
    let duration: TimeInterval

    var body: some View {
        Canvas { context, size in
            guard duration > 0 else { return }
            let interval: TimeInterval = 10
            var t: TimeInterval = 0
            while t <= duration {
                let ratio = t / duration
                let x = CGFloat(ratio) * size.width
                let tickPath = Path(CGRect(x: x - 0.5, y: 0, width: 1, height: 6))
                context.fill(tickPath, with: .color(.secondary.opacity(0.5)))

                let label = formatSeconds(t)
                let text = Text(label)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                let resolved = context.resolve(text)
                let textW = resolved.measure(in: CGSize(width: 60, height: 12)).width
                let textX = min(x - textW / 2, size.width - textW)
                context.draw(resolved, at: CGPoint(x: max(0, textX), y: 8), anchor: .topLeading)

                t += interval
            }
        }
    }

    private func formatSeconds(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

#Preview {
    MainPlayerView()
        .environment(AppViewModel())
}
