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

    func exportSegment(from sourceURL: URL, segment: AudioSegment) async throws -> URL {
        let outDir = try ensureOutDir()
        let ext = sourceURL.pathExtension
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let timecode = segment.timecodeString()
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

    func exportAllSegments(from sourceURL: URL, segments: [AudioSegment]) async throws -> [URL] {
        var exported: [URL] = []
        for segment in segments {
            let url = try await exportSegment(from: sourceURL, segment: segment)
            exported.append(url)
        }
        return exported
    }

    private func exportFileType(for ext: String) -> AVFileType {
        switch ext.lowercased() {
        case "wav": return .wav
        case "mp3": return .mp3
        case "aac": return .m4a
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
