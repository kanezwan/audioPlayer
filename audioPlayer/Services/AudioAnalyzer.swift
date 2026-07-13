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
        let normalized = normalize(downsampled)
        let segments = detectSegments(samples: normalized, duration: duration, targetCount: targetWidth, sensitivity: sensitivity)
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

    private func detectSegments(samples: [Float], duration: TimeInterval, targetCount: Int, sensitivity: Float) -> [AudioSegment] {
        guard !samples.isEmpty, duration > 0 else { return [] }

        // Compute the noise floor from the quietest 10% of samples.
        // This gives a much more robust baseline than "mean of everything" when
        // the audio is mostly silence with a few short loud bursts.
        let sortedAsc = samples.sorted()
        let noiseFloorCount = max(1, samples.count / 10)
        let noiseFloor = sortedAsc.prefix(noiseFloorCount).reduce(0, +) / Float(noiseFloorCount)

        // Threshold = noise floor × sensitivity factor.
        // sensitivity = 1.0 → tight (only very loud); 5.0 → loose (include quieter regions).
        // Guard against the noise floor being literally zero (silent file).
        let threshold = max(noiseFloor * sensitivity, 0.0001)

        let sampleDuration = duration / Double(targetCount)

        var aboveThreshold: [(start: Int, end: Int)] = []
        var i = 0
        while i < samples.count {
            if samples[i] > threshold {
                let start = i
                while i < samples.count && samples[i] > threshold {
                    i += 1
                }
                aboveThreshold.append((start, i - 1))
            } else {
                i += 1
            }
        }

        // Merge regions closer than 0.5 seconds
        let mergeSamples = Int(0.5 / sampleDuration)
        var merged: [(start: Int, end: Int)] = []
        for region in aboveThreshold {
            if let last = merged.last, (region.start - last.end) <= mergeSamples {
                merged[merged.count - 1] = (last.start, region.end)
            } else {
                merged.append(region)
            }
        }

        // Filter out very short segments (< 0.3s)
        let minSamples = Int(0.3 / sampleDuration)
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
