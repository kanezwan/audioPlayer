import SwiftUI

struct WaveformView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let midY = height / 2
            let amplitudeScale = height * 0.4

            ZStack {
                Color(nsColor: .controlBackgroundColor)

                if viewModel.waveformSamples.isEmpty {
                    emptyState
                } else {
                    Canvas { context, size in
                        drawWaveform(context: &context, width: width, midY: midY, ampScale: amplitudeScale)
                        drawSegments(context: &context, width: width, height: height)
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

    private func drawWaveform(context: inout GraphicsContext, width: CGFloat, midY: CGFloat, ampScale: CGFloat) {
        let samples = viewModel.waveformSamples
        guard samples.count > 1 else { return }

        var path = Path()
        let xStep = width / CGFloat(samples.count - 1)

        path.move(to: CGPoint(x: 0, y: midY))
        for (i, sample) in samples.enumerated() {
            let x = CGFloat(i) * xStep
            let y = midY - CGFloat(sample) * ampScale
            path.addLine(to: CGPoint(x: x, y: y))
        }
        for (i, sample) in samples.enumerated().reversed() {
            let x = CGFloat(i) * xStep
            let y = midY + CGFloat(sample) * ampScale
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.closeSubpath()

        context.fill(path, with: .color(Color.accentColor.opacity(0.3)))
        context.stroke(path, with: .color(.accentColor), lineWidth: 0.5)
    }

    private func drawSegments(context: inout GraphicsContext, width: CGFloat, height: CGFloat) {
        let samples = viewModel.waveformSamples
        guard !samples.isEmpty, !viewModel.segments.isEmpty, viewModel.duration > 0 else { return }

        for segment in viewModel.segments {
            let startRatio = segment.startTime / viewModel.duration
            let endRatio = segment.endTime / viewModel.duration
            let rect = CGRect(
                x: CGFloat(startRatio) * width,
                y: 2,
                width: max(CGFloat(endRatio - startRatio) * width, 2),
                height: height - 4
            )

            let isSelected = viewModel.selectedSegments.contains(segment.id)
            context.fill(
                Path(roundedRect: rect, cornerRadius: 3),
                with: .color(isSelected ? Color.accentColor.opacity(0.35) : Color.orange.opacity(0.2))
            )
            context.stroke(
                Path(roundedRect: rect, cornerRadius: 3),
                with: .color(isSelected ? Color.accentColor : Color.orange.opacity(0.6)),
                lineWidth: isSelected ? 2 : 1
            )
        }
    }

    private func drawPlayhead(context: inout GraphicsContext, width: CGFloat, height: CGFloat) {
        let progress = viewModel.progress
        guard progress >= 0, progress <= 1.0 else { return }
        let x = CGFloat(progress) * width
        let rect = CGRect(x: x - 1, y: 0, width: 2, height: height)
        context.fill(Path(rect), with: .color(.red))
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
