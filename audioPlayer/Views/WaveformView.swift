import SwiftUI

struct WaveformView: View {
    @Environment(AppViewModel.self) private var viewModel

    @State private var dragMode: DragMode = .none
    @State private var dragStartX: CGFloat = 0
    @State private var dragCurrentX: CGFloat = 0
    @State private var resizingSegmentId: UUID?
    @State private var draggingSegmentId: UUID?
    @State private var creationLocked: Bool = false

    /// 播放指针颜色 — 橙红色，区别于蓝色波形和段落框
    private let playheadColor = Color(red: 1.0, green: 0.42, blue: 0.21)

    /// 段落框配色 — 柔和的蓝紫色，参考竞品风格
    private let segmentBorderColor = Color(red: 0.45, green: 0.55, blue: 0.85)
    private let segmentFillColor = Color(red: 0.40, green: 0.50, blue: 0.80).opacity(0.12)

    private enum DragMode {
        case none, playhead, creating, movingSegment, resizingLeftEdge, resizingRightEdge
    }
    private enum ResizeEdge { case none, left, right }
    private let edgeHitWidth: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let midY = height / 2
            let amplitudeScale = height * 0.45

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
                    .gesture(
                        DragGesture(minimumDistance: 3)
                            .onChanged { value in handleDragChange(value: value, width: width) }
                            .onEnded { _ in handleDragEnd(width: width) }
                    )
                    .onTapGesture { location in handleStaticTap(at: location.x, width: width) }
                    .contextMenu { segmentContextMenu() }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private var emptyState: some View {
        VStack {
            Image(systemName: "waveform").font(.largeTitle).foregroundColor(.secondary)
            Text("选择音频文件以显示声纹").foregroundColor(.secondary).font(.caption)
        }
    }

    // MARK: - Drawing

