import SwiftUI

/// Recorder-style layout matching the Xiaomi voice recorder aesthetic.
///   Top bar: file name left  —  big time centered
///   Waveform  —  time ruler (mm:ss, 10s intervals)
///   Full-width progress bar  —  position / duration labels
///   Playback controls
struct MainPlayerView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            // ── Top bar ──
            topBar
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            // ── Waveform ──
            WaveformView()
                .padding(.horizontal, 12)

            // ── Time ruler ──
            timeRulerLine
                .padding(.horizontal, 16)
                .padding(.top, 6)

            // ── Progress bar ──
            progressSection
                .padding(.horizontal, 16)
                .padding(.top, 8)

            // ── Controls ──
            PlaybackBar()
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 10)
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

    // MARK: - Top bar

    private var topBar: some View {
        ZStack {
            // Left: file name
            HStack {
                Text(viewModel.selectedFile?.name ?? "未选择文件")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }

            // Center: big current time
            if viewModel.selectedFile != nil {
                Text(viewModel.isDraggingPlayhead
                    ? viewModel.dragTimeDisplay
                    : viewModel.currentTimeDisplay
                )
                .font(.system(size: 60, weight: .thin, design: .monospaced))
                .foregroundColor(.primary)
                .fixedSize()
            }
        }
    }

    // MARK: - Time ruler

    private var timeRulerLine: some View {
        TimeRuler(duration: viewModel.duration)
            .frame(height: 16)
            .opacity(viewModel.duration > 0 ? 1 : 0)
    }

    // MARK: - Progress section

    private var progressSection: some View {
        VStack(spacing: 2) {
            // Thin full-width progress slider
            ProgressSlider(value: Binding(
                get: { viewModel.progress },
                set: { viewModel.seek(to: $0) }
            ))
            .disabled(viewModel.duration == 0)

            // Position / Duration labels
            HStack {
                Text(viewModel.currentTimeFormatted)
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
                Spacer()
                Text(viewModel.durationFormatted)
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Thin progress slider

private struct ProgressSlider: View {
    @Binding var value: Double

    var body: some View {
        Slider(value: $value, in: 0...1) {
            EmptyView()
        }
        .controlSize(.mini)
    }
}

// MARK: - Time ruler (Canvas)

private struct TimeRuler: View {
    let duration: TimeInterval

    var body: some View {
        Canvas { context, size in
            guard duration > 0 else { return }
            let interval: TimeInterval = 10   // one tick every 10 s
            var t: TimeInterval = 0
            while t <= duration {
                let ratio = t / duration
                let x = CGFloat(ratio) * size.width
                let tickPath = Path(CGRect(x: x - 0.5, y: 0, width: 1, height: 5))
                context.fill(tickPath, with: .color(.secondary.opacity(0.4)))

                let label = formatTime(t)
                let text = Text(label)
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
                let resolved = context.resolve(text)
                let textW = resolved.measure(in: .init(width: 50, height: 10)).width
                let textX = min(x - textW / 2, size.width - textW)
                context.draw(resolved, at: CGPoint(x: max(0, textX), y: 6), anchor: .topLeading)
                t += interval
            }
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}
