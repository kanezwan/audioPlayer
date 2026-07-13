import SwiftUI

struct WaveformView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let midY = height / 2
            let amplitudeScale = height * 0.42

            ZStack {
                Color(nsColor: .controlBackgroundColor)

                if viewModel.waveformSamples.isEmpty {
                    emptyState
                } else {
                    Canvas { context, size in
                        // Draw order matters: segments behind, then waveform, then playhead
                        drawSegments(context: &context, width: width, height: height)
                        drawWaveform(context: &context, width: width, midY: midY, ampScale: amplitudeScale)
                        drawPlayhead(context: &context, width: width, height: height)
                    }
                    .gesture(
                        SpatialTapGesture().onEnded { event in
                            handleTap(at: event.location, width: width)
                        }
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var emptyState: some View {
        VStack {
            Image(systemName: "waveform")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("选择音频文件以显示声纹")
                .foregroundColor(.secondary)
                .font(.caption)
        }
    }

    // MARK: - Drawing

    /// Smooth waveform path, mirrored across the center line, with rounded stroke
    /// for a polished look. Inspired by the Xiaomi recorder waveform aesthetic.
    private func drawWaveform(context: inout GraphicsContext, width: CGFloat, midY: CGFloat, ampScale: CGFloat) {
        let samples = viewModel.waveformSamples
        guard samples.count > 1 else { return }

        let xStep = width / CGFloat(samples.count - 1)

        // Build top envelope
        var topPath = Path()
        topPath.move(to: CGPoint(x: 0, y: midY))
        for (i, sample) in samples.enumerated() {
            let x = CGFloat(i) * xStep
            let y = midY - CGFloat(sample) * ampScale
            topPath.addLine(to: CGPoint(x: x, y: y))
        }

        // Build bottom envelope (mirrored, in reverse to close the shape)
        var bottomPath = Path()
        for (i, sample) in samples.enumerated().reversed() {
            let x = CGFloat(i) * xStep
            let y = midY + CGFloat(sample) * ampScale
            bottomPath.addLine(to: CGPoint(x: x, y: y))
        }
        bottomPath.addLine(to: CGPoint(x: width, y: midY))

        // Filled body with low opacity for a soft, painterly look
        var fillPath = topPath
        fillPath.addPath(bottomPath)
        fillPath.closeSubpath()
        context.fill(fillPath, with: .color(Color.accentColor.opacity(0.35)))

        // Crisp stroke for the top envelope only
        context.stroke(
            topPath,
            with: .color(.accentColor),
            style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
        )
    }

    /// Soft horizontal highlight band for each detected segment.
    /// No hard border — just a gentle color wash to indicate "audio activity here".
    private func drawSegments(context: inout GraphicsContext, width: CGFloat, height: CGFloat) {
        guard !viewModel.segments.isEmpty, viewModel.duration > 0 else { return }

        for segment in viewModel.segments {
            let startRatio = segment.startTime / viewModel.duration
            let endRatio = segment.endTime / viewModel.duration
            let rect = CGRect(
                x: CGFloat(startRatio) * width,
                y: 0,
                width: max(CGFloat(endRatio - startRatio) * width, 3),
                height: height
            )

            let isSelected = viewModel.selectedSegments.contains(segment.id)
            // Soft background wash, stronger when selected
            let color = isSelected
                ? Color.accentColor.opacity(0.18)
                : Color.orange.opacity(0.10)
            context.fill(Path(rect), with: .color(color))

            // Thin top and bottom accent line — the ONLY stroke we add.
            // This keeps the visual clean even with 40+ segments.
            let lineY1: CGFloat = 1
            let lineY2: CGFloat = height - 1
            var topLine = Path()
            topLine.move(to: CGPoint(x: rect.minX, y: lineY1))
            topLine.addLine(to: CGPoint(x: rect.maxX, y: lineY1))
            var bottomLine = Path()
            bottomLine.move(to: CGPoint(x: rect.minX, y: lineY2))
            bottomLine.addLine(to: CGPoint(x: rect.maxX, y: lineY2))

            let lineColor = isSelected
                ? Color.accentColor.opacity(0.9)
                : Color.orange.opacity(0.55)
            context.stroke(
                topLine,
                with: .color(lineColor),
                style: StrokeStyle(lineWidth: isSelected ? 2.5 : 1.5, lineCap: .round)
            )
            context.stroke(
                bottomLine,
                with: .color(lineColor),
                style: StrokeStyle(lineWidth: isSelected ? 2.5 : 1.5, lineCap: .round)
            )
        }
    }

    private func drawPlayhead(context: inout GraphicsContext, width: CGFloat, height: CGFloat) {
        let progress = viewModel.progress
        guard progress >= 0, progress <= 1.0 else { return }
        let x = CGFloat(progress) * width
        let rect = CGRect(x: x - 1, y: 0, width: 2, height: height)
        context.fill(Path(rect), with: .color(.red.opacity(0.85)))
    }

    // MARK: - Tap Handling

    private func handleTap(at location: CGPoint, width: CGFloat) {
        let samples = viewModel.waveformSamples
        guard !samples.isEmpty, viewModel.duration > 0 else { return }

        let ratio = location.x / width
        let tappedTime = ratio * viewModel.duration

        for segment in viewModel.segments {
            if tappedTime >= segment.startTime && tappedTime <= segment.endTime {
                viewModel.toggleSegmentSelection(segment)
                return
            }
        }

        viewModel.seek(to: ratio)
    }
}
