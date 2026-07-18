import SwiftUI

// MARK: - File-scope types & geometry shared between WaveformView and HoverTrackingNSView

private enum ResizeEdge { case none, left, right }
private typealias TimeToXFunc = (TimeInterval, CGFloat) -> CGFloat

/// 段落框在屏幕上的最小可视/可交互宽度。1 小时的波形里一个 10 秒的段落只有几个像素宽，
/// 不做下限的话既看不清也拖不到边缘。
private let segmentMinBoxWidth: CGFloat = 18
/// 边缘热区上限。实际热区取 min(上限, 框宽/3)，保证窄框仍留出中间的「框体」区域。
private let segmentMaxEdgeHit: CGFloat = 9

/// 把一段时间的 [起点, 终点] 像素范围撑到最小可视宽度（以中心为锚点）。
private func segmentBox(startX: CGFloat, endX: CGFloat) -> (x0: CGFloat, x1: CGFloat) {
    let w = endX - startX
    guard w < segmentMinBoxWidth else { return (startX, endX) }
    let center = (startX + endX) / 2
    return (center - segmentMinBoxWidth / 2, center + segmentMinBoxWidth / 2)
}

private func edgeHitWidth(boxWidth: CGFloat) -> CGFloat {
    max(3, min(segmentMaxEdgeHit, boxWidth / 3))
}

/// 命中测试 —— 与绘制使用同一套 box 几何，所见即所点。
private func hitTestSegment(
    x: CGFloat,
    width: CGFloat,
    segments: [AudioSegment],
    timeToX: TimeToXFunc
) -> (segment: AudioSegment, edge: ResizeEdge)? {
    for seg in segments {
        let box = segmentBox(startX: timeToX(seg.startTime, width), endX: timeToX(seg.endTime, width))
        guard x >= box.x0, x <= box.x1 else { continue }
        let hit = edgeHitWidth(boxWidth: box.x1 - box.x0)
        // 先判右边缘再判左边缘：窄框上两侧热区可能重叠，
        // 谁离得近谁赢，避免右边缘永远够不到。
        let edge: ResizeEdge
        if x >= box.x1 - hit && (box.x1 - x) <= (x - box.x0) {
            edge = .right
        } else if x <= box.x0 + hit {
            edge = .left
        } else {
            edge = .none
        }
        return (seg, edge)
    }
    return nil
}

// MARK: - NSView wrapper for per-pixel mouse tracking & cursor changes

private struct HoverTrackingView: NSViewRepresentable {
    var width: CGFloat
    let segments: [AudioSegment]
    let duration: TimeInterval
    let timeToX: TimeToXFunc

    func makeNSView(context: Context) -> NSView {
        let view = HoverTrackingNSView()
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? HoverTrackingNSView else { return }
        view.segments = segments
        view.duration = duration
        view.viewWidth = width
        view.timeToXClosure = timeToX
    }
}

private class HoverTrackingNSView: NSView {
    var segments: [AudioSegment] = []
    var duration: TimeInterval = 0
    var viewWidth: CGFloat = 0
    var timeToXClosure: TimeToXFunc?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseMoved(with event: NSEvent) {
        guard let timeToX = timeToXClosure else { return }
        let localPoint = convert(event.locationInWindow, from: nil)
        let hit = hitTestSegment(
            x: localPoint.x,
            width: max(viewWidth, 1),
            segments: segments,
            timeToX: timeToX
        )
        switch hit?.edge {
        case .left:  NSCursor.resizeLeftRight.set()
        case .right: NSCursor.resizeLeftRight.set()
        case .none where hit != nil: NSCursor.openHand.set()
        default: NSCursor.arrow.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }
}

// MARK: - Main Waveform View

struct WaveformView: View {
    @Environment(AppViewModel.self) private var viewModel

    @State private var dragMode: DragMode = .none
    @State private var dragStartX: CGFloat = 0
    @State private var dragCurrentX: CGFloat = 0
    @State private var resizingSegmentId: UUID?
    @State private var draggingSegmentId: UUID?
    @State private var creationLocked: Bool = false
    @FocusState private var isFocused: Bool

    /// 播放指针颜色 — 橙红色，区别于蓝色波形和段落框
    private let playheadColor = Color(red: 1.0, green: 0.42, blue: 0.21)

    /// 段落框配色 —— 剪映式：紫色剪辑区，与蓝色波形、橙红指针都能区分
    private let segNormalTint   = Color(red: 0.42, green: 0.40, blue: 0.62)
    private let segSelectedTint = Color(red: 0.42, green: 0.31, blue: 0.93)

