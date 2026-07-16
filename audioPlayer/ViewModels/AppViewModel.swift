import Foundation
import AVFoundation
import Combine
import AppKit
import Observation

@MainActor
@Observable
class AppViewModel {
    // MARK: - File State
    var openFolderURL: URL?
    var allFileItems: [AudioFileItem] = []
    var displayedCount: Int = 20
    var filterText: String = ""
    var selectedFile: AudioFileItem?
    var playingFile: AudioFileItem?

    // MARK: - Playback State
    var isPlaying: Bool = false
    var isPaused: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var volume: Float = 0.7

    // MARK: - Waveform & Segments
    var waveformSamples: [Float] = []
    var segments: [AudioSegment] = []       // expanded + merged segments shown on waveform
    var selectedSegments: Set<UUID> = []
    var sensitivityFactor: Float = 2.0
    var isLoadingWaveform: Bool = false

    // MARK: - Logs
    var logs: [LogEntry] = []

    // MARK: - Settings
    var isShowingSettings: Bool = false
    var segmentExpansionSeconds: Double = 5.0  // ±N seconds around each detected high-amplitude core

    // MARK: - Drag State
    var isDraggingPlayhead: Bool = false
    private var wasPlayingBeforeDrag: Bool = false
    private var dragCurrentProgress: Double = 0

    var currentTimeDisplay: String {
        formatTimeDisplay(currentTime)
    }

    var dragTimeDisplay: String {
        formatTimeDisplay(dragCurrentProgress * duration)
    }

    // MARK: - Private
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private let scanner = FileScanner()
    private let analyzer = AudioAnalyzer()
    private var exporter: AudioExporter?
    private var exportBaseURL: URL = URL(fileURLWithPath: NSHomeDirectory())

    // MARK: - Computed

    var filteredFiles: [AudioFileItem] {
        if filterText.isEmpty {
            return Array(allFileItems.prefix(displayedCount))
        }
        return allFileItems.filter {
            $0.name.localizedCaseInsensitiveContains(filterText)
        }
    }

    var displayedFiles: [AudioFileItem] {
        let filtered = allFileItems.filter {
            filterText.isEmpty || $0.name.localizedCaseInsensitiveContains(filterText)
        }
        return Array(filtered.prefix(displayedCount))
    }

    var hasMore: Bool {
        let filteredCount = allFileItems.filter {
            filterText.isEmpty || $0.name.localizedCaseInsensitiveContains(filterText)
        }.count
        return displayedCount < filteredCount
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    var currentTimeFormatted: String {
        formatTime(currentTime)
    }

    var durationFormatted: String {
        formatTime(duration)
    }

    // MARK: - Folder Operations

    func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择文件夹"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        openFolderURL = url
        exportBaseURL = url
        exporter = AudioExporter(baseURL: url)

        do {
            allFileItems = try scanner.scanFolder(at: url)
            displayedCount = 20
            addLog("已加载 \(url.path)，共 \(allFileItems.count) 个文件", level: .info)
        } catch {
            addLog("文件夹扫描失败: \(error.localizedDescription)", level: .error)
        }
    }

    func loadNextPage() {
        let filtered = allFileItems.filter {
            filterText.isEmpty || $0.name.localizedCaseInsensitiveContains(filterText)
        }
        if displayedCount < filtered.count {
            displayedCount = min(displayedCount + 20, filtered.count)
        }
    }

    // MARK: - File Selection

    func selectFile(_ item: AudioFileItem) {
        guard item.id != selectedFile?.id else { return }
        selectedFile = item
        stopPlayback()
        loadWaveform(for: item)
    }

    func doubleClickFile(_ item: AudioFileItem) {
        if selectedFile?.id != item.id {
            selectFile(item)
        }
        play(item: item)
    }

    // MARK: - Waveform Loading

