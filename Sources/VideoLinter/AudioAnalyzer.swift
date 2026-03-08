import Foundation
import AVFoundation
import CoreMedia
import Accelerate

// MARK: - Audio analysis: LUFS, peaks, silence detection

enum AudioAnalyzer {

    // MARK: - K-weighting biquad filter (ITU-R BS.1770-4)

    private struct BiquadFilter {
        var b0, b1, b2, a1, a2: Double
        var z1: Double = 0
        var z2: Double = 0

        /// Direct form II transposed biquad
        mutating func process(_ x: Double) -> Double {
            let y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            return y
        }
    }

    /// Returns (stage1, stage2) K-weighting biquad filters for the given sample rate.
    private static func kWeightingFilters(sampleRate: Double) -> (BiquadFilter, BiquadFilter) {
        // Stage 1: High-shelf pre-filter
        let f1: Double = 1681.974450955533
        let G:  Double = 3.99984385397
        let Q1: Double = 0.7071752369554196
        let K1 = tan(.pi * f1 / sampleRate)
        let Vh = pow(10.0, G / 20.0)
        let Vb = pow(Vh, 0.4996667741545416)
        let a0_1 = 1.0 + K1 / Q1 + K1 * K1
        let stage1 = BiquadFilter(
            b0: (Vh + Vb * K1 / Q1 + K1 * K1) / a0_1,
            b1: 2.0 * (K1 * K1 - Vh) / a0_1,
            b2: (Vh - Vb * K1 / Q1 + K1 * K1) / a0_1,
            a1: 2.0 * (K1 * K1 - 1.0) / a0_1,
            a2: (1.0 - K1 / Q1 + K1 * K1) / a0_1
        )

        // Stage 2: RLB high-pass
        let f2: Double = 38.13547087602444
        let Q2: Double = 0.5003270373238773
        let K2 = tan(.pi * f2 / sampleRate)
        let a0_2 = 1.0 + K2 / Q2 + K2 * K2
        let stage2 = BiquadFilter(
            b0:  1.0 / a0_2,
            b1: -2.0 / a0_2,
            b2:  1.0 / a0_2,
            a1: 2.0 * (K2 * K2 - 1.0) / a0_2,
            a2: (1.0 - K2 / Q2 + K2 * K2) / a0_2
        )

        return (stage1, stage2)
    }

    // MARK: - Public entry point

    struct AudioAnalysisResult {
        let lufsChecks: [CheckResult]
        let silenceCheck: CheckResult
        let peakCheck: CheckResult
    }

    static func analyze(
        asset: AVAsset,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> AudioAnalysisResult {

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        guard let audioTrack = audioTracks.first else {
            let noAudio = CheckResult(
                checkName: "Audio",
                status: .fail,
                summary: "No audio track found",
                detail: "YouTube requires an audio track."
            )
            return AudioAnalysisResult(
                lufsChecks: [noAudio],
                silenceCheck: noAudio,
                peakCheck: noAudio
            )
        }

        let formatDescs = try await audioTrack.load(.formatDescriptions)
        var sampleRate: Double = 48000
        var channelCount: Int  = 2

        if let desc = formatDescs.first,
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
            sampleRate   = asbd.pointee.mSampleRate
            channelCount = Int(asbd.pointee.mChannelsPerFrame)
        }

        let asset_duration = try await asset.load(.duration).seconds

        // Set up AVAssetReader for linear PCM
        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey:             Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey:    32,
            AVLinearPCMIsFloatKey:     true,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        audioOutput.alwaysCopiesSampleData = false
        reader.add(audioOutput)

        guard reader.startReading() else {
            throw AnalysisError.readerFailed(reader.error?.localizedDescription ?? "AVAssetReader failed to start")
        }

        // Per-channel K-weighting filter state
        var stage1Filters = Array(repeating: kWeightingFilters(sampleRate: sampleRate).0, count: channelCount)
        var stage2Filters = Array(repeating: kWeightingFilters(sampleRate: sampleRate).1, count: channelCount)
        var kWeightedSumSq = Array(repeating: 0.0, count: channelCount)

        // totalAudioFrames counts every decoded audio frame — used for LUFS mean square denominator
        var totalAudioFrames: Int64 = 0
        var peakAbs: Float          = 0

        // Silence tracking: 100 ms windows, -60 dBFS RMS threshold
        let silenceWindowFrames = Int(sampleRate * 0.1)
        var silenceWindowSumSq: Double  = 0
        var silenceWindowCount: Int     = 0
        var completedWindowFrames: Int64 = 0  // tracks position for silence timestamps
        var silenceStart: TimeInterval? = nil
        var silenceGaps: [(start: TimeInterval, end: TimeInterval)] = []
        let silenceThreshold: Double = 0.001  // -60 dBFS amplitude

        // Read all sample buffers
        while let sampleBuffer = audioOutput.copyNextSampleBuffer() {
            try Task.checkCancellation()

            let numFrames = CMSampleBufferGetNumSamples(sampleBuffer)
            guard numFrames > 0,
                  let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }

            var dataLength: Int = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0,
                                        lengthAtOffsetOut: nil,
                                        totalLengthOut: &dataLength,
                                        dataPointerOut: &dataPointer)

            guard let rawPtr = dataPointer else { continue }

            let floatPtr   = UnsafeRawPointer(rawPtr).bindMemory(to: Float.self, capacity: dataLength / 4)
            let floatCount = dataLength / MemoryLayout<Float>.size
            let frames     = floatCount / max(channelCount, 1)

