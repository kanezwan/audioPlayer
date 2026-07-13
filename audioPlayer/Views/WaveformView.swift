import SwiftUI

struct WaveformView: View {
    @Environment(AppViewModel.self) private var viewModel

    @State private var dragMode: DragMode = .none
    @State private var dragStartX: CGFloat = 0
    @State private var dragCurrentX: CGFloat = 0
    @State private var resizingSegmentId: UUID?
    @State private var resizingEdge: ResizeEdge = .none
    @State private var draggingSegmentId: UUID?

    private enum DragMode {
        case none
        case playhead
        case creating              // drag on empty area creates a new segment
        case movingSegment         // drag inside a segment body moves it
        case resizingLeftEdge
        case resizingRightEdge
    }

    private enum ResizeEdge {
        case none, left, right
    }

    private let edgeHitWidth: CGFloat = 10

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
                        drawCreatingPreview(context: &context, width: width, height: height)
                        drawWaveform(context: &context, width: width, midY: midY, ampScale: amplitudeScale)
                        drawPlayhead(context: &context, width: width, height: height)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        // Static click — toggle selection or seek
                        handleTap(at: location.x, width: width)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 3)
                            .onChanged { value in
                                handleDragChange(value: value, width: width)
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

    // MARK: - Drawing

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

        // Render the box as a slim horizontal band: top and bottom thin lines
        // at the peak amplitude (height × 0.42) plus a soft fill spanning the
        // full height. Height is roughly 1/4 of the canvas.
        let bandY = height * 0.5 - height * 0.10   // upper line at 40% from top
        let bandH = height * 0.20                   // band height ~ 1/4 of canvas

        for segment in viewModel.segments {
            let startX = timeToX(segment.startTime, width: width)
            let endX = timeToX(segment.endTime, width: width)
            let rect = CGRect(
                x: startX,
                y: bandY,
                width: max(endX - startX, 3),
                height: bandH
            )

            let isSelected = viewModel.selectedSegments.contains(segment.id)
            // Purple to avoid clashing with the red nav/playhead colors.
            let borderColor: Color = isSelected ? .accentColor : Color(red: 0.49, green: 0.23, blue: 0.93)
            let fillColor: Color = isSelected
                ? Color.accentColor.opacity(0.18)
                : Color(red: 0.49, green: 0.23, blue: 0.93).opacity(0.12)

            let rounded = Path(roundedRect: rect, cornerRadius: 3)
            context.fill(rounded, with: .color(fillColor))
            context.stroke(
                rounded,
                with: .color(borderColor),
                style: StrokeStyle(lineWidth: isSelected ? 2.5 : 2.0, lineCap: .round, lineJoin: .round)
            )
        }
    }

    /// Show a live preview while the user is dragging to create a new segment.
    private func drawCreatingPreview(context: inout GraphicsContext, width: CGFloat, height: CGFloat) {
        guard dragMode == .creating else { return }
        let startX = min(dragStartX, dragCurrentX)
        let endX = max(dragStartX, dragCurrentX)
        let bandY = height * 0.5 - height * 0.10
        let bandH = height * 0.20
        let rect = CGRect(x: startX, y: bandY, width: max(endX - startX, 3), height: bandH)
        let rounded = Path(roundedRect: rect, cornerRadius: 3)
        context.fill(rounded, with: .color(Color.accentColor.opacity(0.20)))
        context.stroke(
            rounded,
            with: .color(.accentColor),
            style: StrokeStyle(lineWidth: 2.0, lineCap: .round, dash: [6, 4])
        )
    }

    private func drawPlayhead(context: inout GraphicsContext, width: CGFloat, height: CGFloat) {
        let progress = viewModel.progress
        guard progress >= 0, progress <= 1.0 else { return }
        let x = CGFloat(progress) * width
        let rect = CGRect(x: x - 1, y: 0, width: 2, height: height)
        context.fill(Path(rect), with: .color(.red.opacity(viewModel.isDraggingPlayhead ? 1.0 : 0.85)))
    }

    // MARK: - Hit testing

    private func timeToX(_ time: TimeInterval, width: CGFloat) -> CGFloat {
        guard viewModel.duration > 0 else { return 0 }
        return CGFloat(time / viewModel.duration) * width
    }

    private func xToTime(_ x: CGFloat, width: CGFloat) -> TimeInterval {
        guard viewModel.duration > 0 else { return 0 }
        let ratio = max(0, min(1, x / width))
        return ratio * viewModel.duration
    }

    private func segmentHit(at x: CGFloat, width: CGFloat) -> (segment: AudioSegment, edge: ResizeEdge) {
        for segment in viewModel.segments {
            let startX = timeToX(segment.startTime, width: width)
            let endX = timeToX(segment.endTime, width: width)
            if x >= startX && x <= endX {
                let edge: ResizeEdge
                if x < startX + edgeHitWidth { edge = .left }
                else if x > endX - edgeHitWidth { edge = .right }
                else { edge = .none }
                return (segment, edge)
            }
        }
        return (AudioSegment(startTime: 0, endTime: 0), .none)
    }

    private func isNearPlayhead(x: CGFloat, width: CGFloat) -> Bool {
        abs(x - CGFloat(viewModel.progress) * width) < 12
    }

    // MARK: - Drag Handling

    private func handleDragChange(value: DragGesture.Value, width: CGFloat) {
        dragCurrentX = value.location.x

        switch dragMode {
        case .none:
            dragStartX = value.startLocation.x
            if isNearPlayhead(x: value.startLocation.x, width: width) {
                dragMode = .playhead
                viewModel.beginPlayheadDrag()
                let progress = max(0, min(1, value.location.x / width))
                viewModel.updatePlayheadDrag(to: progress)
            } else {
                let hit = segmentHit(at: value.startLocation.x, width: width)
                if hit.segment.endTime > 0 {
                    draggingSegmentId = hit.segment.id
                    switch hit.edge {
                    case .left:
                        dragMode = .resizingLeftEdge
                        resizingSegmentId = hit.segment.id
                        resizingEdge = .left
                    case .right:
                        dragMode = .resizingRightEdge
                        resizingSegmentId = hit.segment.id
                        resizingEdge = .right
                    case .none:
                        dragMode = .movingSegment
                    }
                } else {
                    dragMode = .creating
                }
            }

        case .playhead:
            let progress = max(0, min(1, value.location.x / width))
            viewModel.updatePlayheadDrag(to: progress)

        case .creating:
            // Live preview is drawn in drawCreatingPreview
            break

        case .movingSegment:
            guard let segId = draggingSegmentId,
                  let seg = viewModel.segments.first(where: { $0.id == segId }) else { return }
            let dx = value.location.x - value.startLocation.x
            let dt = xToTime(dx, width: width)
            let dur = viewModel.duration
            let newStart = max(0, min(dur - (seg.endTime - seg.startTime), seg.startTime + dt))
            let newEnd = newStart + (seg.endTime - seg.startTime)
            viewModel.moveSegment(segId, to: AudioSegment(startTime: newStart, endTime: newEnd))

        case .resizingLeftEdge:
            guard let segId = resizingSegmentId,
                  let seg = viewModel.segments.first(where: { $0.id == segId }) else { return }
            let newStart = xToTime(value.location.x, width: width)
            let clamped = min(newStart, seg.endTime - 0.2)
            viewModel.moveSegment(segId, to: AudioSegment(startTime: max(0, clamped), endTime: seg.endTime))

        case .resizingRightEdge:
            guard let segId = resizingSegmentId,
                  let seg = viewModel.segments.first(where: { $0.id == segId }) else { return }
            let newEnd = xToTime(value.location.x, width: width)
            let clamped = max(newEnd, seg.startTime + 0.2)
            viewModel.moveSegment(segId, to: AudioSegment(startTime: seg.startTime, endTime: min(viewModel.duration, clamped)))
        }
    }

    private func handleDragEnd(width: CGFloat) {
        switch dragMode {
        case .playhead:
            viewModel.endPlayheadDrag()
        case .creating:
            // Create segment if drag was at least 8pt wide
            let startX = min(dragStartX, dragCurrentX)
            let endX = max(dragStartX, dragCurrentX)
            if endX - startX >= 8 {
                let startTime = xToTime(startX, width: width)
                let endTime = xToTime(endX, width: width)
                viewModel.createSegment(start: startTime, end: endTime)
            }
        case .movingSegment, .resizingLeftEdge, .resizingRightEdge:
            break
        case .none:
            break
        }
        dragMode = .none
        draggingSegmentId = nil
        resizingSegmentId = nil
        resizingEdge = .none
    }

    // MARK: - Tap-only fallback (called when click is inside an existing segment)

    private func handleTap(at x: CGFloat, width: CGFloat) {
        guard viewModel.duration > 0 else { return }
        // Playhead region: drag, not click
        if isNearPlayhead(x: x, width: width) { return }
        let hit = segmentHit(at: x, width: width)
        if hit.segment.endTime > 0 && hit.edge == .none {
            // Click inside a segment body — toggle selection
            viewModel.toggleSegmentSelection(hit.segment)
        } else {
            // Empty area or segment edge — seek
            viewModel.seek(to: max(0, min(1, x / width)))
        }
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