    private enum DragMode {
        case none, playhead, creating, movingSegment, resizingLeftEdge, resizingRightEdge
    }
    /// 内部判断拖动是否开始的阈值（替代 DragGesture.minimumDistance）
    private let dragThreshold: CGFloat = 3

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
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in handleDragChange(value: value, width: width) }
                            .onEnded { value in handleDragEnd(value: value, width: width) }
                    )
                    .contextMenu { segmentContextMenu() }
                }
                // NSView overlay for per-pixel cursor tracking
                HoverTrackingView(
                    width: width,
                    segments: viewModel.segments,
                    duration: viewModel.duration,
                    timeToX: timeToX
                )
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        // 让波形区能拿到键盘焦点，Delete / Backspace 才会送到这里，
        // 而不是被侧栏的过滤输入框吃掉。
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress { press in
            guard press.key == .delete || press.key == .deleteForward else { return .ignored }
            guard !viewModel.selectedSegments.isEmpty else { return .ignored }
            viewModel.deleteSelectedSegments()
            return .handled
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

    /// 剪辑框的垂直范围：以波形中线为中心，取可用高度的 40%。
    private func segmentBand(height: CGFloat) -> (y: CGFloat, h: CGFloat) {
        let h = max((height - 12) * 0.4, 12)
        return ((height - h) / 2, h)
    }

    /// 剪映式剪辑框：居中的着色区 + 上下横梁 + 左右可拖拽把手（带握纹）。
    private func drawSegments(context: inout GraphicsContext, width: CGFloat, height: CGFloat) {
        guard !viewModel.segments.isEmpty, viewModel.duration > 0 else { return }
        let (bandY, bandH) = segmentBand(height: height)

        for segment in viewModel.segments {
            let box = segmentBox(startX: timeToX(segment.startTime, width: width),
                                 endX: timeToX(segment.endTime, width: width))
            let boxW = box.x1 - box.x0
            let rect = CGRect(x: box.x0, y: bandY, width: boxW, height: bandH)
            let isSel = viewModel.selectedSegments.contains(segment.id)
            let tint = isSel ? segSelectedTint : segNormalTint

            // 1. 区域着色
            let body = Path(roundedRect: rect, cornerRadius: 4)
            context.fill(body, with: .color(tint.opacity(isSel ? 0.16 : 0.09)))

            // 2. 上下横梁 —— 把左右把手连成一个「夹住」波形的框
            let barH: CGFloat = isSel ? 1.5 : 1
            context.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: boxW, height: barH)),
                         with: .color(tint.opacity(isSel ? 1.0 : 0.55)))
            context.fill(Path(CGRect(x: rect.minX, y: rect.maxY - barH, width: boxW, height: barH)),
                         with: .color(tint.opacity(isSel ? 1.0 : 0.55)))

            // 3. 左右把手
            let handleW = max(2.5, min(5, boxW / 4))
            drawHandle(context: &context, x: rect.minX, y: rect.minY,
                       w: handleW, h: bandH, tint: tint, isSelected: isSel)
            drawHandle(context: &context, x: rect.maxX - handleW, y: rect.minY,
                       w: handleW, h: bandH, tint: tint, isSelected: isSel)

            // 4. 时长标签 —— 画在框的上方，不遮挡波形（框够宽时才画）
            if boxW >= 44 {
                let text = Text(durationLabel(segment.duration))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                let resolved = context.resolve(text)
                let size = resolved.measure(in: CGSize(width: boxW, height: 14))
                let pillW = size.width + 10
                let pill = CGRect(x: rect.midX - pillW / 2, y: max(2, rect.minY - 16),
                                  width: pillW, height: 13)
                context.fill(Path(roundedRect: pill, cornerRadius: 6.5),
                             with: .color(tint.opacity(isSel ? 0.95 : 0.65)))
                context.draw(resolved, at: CGPoint(x: pill.midX, y: pill.midY), anchor: .center)
            }
        }
    }

    /// 单个把手：圆角竖条 + 中间的白色握纹
    private func drawHandle(context: inout GraphicsContext, x: CGFloat, y: CGFloat,
                            w: CGFloat, h: CGFloat, tint: Color, isSelected: Bool) {
        let rect = CGRect(x: x, y: y, width: w, height: h)
        let corners = RoundedRectangle(cornerRadius: 2).path(in: rect)
        context.fill(corners, with: .color(tint.opacity(isSelected ? 1.0 : 0.6)))

        // 握纹只在把手够宽时画
        guard w >= 4.5 else { return }
        let gripH = min(10, h * 0.3)
        let gripY = rect.midY - gripH / 2
        for offset in [-1.0, 1.0] as [CGFloat] {
            let grip = CGRect(x: rect.midX + offset - 0.5, y: gripY, width: 1, height: gripH)
            context.fill(Path(grip), with: .color(.white.opacity(0.85)))
        }
    }

    private func drawCreatingPreview(context: inout GraphicsContext, width: CGFloat, height: CGFloat) {
        guard dragMode == .creating else { return }
        let x1 = min(dragStartX, dragCurrentX)
        let x2 = max(dragStartX, dragCurrentX)
        let band = segmentBand(height: height)
        let rect = CGRect(x: x1, y: band.y, width: max(x2 - x1, 3), height: band.h)
        let rounded = Path(roundedRect: rect, cornerRadius: 4)
        context.fill(rounded, with: .color(segSelectedTint.opacity(0.14)))
        context.stroke(rounded, with: .color(segSelectedTint),
                       style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
    }

    // Blue solid line + circle endpoints (dot at top, dot at bottom) — 橙红色播放指针
    private func drawPlayhead(context: inout GraphicsContext, width: CGFloat, height: CGFloat) {
        let progress = viewModel.progress
        guard progress >= 0, progress <= 1.0 else { return }
        let x = CGFloat(progress) * width
        let h = height * 0.84          // 比原来的 0.6 长 40%
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

    private func durationLabel(_ t: TimeInterval) -> String {
        let total = Int(t.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: - Coordinate helpers

    private func timeToX(_ t: TimeInterval, width: CGFloat) -> CGFloat {
        guard viewModel.duration > 0 else { return 0 }
        return CGFloat(t / viewModel.duration) * width
    }
    private func xToTime(_ x: CGFloat, width: CGFloat) -> TimeInterval {
        max(0, min(1, x / width)) * viewModel.duration
    }
    private func segmentHit(at x: CGFloat, width: CGFloat) -> (segment: AudioSegment, edge: ResizeEdge)? {
        hitTestSegment(x: x, width: width, segments: viewModel.segments, timeToX: timeToX)
    }
    private func isNearPlayhead(x: CGFloat, width: CGFloat) -> Bool {
        abs(x - CGFloat(viewModel.progress) * width) < 12
    }

    // MARK: - Static tap

    private func handleStaticTap(at x: CGFloat, width: CGFloat) {
        guard viewModel.duration > 0 else { return }
        if isNearPlayhead(x: x, width: width) { return }
        if let hit = segmentHit(at: x, width: width) {
            // 点框（含边缘）都算选中 —— 边缘的拖拽由 DragGesture 处理
            viewModel.toggleSegmentSelection(hit.segment)
        } else {
            // Empty area → seek
            viewModel.seek(to: max(0, min(1, x / width)))
        }
    }

    // MARK: - Drag

    private func handleDragChange(value: DragGesture.Value, width: CGFloat) {
        let dx = abs(value.location.x - value.startLocation.x)
        dragCurrentX = value.location.x
        isFocused = true

        switch dragMode {
        case .none:
            // 只有移动超过 threshold 才开始真正拖动（否则视为 pending tap）
            guard dx >= dragThreshold else { return }
            dragStartX = value.startLocation.x
            if isNearPlayhead(x: value.startLocation.x, width: width) {
                dragMode = .playhead
                viewModel.beginPlayheadDrag()
                viewModel.updatePlayheadDrag(to: max(0, min(1, value.location.x / width)))
            } else if let hit = segmentHit(at: value.startLocation.x, width: width) {
                draggingSegmentId = hit.segment.id
                switch hit.edge {
                case .left:  dragMode = .resizingLeftEdge;  resizingSegmentId = hit.segment.id
                case .right: dragMode = .resizingRightEdge; resizingSegmentId = hit.segment.id
                case .none:  dragMode = .movingSegment
                }
            } else {
                if !creationLocked { dragMode = .creating }
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

    private func handleDragEnd(value: DragGesture.Value, width: CGFloat) {
        switch dragMode {
        case .playhead:
            viewModel.endPlayheadDrag()
        case .creating:
            let x1 = min(dragStartX, dragCurrentX)
            let x2 = max(dragStartX, dragCurrentX)
            if x2 - x1 >= 8, !creationLocked {
                creationLocked = true
                viewModel.createSegment(start: xToTime(x1, width: width), end: xToTime(x2, width: width))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { creationLocked = false }
            }
        case .none:
            // No drag mode entered → treat as tap (click without movement)
            handleStaticTap(at: value.startLocation.x, width: width)
        default:
            break
        }
        dragMode = .none; draggingSegmentId = nil; resizingSegmentId = nil
    }

    @ViewBuilder private func segmentContextMenu() -> some View {
        if !viewModel.segments.isEmpty {
            Button("全选段落") { viewModel.selectAllSegments() }
            Button("取消选中") { viewModel.clearSegmentSelection() }
            if viewModel.selectedSegments.count >= 2 {
                Button("合并选中 (\(viewModel.selectedSegments.count))") { viewModel.mergeSelectedSegments() }
            }
            if !viewModel.selectedSegments.isEmpty {
                Button("删除选中", role: .destructive) { viewModel.deleteSelectedSegments() }
                Divider()
                Button("导出选中 (\(viewModel.selectedSegments.count))") { viewModel.exportSelectedSegments() }
            }
            Divider()
            Button("导出全部段落 (\(viewModel.segments.count))") { viewModel.exportAllSegments() }
        }
    }
}
