import Foundation
import AVFoundation

struct AudioAnalysis {
    let samples: [Float]          // normalized amplitudes 0.0~1.0
    let segments: [AudioSegment]
    let duration: TimeInterval
}

class AudioAnalyzer {
    func analyze(url: URL, targetWidth: Int = 1000, sensitivity: Float = 2.0) async throws -> AudioAnalysis {
        let (rawSamples, duration) = try await extractPCM(from: url)
        let downsampled = downsample(samples: rawSamples, targetCount: targetWidth)

        // Detect segments on raw (un-normalized) amplitudes.
        // Normalization would compress the dynamic range and make quiet regions
        // appear artificially high, so detection runs on the original scale.
        let segments = detectSegments(
            rawSamples: downsampled,
            duration: duration,
            targetCount: targetWidth,
            sensitivity: sensitivity
        )

        // Normalize AFTER detection — display only.
        let normalized = normalize(downsampled)
        return AudioAnalysis(samples: normalized, segments: segments, duration: duration)
    }

    // MARK: - PCM Extraction

    private func extractPCM(from url: URL) async throws -> ([Float], TimeInterval) {
        let asset = AVAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AnalyzerError.noAudioTrack
        }

        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(output)
        guard reader.startReading() else {
            throw AnalyzerError.readFailed(reader.error)
        }

        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            if let blockBuffer = CMSampleBufferGetDataBuffer(buffer) {
                var length = 0
                var dataPointer: UnsafeMutablePointer<Int8>?
                CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
                if let data = dataPointer {
                    let count = length / MemoryLayout<Float>.stride
                    let floats = UnsafeBufferPointer(start: data.withMemoryRebound(to: Float.self, capacity: count) { $0 }, count: count)
                    samples.append(contentsOf: Array(floats))
                }
            }
        }

        guard reader.status == .completed else {
            throw AnalyzerError.readFailed(reader.error)
        }

        return (samples, durationSeconds)
    }

    // MARK: - Downsampling

    private func downsample(samples: [Float], targetCount: Int) -> [Float] {
        guard !samples.isEmpty, targetCount > 0 else { return [] }
        let bucketSize = max(1, samples.count / targetCount)
        var result: [Float] = []
        for i in stride(from: 0, to: samples.count, by: bucketSize) {
            let end = min(i + bucketSize, samples.count)
            let bucket = samples[i..<end]
            let maxVal = bucket.map { abs($0) }.max() ?? 0
            result.append(maxVal)
        }
        return result
    }

    // MARK: - Normalization

    private func normalize(_ samples: [Float]) -> [Float] {
        guard let maxVal = samples.max(), maxVal > 0 else { return samples }
        return samples.map { $0 / maxVal }
    }

    // MARK: - Segment Detection

    /// Detects high-amplitude regions on RAW (un-normalized) downsampled amplitudes.
    ///
    /// Threshold = global max amplitude ÷ sensitivity.
    /// sensitivity = 1.0 → only the single loudest sample passes
    /// sensitivity = 2.0 → amplitudes ≥ 50% of max pass (default, good for 2 clear peaks)
    /// sensitivity = 5.0 → amplitudes ≥ 20% of max pass (more inclusive)
    private func detectSegments(rawSamples: [Float], duration: TimeInterval, targetCount: Int, sensitivity: Float) -> [AudioSegment] {
        guard !rawSamples.isEmpty, duration > 0 else { return [] }

        guard let globalMax = rawSamples.max(), globalMax > 0 else { return [] }

        // Threshold relative to the loudest sample in the file.
        // On raw PCM, max is typically 0.3–0.8.  Background noise is ~0.001–0.01.
        // threshold = 0.5 / 2.0 = 0.25  ⇒ only the true peaks survive.
        let threshold = globalMax / sensitivity

        let sampleDuration = duration / Double(targetCount)

        var aboveThreshold: [(start: Int, end: Int)] = []
        var i = 0
        while i < rawSamples.count {
            if rawSamples[i] > threshold {
                let start = i
                while i < rawSamples.count && rawSamples[i] > threshold {
                    i += 1
                }
                aboveThreshold.append((start, i - 1))
            } else {
                i += 1
            }
        }

        // Merge regions within 1.5 seconds of each other
        let mergeSamples = Int(1.5 / sampleDuration)
        var merged: [(start: Int, end: Int)] = []
        for region in aboveThreshold {
            if let last = merged.last, (region.start - last.end) <= mergeSamples {
                merged[merged.count - 1] = (last.start, region.end)
            } else {
                merged.append(region)
            }
        }

        // Filter out very short segments (< 0.5s on raw scale — they're usually clicks, not meaningful audio)
        let minSamples = Int(0.5 / sampleDuration)
        return merged
            .filter { ($0.end - $0.start) >= minSamples }
            .map { AudioSegment(
                startTime: Double($0.start) * sampleDuration,
                endTime: Double($0.end) * sampleDuration
            )}
    }
}

enum AnalyzerError: LocalizedError {
    case noAudioTrack
    case readFailed(Error?)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack: return "音频文件没有音轨"
        case .readFailed(let e): return "读取音频数据失败: \(e?.localizedDescription ?? "未知错误")"
        }
    }
}