    // Thin waveform — top envelope stroke only, no fill.
    private func drawWaveform(context: inout GraphicsContext, width: CGFloat, midY: CGFloat, ampScale: CGFloat) {
        let samples = viewModel.waveformSamples
        guard samples.count > 1 else { return }
        let xStep = width / CGFloat(samples.count - 1)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: midY))
        for (i, sample) in samples.enumerated() {
            let x = CGFloat(i) * xStep
            let y = midY - CGFloat(sample) * ampScale
            path.addLine(to: CGPoint(x: x, y: y))
        }
        context.stroke(path, with: .color(.accentColor),
                       style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round))
    }

    // Segment overlay boxes — 仅绘制已选中的段落，柔和蓝紫配色
    private func drawSegments(context: inout GraphicsContext, width: CGFloat, height: CGFloat) {
        guard !viewModel.segments.isEmpty, !viewModel.selectedSegments.isEmpty, viewModel.duration > 0 else { return }
        let bandY = height * 0.38
        let bandH = height * 0.24
        for segment in viewModel.segments where viewModel.selectedSegments.contains(segment.id) {
            let sx = timeToX(segment.startTime, width: width)
            let ex = timeToX(segment.endTime, width: width)
            let rect = CGRect(x: sx, y: bandY, width: max(ex - sx, 3), height: bandH)
            // 柔和渐变填充 + 细边框
            let rounded = Path(roundedRect: rect, cornerRadius: 4)
            context.fill(rounded, with: .color(segmentFillColor))
            context.stroke(rounded, with: .color(segmentBorderColor),
                           style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
    }

    private func drawCreatingPreview(context: inout GraphicsContext, width: CGFloat, height: CGFloat) {
        guard dragMode == .creating else { return }
        let x1 = min(dragStartX, dragCurrentX)
        let x2 = max(dragStartX, dragCurrentX)
        let bandY = height * 0.38
        let bandH = height * 0.24
        let rect = CGRect(x: x1, y: bandY, width: max(x2 - x1, 3), height: bandH)
        let rounded = Path(roundedRect: rect, cornerRadius: 4)
        context.fill(rounded, with: .color(segmentFillColor))
        context.stroke(rounded, with: .color(segmentBorderColor),
                       style: StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
    }

    // Blue solid line + circle endpoints (dot at top, dot at bottom) — 橙红色播放指针
    private func drawPlayhead(context: inout GraphicsContext, width: CGFloat, height: CGFloat) {
        let progress = viewModel.progress
        guard progress >= 0, progress <= 1.0 else { return }
        let x = CGFloat(progress) * width
        let h = height * 0.6
        let y = (height - h) / 2
        // Vertical line — 使用橙红色区分于波形和段落框
        let line = Path(CGRect(x: x - 1, y: y, width: 2, height: h))
        context.fill(line, with: .color(playheadColor))
        // Circle at top
        let topDot = Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6))
        context.fill(topDot, with: .color(playheadColor))
        // Circle at bottom
        let bottomDot = Path(ellipseIn: CGRect(x: x - 3, y: y + h - 3, width: 6, height: 6))
        context.fill(bottomDot, with: .color(playheadColor))
    }

    // MARK: - Coordinate helpers

    private func timeToX(_ t: TimeInterval, width: CGFloat) -> CGFloat {
        guard viewModel.duration > 0 else { return 0 }
        return CGFloat(t / viewModel.duration) * width
    }
    private func xToTime(_ x: CGFloat, width: CGFloat) -> TimeInterval {
        max(0, min(1, x / width)) * viewModel.duration
    }
    /// 仅在已选中的段落中进行命中测试（与 drawSegments 一致：只显示选中项）
    private func segmentHit(at x: CGFloat, width: CGFloat) -> (segment: AudioSegment, edge: ResizeEdge) {
        for seg in viewModel.segments where viewModel.selectedSegments.contains(seg.id) {
            let sx = timeToX(seg.startTime, width: width)
            let ex = timeToX(seg.endTime, width: width)
            if x >= sx && x <= ex {
                let e: ResizeEdge
                if x < sx + edgeHitWidth { e = .left }
                else if x > ex - edgeHitWidth { e = .right }
                else { e = .none }
                return (seg, e)
            }
        }
        return (AudioSegment(startTime: 0, endTime: 0), .none)
    }
    private func isNearPlayhead(x: CGFloat, width: CGFloat) -> Bool {
        abs(x - CGFloat(viewModel.progress) * width) < 12
    }

    // MARK: - Static tap

    private func handleStaticTap(at x: CGFloat, width: CGFloat) {
        guard viewModel.duration > 0 else { return }
        if isNearPlayhead(x: x, width: width) { return }
        let hit = segmentHit(at: x, width: width)
        if hit.segment.endTime > 0 && hit.edge == .none {
            viewModel.toggleSegmentSelection(hit.segment)
        } else {
            viewModel.seek(to: max(0, min(1, x / width)))
        }
    }

    // MARK: - Drag

    private func handleDragChange(value: DragGesture.Value, width: CGFloat) {
        dragCurrentX = value.location.x
        switch dragMode {
        case .none:
            dragStartX = value.startLocation.x
            if isNearPlayhead(x: value.startLocation.x, width: width) {
                dragMode = .playhead
                viewModel.beginPlayheadDrag()
                viewModel.updatePlayheadDrag(to: max(0, min(1, value.location.x / width)))
            } else {
                let hit = segmentHit(at: value.startLocation.x, width: width)
                if hit.segment.endTime > 0 {
                    draggingSegmentId = hit.segment.id
                    switch hit.edge {
                    case .left:  dragMode = .resizingLeftEdge;  resizingSegmentId = hit.segment.id
                    case .right: dragMode = .resizingRightEdge; resizingSegmentId = hit.segment.id
                    case .none:  dragMode = .movingSegment
                    }
                } else {
                    if !creationLocked { dragMode = .creating }
                }
            }
        case .playhead:
            viewModel.updatePlayheadDrag(to: max(0, min(1, value.location.x / width)))
        case .creating: break
        case .movingSegment:
            guard let id = draggingSegmentId, let seg = viewModel.segments.first(where: { $0.id == id }) else { return }
            let dt = xToTime(value.location.x - value.startLocation.x, width: width)
            let ns = max(0, min(viewModel.duration - (seg.endTime - seg.startTime), seg.startTime + dt))
            viewModel.moveSegment(id, to: AudioSegment(startTime: ns, endTime: ns + (seg.endTime - seg.startTime)))
        case .resizingLeftEdge:
            guard let id = resizingSegmentId, let seg = viewModel.segments.first(where: { $0.id == id }) else { return }
            let ns = min(xToTime(value.location.x, width: width), seg.endTime - 0.2)
            viewModel.moveSegment(id, to: AudioSegment(startTime: max(0, ns), endTime: seg.endTime))
        case .resizingRightEdge:
            guard let id = resizingSegmentId, let seg = viewModel.segments.first(where: { $0.id == id }) else { return }
            let ne = max(xToTime(value.location.x, width: width), seg.startTime + 0.2)
            viewModel.moveSegment(id, to: AudioSegment(startTime: seg.startTime, endTime: min(viewModel.duration, ne)))
        }
    }

    private func handleDragEnd(width: CGFloat) {
        switch dragMode {
        case .playhead: viewModel.endPlayheadDrag()
        case .creating:
            let x1 = min(dragStartX, dragCurrentX)
            let x2 = max(dragStartX, dragCurrentX)
            if x2 - x1 >= 8, !creationLocked {
                creationLocked = true
                viewModel.createSegment(start: xToTime(x1, width: width), end: xToTime(x2, width: width))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { creationLocked = false }
            }
        default: break
        }
        dragMode = .none; draggingSegmentId = nil; resizingSegmentId = nil
    }

    @ViewBuilder private func segmentContextMenu() -> some View {
        if !viewModel.segments.isEmpty {
            Button("全选段落") { viewModel.selectAllSegments() }
            Button("取消选中") { viewModel.clearSegmentSelection() }
            Divider()
            if !viewModel.selectedSegments.isEmpty {
                Button("导出选中 (\(viewModel.selectedSegments.count))") { viewModel.exportSelectedSegments() }
            }
            Button("导出全部段落 (\(viewModel.segments.count))") { viewModel.exportAllSegments() }
        }
    }
}