    func loadWaveform(for item: AudioFileItem) {
        guard FileManager.default.isReadableFile(atPath: item.url.path) else {
            addLog("无法访问文件: \(item.name)", level: .error)
            return
        }

        isLoadingWaveform = true
        addLog("正在分析 \(item.name)...", level: .info)

        let analyzer = self.analyzer
        let sensitivity = sensitivityFactor
        let itemName = item.name
        let fileUrl = item.url

        Task.detached { [weak self] in
            do {
                let analysis = try await analyzer.analyze(
                    url: fileUrl,
                    targetWidth: 1000,
                    sensitivity: sensitivity
                )
                await MainActor.run {
                    guard let self = self else { return }
                    self.waveformSamples = analysis.samples
                    self.duration = analysis.duration
                    self.segments = self.expandAndMergeSegments(
                        analysis.segments,
                        duration: analysis.duration
                    )
                    self.selectedSegments = []
                    self.isLoadingWaveform = false
                    self.addLog("\(itemName) 检测到 \(self.segments.count) 个段落", level: .info)
                }
            } catch {
                await MainActor.run {
                    guard let self = self else { return }
                    self.waveformSamples = []
                    self.segments = []
                    self.duration = 0
                    self.isLoadingWaveform = false
                    self.addLog("\(itemName) 分析失败: \(error.localizedDescription)", level: .error)
                }
            }
        }
    }

    func reanalyzeSegments() {
        guard let file = selectedFile else { return }
        loadWaveform(for: file)
    }

    // MARK: - Playback