            for f in 0..<frames {
                var monoAbsSum: Double = 0

                for ch in 0..<channelCount {
                    let sample = Double(floatPtr[f * channelCount + ch])
                    let absF   = Float(abs(sample))
                    if absF > peakAbs { peakAbs = absF }

                    // K-weighting: stage1 (high-shelf) → stage2 (high-pass)
                    let s1 = stage1Filters[ch].process(sample)
                    let s2 = stage2Filters[ch].process(s1)
                    kWeightedSumSq[ch] += s2 * s2

                    monoAbsSum += abs(sample)
                }
                totalAudioFrames += 1

                let monoSample = monoAbsSum / Double(channelCount)
                silenceWindowSumSq += monoSample * monoSample
                silenceWindowCount += 1

                // Evaluate silence window when full
                if silenceWindowCount >= silenceWindowFrames {
                    let rms = sqrt(silenceWindowSumSq / Double(silenceWindowCount))
                    let windowStartTime = Double(completedWindowFrames) / sampleRate

                    if rms < silenceThreshold {
                        if silenceStart == nil { silenceStart = windowStartTime }
                    } else if let start = silenceStart {
                        let end = windowStartTime + 0.1
                        if end - start >= 2.0 {
                            silenceGaps.append((start: start, end: end))
                        }
                        silenceStart = nil
                    }

                    completedWindowFrames += Int64(silenceWindowCount)
                    silenceWindowSumSq = 0
                    silenceWindowCount = 0
                }
            }

            // Report progress via presentation timestamp
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            if asset_duration > 0 {
                onProgress(min(pts / asset_duration, 1.0))
            }
        }

        reader.cancelReading()

        // Close any trailing silence gap
        if let start = silenceStart {
            let end = Double(totalAudioFrames) / sampleRate
            if end - start >= 2.0 {
                silenceGaps.append((start: start, end: end))
            }
        }

        let measuredFrames = max(totalAudioFrames, 1)

        // LUFS (BS.1770-4, ungated integrated loudness)
        let channelMeanSqSum = kWeightedSumSq.reduce(0, +) / Double(measuredFrames)
        let lufs = channelMeanSqSum > 0
            ? -0.691 + 10.0 * log10(channelMeanSqSum)
            : -Double.infinity

        // Peak (sample peak in dBFS)
        let peakdBFS = peakAbs > 0
            ? 20.0 * log10(Double(peakAbs))
            : -Double.infinity

        return AudioAnalysisResult(
            lufsChecks: buildLUFSChecks(lufs: lufs),
            silenceCheck: buildSilenceCheck(silenceGaps: silenceGaps),
            peakCheck: buildPeakCheck(peakdBFS: peakdBFS)
        )
    }

    // MARK: - Result builders

    private static func buildLUFSChecks(lufs: Double) -> [CheckResult] {
        let lufsStr = lufs.isFinite
            ? String(format: "%.1f LUFS", lufs)
            : "–∞ LUFS (silent)"

        let loudnessCheck: CheckResult
        if lufs < -23.0 {
            loudnessCheck = CheckResult(
                checkName: "Audio Loudness",
                status: .fail,
                summary: "\(lufsStr) — below –23 LUFS minimum",
                detail: "YouTube normalises to –14 LUFS. Audio this quiet will be boosted aggressively, increasing noise."
            )
        } else {
            loudnessCheck = CheckResult(
                checkName: "Audio Loudness",
                status: .pass,
                summary: lufsStr,
                detail: nil
            )
        }

        return [loudnessCheck]
    }

    private static func buildPeakCheck(peakdBFS: Double) -> CheckResult {
        let peakStr = peakdBFS.isFinite
            ? String(format: "%.1f dBFS", peakdBFS)
            : "–∞ dBFS"

        if peakdBFS > -1.0 {
            return CheckResult(
                checkName: "Audio Peak",
                status: .fail,
                summary: "Peak \(peakStr) — clipping above –1 dBFS",
                detail: "Clipping causes audible distortion. Lower the master volume and re-export."
            )
        }
        return CheckResult(
            checkName: "Audio Peak",
            status: .pass,
            summary: "Peak \(peakStr)",
            detail: nil
        )
    }

    private static func buildSilenceCheck(
        silenceGaps: [(start: TimeInterval, end: TimeInterval)]
    ) -> CheckResult {
        if silenceGaps.isEmpty {
            return CheckResult(
                checkName: "Complete Silence",
                status: .pass,
                summary: "No silence gaps detected",
                detail: nil
            )
        }

        let detail = silenceGaps.map { gap in
            let dur = gap.end - gap.start
            return "Complete silence at \(TimeFormatter.formatRange(start: gap.start, end: gap.end)) (\(String(format: "%.1f", dur)) s)"
        }.joined(separator: "\n")

        let count = silenceGaps.count
        return CheckResult(
            checkName: "Complete Silence",
            status: .fail,
            summary: "\(count) silence gap\(count == 1 ? "" : "s") detected (≥ 2 s of flat/zero signal)",
            detail: detail
        )
    }
}

// MARK: - Errors

enum AnalysisError: LocalizedError {
    case noVideoTrack
    case readerFailed(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:        return "No video track found in file."
        case .readerFailed(let m): return "Asset reader error: \(m)"
        }
    }
}
