import Foundation
import AVFoundation
import CoreMedia

// MARK: - Track-level checks (bitrate, resolution, fps, codec, duration, A/V sync)

enum TrackAnalyzer {

    // MARK: Video track checks

    static func checkVideoTrack(_ track: AVAssetTrack) async throws -> [CheckResult] {
        async let bitrateVal      = track.load(.estimatedDataRate)
        async let naturalSizeVal  = track.load(.naturalSize)
        async let transformVal    = track.load(.preferredTransform)
        async let fpsVal          = track.load(.nominalFrameRate)
        async let formatsVal      = track.load(.formatDescriptions)

        let (bitrate, naturalSize, transform, fps, formats) =
            try await (bitrateVal, naturalSizeVal, transformVal, fpsVal, formatsVal)

        return [
            checkBitrate(bitrate),
            checkResolution(naturalSize: naturalSize, transform: transform),
            checkFrameRate(fps),
            checkCodec(formats),
        ]
    }

    // MARK: Asset-level checks

    static func checkDuration(asset: AVAsset) async throws -> CheckResult {
        let duration = try await asset.load(.duration).seconds
        if duration < 60 {
            return CheckResult(
                checkName: "Duration",
                status: .warning,
                summary: "Video is \(TimeFormatter.format(duration)) — under 1 minute",
                detail: "Very short videos may be flagged or demonetised on YouTube."
            )
        }
        return CheckResult(
            checkName: "Duration",
            status: .pass,
            summary: TimeFormatter.format(duration),
            detail: nil
        )
    }

    static func checkAVSync(asset: AVAsset) async throws -> CheckResult {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        guard let videoTrack = videoTracks.first,
              let audioTrack = audioTracks.first else {
            return CheckResult(
                checkName: "A/V Sync",
                status: .skipped,
                summary: "Missing video or audio track — sync check skipped",
                detail: nil
            )
        }

        let videoRange = try await videoTrack.load(.timeRange)
        let audioRange = try await audioTrack.load(.timeRange)

        let videoDur = videoRange.duration.seconds
        let audioDur = audioRange.duration.seconds
        let diff = abs(videoDur - audioDur)

        if diff > 0.5 {
            return CheckResult(
                checkName: "A/V Sync",
                status: .fail,
                summary: String(format: "Stream durations differ by %.3f s (video %.3f s, audio %.3f s)",
                                diff, videoDur, audioDur),
                detail: "A mismatch > 500 ms can cause audio/video drift throughout the video."
            )
        }
        return CheckResult(
            checkName: "A/V Sync",
            status: .pass,
            summary: String(format: "Stream durations match (Δ %.0f ms)", diff * 1000),
            detail: nil
        )
    }

    // MARK: - Private helpers

    private static func checkBitrate(_ bps: Float) -> CheckResult {
        let mbps = Double(bps) / 1_000_000
        let threshold = 25.0
        if mbps < threshold {
            return CheckResult(
                checkName: "Video Bitrate",
                status: .fail,
                summary: String(format: "%.2f Mbps — below 25 Mbps minimum", mbps),
                detail: "Low bitrate causes compression artefacts. Re-export at a higher quality preset."
            )
        }
        return CheckResult(
            checkName: "Video Bitrate",
            status: .pass,
            summary: String(format: "%.2f Mbps", mbps),
            detail: nil
        )
    }

    private static func checkResolution(naturalSize: CGSize, transform: CGAffineTransform) -> CheckResult {
        let displaySize = computeDisplaySize(naturalSize: naturalSize, transform: transform)
        let w = Int(displaySize.width.rounded())
        let h = Int(displaySize.height.rounded())

        if w == 2560 && h == 1440 {
            return CheckResult(
                checkName: "Resolution",
                status: .pass,
                summary: "2560×1440 (QHD)",
                detail: nil
            )
        }
        return CheckResult(
            checkName: "Resolution",
            status: .fail,
            summary: "Found \(w)×\(h) — expected 2560×1440",
            detail: "YouTube recommends exact 2560×1440 for QHD uploads."
        )
    }

    private static func computeDisplaySize(naturalSize: CGSize, transform: CGAffineTransform) -> CGSize {
        // Apply transform to bounding box of the natural-size rectangle
        let corners: [CGPoint] = [
            CGPoint.zero,
            CGPoint(x: naturalSize.width, y: 0),
            CGPoint(x: 0, y: naturalSize.height),
            CGPoint(x: naturalSize.width, y: naturalSize.height),
        ].map { $0.applying(transform) }

        let xs = corners.map { $0.x }
        let ys = corners.map { $0.y }
        return CGSize(
            width:  (xs.max()! - xs.min()!),
            height: (ys.max()! - ys.min()!)
        )
    }

    private static func checkFrameRate(_ fps: Float) -> CheckResult {
        let is30    = abs(fps - 30.000) < 0.05
        let is2997  = abs(fps - 29.970) < 0.05

        if is30 || is2997 {
            return CheckResult(
                checkName: "Frame Rate",
                status: .pass,
                summary: String(format: "%.3f fps", fps),
                detail: nil
            )
        }
        return CheckResult(
            checkName: "Frame Rate",
            status: .fail,
            summary: String(format: "%.3f fps — expected 30 or 29.97", fps),
            detail: "Frame rate mismatch can cause judder or timing issues during playback."
        )
    }

    private static func checkCodec(_ formatDescriptions: [CMFormatDescription]) -> CheckResult {
        guard let desc = formatDescriptions.first else {
            return CheckResult(
                checkName: "Video Codec",
                status: .fail,
                summary: "No video format description found",
                detail: nil
            )
        }

        let subType = CMFormatDescriptionGetMediaSubType(desc)

        // kCMVideoCodecType_H264 == 'avc1'
        if subType == kCMVideoCodecType_H264 {
            return CheckResult(
                checkName: "Video Codec",
                status: .pass,
                summary: "H.264 (avc1)",
                detail: nil
            )
        }

        let fourCC = fourCCString(subType)
        return CheckResult(
            checkName: "Video Codec",
            status: .fail,
            summary: "Codec '\(fourCC)' is not H.264 (avc1)",
            detail: "YouTube accepts H.264 for reliable compatibility. Re-export with H.264 codec."
        )
    }

    private static func fourCCString(_ value: FourCharCode) -> String {
        let bytes: [CChar] = [
            CChar(bitPattern: UInt8((value >> 24) & 0xFF)),
            CChar(bitPattern: UInt8((value >> 16) & 0xFF)),
            CChar(bitPattern: UInt8((value >>  8) & 0xFF)),
            CChar(bitPattern: UInt8((value >>  0) & 0xFF)),
            0,
        ]
        return String(cString: bytes)
    }
}