    func play(item: AudioFileItem) {
        guard FileManager.default.isReadableFile(atPath: item.url.path) else {
            addLog("无法播放: \(item.name)", level: .error)
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: item.url)
            audioPlayer?.volume = volume
            audioPlayer?.play()
            playingFile = item
            isPlaying = true
            isPaused = false
            duration = audioPlayer?.duration ?? 0
            startTimer()
        } catch {
            addLog("播放失败: \(error.localizedDescription)", level: .error)
        }
    }

    func togglePlayPause() {
        if isPlaying, !isPaused {
            audioPlayer?.pause()
            isPaused = true
            stopTimer()
        } else if let player = audioPlayer, isPaused {
            player.play()
            isPaused = false
            startTimer()
        } else if let file = selectedFile {
            play(item: file)
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        isPaused = false
        currentTime = 0
        stopTimer()
    }

    func seek(to progress: Double) {
        guard let player = audioPlayer else { return }
        player.currentTime = progress * player.duration
        currentTime = player.currentTime
    }

    func setVolume(_ value: Float) {
        volume = value
        audioPlayer?.volume = value
    }

    func skip(by seconds: TimeInterval) {
        guard let player = audioPlayer else { return }
        let target = max(0, min(player.duration, player.currentTime + seconds))
        player.currentTime = target
        currentTime = target
    }

    // MARK: - Segment Operations

    /// User-created segment (from drag on empty area)
    func createSegment(start: TimeInterval, end: TimeInterval) {
        guard duration > 0 else { return }
        let clampedStart = max(0, min(duration, start))
        let clampedEnd = max(0, min(duration, end))
        guard clampedEnd - clampedStart >= 0.2 else { return }
        let new = AudioSegment(startTime: clampedStart, endTime: clampedEnd)
        segments.append(new)
        selectedSegments = [new.id]
    }

    /// Replace a segment's time range (used by drag-to-move / drag-to-resize)
    func moveSegment(_ id: UUID, to newSegment: AudioSegment) {
        guard let idx = segments.firstIndex(where: { $0.id == id }) else { return }
        segments[idx] = AudioSegment(startTime: newSegment.startTime, endTime: newSegment.endTime)
    }

    func toggleSegmentSelection(_ segment: AudioSegment) {
        if selectedSegments.contains(segment.id) {
            selectedSegments.remove(segment.id)
        } else {
            selectedSegments.insert(segment.id)
        }
    }

    func selectAllSegments() {
        selectedSegments = Set(segments.map { $0.id })
    }

    func clearSegmentSelection() {
        selectedSegments = []
    }

    /// 删除当前选中的段落（按 Delete / Backspace 触发）
    func deleteSelectedSegments() {
        guard !selectedSegments.isEmpty else { return }
        segments.removeAll { selectedSegments.contains($0.id) }
        let count = selectedSegments.count
        selectedSegments = []
        addLog("已删除 \(count) 个段落", level: .info)
    }

    func exportSelectedSegments() {
        guard let file = selectedFile,
              let exporter = exporter,
              !selectedSegments.isEmpty else {
            addLog("没有选中段落或未选择文件", level: .warning)
            return
        }

        let toExport = segments.filter { selectedSegments.contains($0.id) }
        let baseTime = parseBaseTime(from: file.name)

        Task {
            addLog("开始导出 \(toExport.count) 个段落...", level: .info)
            do {
                let urls = try await exporter.exportAllSegments(from: file.url, segments: toExport, baseTime: baseTime)
                addLog("导出完成，共 \(urls.count) 个文件", level: .info)
                if let outDir = try? exporter.ensureOutDir() {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: outDir.path)
                }
            } catch {
                addLog("导出失败: \(error.localizedDescription)", level: .error)
            }
        }
    }

    func exportAllSegments() {
        guard let file = selectedFile,
              let exporter = exporter,
              !segments.isEmpty else {
            addLog("没有可导出的段落", level: .warning)
            return
        }

        let baseTime = parseBaseTime(from: file.name)

        Task {
            addLog("开始导出全部 \(segments.count) 个段落...", level: .info)
            do {
                let urls = try await exporter.exportAllSegments(from: file.url, segments: segments, baseTime: baseTime)
                addLog("导出完成，共 \(urls.count) 个文件", level: .info)
                if let outDir = try? exporter.ensureOutDir() {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: outDir.path)
                }
            } catch {
                addLog("导出失败: \(error.localizedDescription)", level: .error)
            }
        }
    }

    // MARK: - Filename Time Parsing

    /// Extract a base time from a filename like `R20260713-200012.WAV`.
    /// Returns nil if the filename doesn't match the expected pattern.
    func parseBaseTime(from filename: String) -> TimeInterval? {
        // Pattern: RYYYYMMDD-HHMMSS or similar prefix_date-time.extension
        let name = (filename as NSString).deletingPathExtension
        let parts = name.components(separatedBy: "-")
        // Look for a 6-digit time part (HHMMSS)
        for part in parts.reversed() {
            if part.count == 6, let hour = Int(part.prefix(2)),
               let min = Int(part.dropFirst(2).prefix(2)),
               let sec = Int(part.dropFirst(4).prefix(2)),
               (0...23).contains(hour), (0...59).contains(min), (0...59).contains(sec) {
                return TimeInterval(hour * 3600 + min * 60 + sec)
            }
        }
        return nil
    }

    // MARK: - Segment Expansion & Merge

    /// Expand every raw segment by ±segmentExpansionSeconds, then merge
    /// overlapping expanded segments into unified boxes.
    /// Each visible box corresponds to one high-amplitude region.
    private func expandAndMergeSegments(_ raw: [AudioSegment], duration: TimeInterval) -> [AudioSegment] {
        guard !raw.isEmpty else { return [] }

        let expansion = segmentExpansionSeconds

        // Step 1 — expand
        let expanded = raw.map { seg -> AudioSegment in
            let newStart = max(0, seg.startTime - expansion)
            let newEnd = min(duration, seg.endTime + expansion)
            return AudioSegment(startTime: newStart, endTime: newEnd)
        }.sorted { $0.startTime < $1.startTime }

        // Step 2 — merge overlapping
        var merged: [AudioSegment] = []
        for seg in expanded {
            if let last = merged.last, seg.startTime <= last.endTime {
                merged[merged.count - 1] = AudioSegment(
                    startTime: last.startTime,
                    endTime: max(last.endTime, seg.endTime)
                )
            } else {
                merged.append(seg)
            }
        }
        return merged
    }

    // MARK: - Playhead Drag

    func beginPlayheadDrag() {
        wasPlayingBeforeDrag = isPlaying && !isPaused
        if wasPlayingBeforeDrag {
            audioPlayer?.pause()
            isPaused = true
            stopTimer()
        }
        isDraggingPlayhead = true
    }

    func updatePlayheadDrag(to progress: Double) {
        let clamped = max(0, min(1, progress))
        dragCurrentProgress = clamped
        guard let player = audioPlayer else { return }
        player.currentTime = clamped * player.duration
        currentTime = player.currentTime
    }

    func endPlayheadDrag() {
        isDraggingPlayhead = false
        if wasPlayingBeforeDrag, let player = audioPlayer {
            player.play()
            isPaused = false
            startTimer()
        }
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let player = self.audioPlayer else { return }
                self.currentTime = player.currentTime
                if !player.isPlaying && self.isPlaying {
                    self.isPlaying = false
                    self.isPaused = false
                    self.stopTimer()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Logging

    func addLog(_ message: String, level: LogLevel = .info) {
        logs.append(LogEntry(timestamp: Date(), message: message, level: level))
        if logs.count > 200 {
            logs.removeFirst(logs.count - 200)
        }
    }

    // MARK: - Helpers

    private func formatTime(_ time: TimeInterval) -> String {
        let total = Int(time)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private func formatTimeDisplay(_ time: TimeInterval) -> String {
        let min = Int(time) / 60
        let sec = time - TimeInterval(min * 60)
        return String(format: "%02d:%05.2f", min, sec)
    }
}
