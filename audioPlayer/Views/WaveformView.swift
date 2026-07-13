import SwiftUI

struct WaveformView: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var dragMode: DragMode = .none
    @State private var dragStartX: CGFloat = 0

    private enum DragMode {
        case none
        case playhead
        case seeking
    }

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
                        drawSegments(context: &context, width: width, height: height)
                        drawWaveform(context: &context, width: width, midY: midY, ampScale: amplitudeScale)
                        drawPlayhead(context: &context, width: width, height: height)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                handleDragChange(value: value, width: width, height: height)
                            }
                            .onEnded { _ in
                                handleDragEnd(width: width)
                            }
                    )
                    .contextMenu { segmentContextMenu(width: width) }
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

    // MARK: - Drawing (unchanged)

    private func drawWaveform(context: inout GraphicsContext, width: CGFloat, midY: CGFloat, ampScale: CGFloat) {
        let samples = viewModel.waveformSamples
        guard samples.count > 1 else { return }

        let xStep = width / CGFloat(samples.count - 1)

        var topPath = Path()
        topPath.move(to: CGPoint(x: 0, y: midY))
        for (i, sample) in samples.enumerated() {
            let x = CGFloat(i) * xStep
            let y = midY - CGFloat(sample) * ampScale
            topPath.addLine(to: CGPoint(x: x, y: y))
        }

        var bottomPath = Path()
        for (i, sample) in samples.enumerated().reversed() {
            let x = CGFloat(i) * xStep
            let y = midY + CGFloat(sample) * ampScale
            bottomPath.addLine(to: CGPoint(x: x, y: y))
        }
        bottomPath.addLine(to: CGPoint(x: width, y: midY))

        var fillPath = topPath
        fillPath.addPath(bottomPath)
        fillPath.closeSubpath()
        context.fill(fillPath, with: .color(Color.accentColor.opacity(0.35)))

        context.stroke(
            topPath,
            with: .color(.accentColor),
            style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawSegments(context: inout GraphicsContext, width: CGFloat, height: CGFloat) {
        guard !viewModel.segments.isEmpty, viewModel.duration > 0 else { return }

        for segment in viewModel.segments {
            let startRatio = segment.startTime / viewModel.duration
            let endRatio = segment.endTime / viewModel.duration
            let rect = CGRect(
                x: CGFloat(startRatio) * width,
                y: 4,
                width: max(CGFloat(endRatio - startRatio) * width, 3),
                height: height - 8
            )

            let isSelected = viewModel.selectedSegments.contains(segment.id)

            // Bold, obvious border in the brand red.
            // Selected segments shift to accent color to signal state.
            let borderColor: Color = isSelected ? .accentColor : Color(red: 1.0, green: 0.30, blue: 0.30)
            let fillColor: Color = isSelected
                ? Color.accentColor.opacity(0.18)
                : Color(red: 1.0, green: 0.30, blue: 0.30).opacity(0.10)

            let rounded = Path(roundedRect: rect, cornerRadius: 4)
            context.fill(rounded, with: .color(fillColor))
            context.stroke(
                rounded,
                with: .color(borderColor),
                style: StrokeStyle(lineWidth: isSelected ? 3.0 : 2.5, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func drawPlayhead(context: inout GraphicsContext, width: CGFloat, height: CGFloat) {
        let progress = viewModel.progress
        guard progress >= 0, progress <= 1.0 else { return }
        let x = CGFloat(progress) * width
        let rect = CGRect(x: x - 1, y: 0, width: 2, height: height)
        context.fill(Path(rect), with: .color(.red.opacity(viewModel.isDraggingPlayhead ? 1.0 : 0.85)))
    }

    // MARK: - Gesture Handling

    private func playheadX(width: CGFloat) -> CGFloat {
        CGFloat(viewModel.progress) * width
    }

    private func isNearPlayhead(x: CGFloat, width: CGFloat) -> Bool {
        abs(x - playheadX(width: width)) < 12
    }

    private func handleDragChange(value: DragGesture.Value, width: CGFloat, height: CGFloat) {
        switch dragMode {
        case .none:
            dragStartX = value.startLocation.x
            if isNearPlayhead(x: value.startLocation.x, width: width) {
                dragMode = .playhead
                viewModel.beginPlayheadDrag()
            } else {
                dragMode = .seeking
            }
            if dragMode == .playhead {
                let progress = max(0, min(1, value.location.x / width))
                viewModel.updatePlayheadDrag(to: progress)
            }

        case .playhead:
            let progress = max(0, min(1, value.location.x / width))
            viewModel.updatePlayheadDrag(to: progress)

        case .seeking:
            break
        }
    }

    private func handleDragEnd(width: CGFloat) {
        switch dragMode {
        case .playhead:
            viewModel.endPlayheadDrag()
        case .seeking:
            // Static tap (no movement) → process as click
            handleTap(at: dragStartX, width: width)
        case .none:
            break
        }
        dragMode = .none
    }

    // MARK: - Tap Handling

    private func handleTap(at x: CGFloat, width: CGFloat) {
        guard viewModel.duration > 0 else { return }
        let ratio = x / width
        let tappedTime = ratio * viewModel.duration

        for segment in viewModel.segments {
            if tappedTime >= segment.startTime && tappedTime <= segment.endTime {
                viewModel.toggleSegmentSelection(segment)
                return
            }
        }
        viewModel.seek(to: ratio)
    }

    // MARK: - Right-Click Context Menu

    @ViewBuilder
    private func segmentContextMenu(width: CGFloat) -> some View {
        if !viewModel.segments.isEmpty {
            Button("全选段落") {
                viewModel.selectAllSegments()
            }
            Button("取消选中") {
                viewModel.clearSegmentSelection()
            }
            Divider()
            if !viewModel.selectedSegments.isEmpty {
                Button("导出选中 (\(viewModel.selectedSegments.count))") {
                    viewModel.exportSelectedSegments()
                }
            }
            Button("导出全部段落 (\(viewModel.segments.count))") {
                viewModel.exportAllSegments()
            }
        }
    }
}
