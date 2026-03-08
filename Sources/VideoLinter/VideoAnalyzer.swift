import Foundation
import AVFoundation

// MARK: - Main orchestrator

enum VideoAnalyzer {

    typealias ProgressHandler = @Sendable (Double, String) -> Void

    static func analyze(url: URL, onProgress: @escaping ProgressHandler) async throws -> [CheckResult] {
        var results: [CheckResult] = []

        // ── 1. Load asset ─────────────────────────────────────────────────────
        onProgress(0.02, "Loading asset…")
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

        // Quick sanity: is this a readable media file?
        let isPlayable = try await asset.load(.isPlayable)
        guard isPlayable else {
            throw AnalysisError.readerFailed("File is not a playable media asset.")
        }

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw AnalysisError.noVideoTrack
        }

        // ── 2. Track properties ───────────────────────────────────────────────
        onProgress(0.05, "Checking video properties…")
        let trackChecks = try await TrackAnalyzer.checkVideoTrack(videoTrack)
        results.append(contentsOf: trackChecks)

        // ── 3. Duration ───────────────────────────────────────────────────────
        onProgress(0.12, "Checking duration…")
        let durationCheck = try await TrackAnalyzer.checkDuration(asset: asset)
        results.append(durationCheck)

        // ── 4. A/V sync ───────────────────────────────────────────────────────
        onProgress(0.15, "Checking A/V sync…")
        let syncCheck = try await TrackAnalyzer.checkAVSync(asset: asset)
        results.append(syncCheck)

        // ── 5. Black frames ───────────────────────────────────────────────────
        onProgress(0.18, "Scanning for black frames…")
        let blackFrameCheck = try await BlackFrameAnalyzer.detectBlackFrames(
            asset: asset,
            onProgress: { p in onProgress(0.18 + p * 0.32, "Scanning for black frames…") }
        )
        results.append(blackFrameCheck)

        // ── 6. Audio analysis ─────────────────────────────────────────────────
        onProgress(0.50, "Analysing audio…")
        let audioResult = try await AudioAnalyzer.analyze(
            asset: asset,
            onProgress: { p in onProgress(0.50 + p * 0.47, "Analysing audio…") }
        )
        results.append(contentsOf: audioResult.lufsChecks)
        results.append(audioResult.peakCheck)
        results.append(audioResult.silenceCheck)

        onProgress(1.0, "Complete")
        return results
    }
}
