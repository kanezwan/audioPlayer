import Foundation
import AVFoundation
import AppKit

class AudioExporter {
    private let baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func ensureOutDir() throws -> URL {
        let outDir = baseURL.appendingPathComponent("out")
        if !FileManager.default.fileExists(atPath: outDir.path) {
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        }
        return outDir
    }

    func exportSegment(from sourceURL: URL, segment: AudioSegment, baseTime: TimeInterval?) async throws -> URL {
        let outDir = try ensureOutDir()
        let ext = sourceURL.pathExtension
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let timecode = absTimecodeString(
            start: segment.startTime,
            end: segment.endTime,
            baseTime: baseTime
        )
        let outputName = "\(baseName)_\(timecode).\(ext)"
        let outputURL = outDir.appendingPathComponent(outputName)

        let asset = AVAsset(url: sourceURL)
        let startCMTime = CMTime(seconds: segment.startTime, preferredTimescale: 44100)
        let endCMTime = CMTime(seconds: segment.endTime, preferredTimescale: 44100)
        let timeRange = CMTimeRange(start: startCMTime, end: endCMTime)

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw ExporterError.exportSetupFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = exportFileType(for: ext)
        exportSession.timeRange = timeRange

        await exportSession.export()

        guard exportSession.status == .completed else {
            throw ExporterError.exportFailed(exportSession.error)
        }

        return outputURL
    }

    func exportAllSegments(from sourceURL: URL, segments: [AudioSegment], baseTime: TimeInterval? = nil) async throws -> [URL] {
        var exported: [URL] = []
        for segment in segments {
            let url = try await exportSegment(from: sourceURL, segment: segment, baseTime: baseTime)
            exported.append(url)
        }
        return exported
    }

    // MARK: - Timecode

    /// Format as absolute HH:mm:ss-HH:mm:ss when baseTime is available,
    /// otherwise fall back to relative mm:ss-mm:ss.
    private func absTimecodeString(start: TimeInterval, end: TimeInterval, baseTime: TimeInterval?) -> String {
        guard let base = baseTime else {
            return timecodeRelative(start: start, end: end)
        }
        let absStart = base + start
        let absEnd = base + end
        return "\(formatHMS(absStart))-\(formatHMS(absEnd))"
    }

    private func timecodeRelative(start: TimeInterval, end: TimeInterval) -> String {
        let sMin = Int(start) / 60, sSec = Int(start) % 60
        let eMin = Int(end) / 60, eSec = Int(end) % 60
        return String(format: "%02d:%02d-%02d:%02d", sMin, sSec, eMin, eSec)
    }

    private func formatHMS(_ interval: TimeInterval) -> String {
        let totalSec = Int(interval)
        let h = totalSec / 3600
        let m = (totalSec % 3600) / 60
        let s = totalSec % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private func exportFileType(for ext: String) -> AVFileType {
        switch ext.lowercased() {
        case "wav": return .wav
        case "mp3": return .mp3
        case "aac": return .m4a
        case "m4a": return .m4a
        default: return .wav
        }
    }
}

enum ExporterError: LocalizedError {
    case exportSetupFailed
    case exportFailed(Error?)

    var errorDescription: String? {
        switch self {
        case .exportSetupFailed: return "无法创建导出会话"
        case .exportFailed(let e): return "导出失败: \(e?.localizedDescription ?? "未知错误")"
        }
    }
}


