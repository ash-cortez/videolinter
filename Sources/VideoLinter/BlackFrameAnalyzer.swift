import Foundation
import AVFoundation
import CoreGraphics

// MARK: - Black frame detection via sampled thumbnails

enum BlackFrameAnalyzer {

    /// Luminance threshold below which a frame is considered "black" (0–1 scale, ~4%)
    private static let blackThreshold: Double = 0.04

    /// Minimum duration of a sustained black section to flag (seconds)
    private static let minimumBlackDuration: Double = 2.0

    /// Interval between sample frames (seconds)
    private static let sampleInterval: Double = 0.5

    /// Thumbnail resolution (small enough for fast pixel analysis)
    private static let thumbnailSize = CGSize(width: 64, height: 36)

    // MARK: Public

    static func detectBlackFrames(
        asset: AVAsset,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> CheckResult {

        let duration = try await asset.load(.duration).seconds
        guard duration > 0 else {
            return pass("Video duration is zero — skipped")
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = CMTime(seconds: sampleInterval / 2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter  = CMTime(seconds: sampleInterval / 2, preferredTimescale: 600)
        generator.maximumSize = thumbnailSize
        generator.appliesPreferredTrackTransform = true

        let sampleTimes = stride(from: 0.0, to: duration, by: sampleInterval).map { $0 }
        let total = sampleTimes.count

        var blackSections: [(start: TimeInterval, end: TimeInterval)] = []
        var blackStart: TimeInterval? = nil
        var lastBlackTime: TimeInterval = 0

        for (index, time) in sampleTimes.enumerated() {
            try Task.checkCancellation()

            let cmTime = CMTime(seconds: time, preferredTimescale: 600)

            // copyCGImage is synchronous but runs off-main in a Task
            if let cgImage = try? generator.copyCGImage(at: cmTime, actualTime: nil),
               averageLuminance(cgImage) < blackThreshold {
                if blackStart == nil { blackStart = time }
                lastBlackTime = time + sampleInterval   // estimate end
            } else {
                if let start = blackStart {
                    let sectionDuration = lastBlackTime - start
                    if sectionDuration >= minimumBlackDuration {
                        blackSections.append((start: start, end: lastBlackTime))
                    }
                    blackStart = nil
                }
            }

            onProgress(Double(index + 1) / Double(total))
        }

        // Trailing black section reaching end of file
        if let start = blackStart {
            let sectionDuration = min(lastBlackTime, duration) - start
            if sectionDuration >= minimumBlackDuration {
                blackSections.append((start: start, end: min(lastBlackTime, duration)))
            }
        }

        if blackSections.isEmpty {
            return pass("No sustained black frames detected")
        }

        let detail = blackSections.map { section in
            "Black frames at \(TimeFormatter.formatRange(start: section.start, end: section.end))"
        }.joined(separator: "\n")

        let count = blackSections.count
        return CheckResult(
            checkName: "Black Frames",
            status: .fail,
            summary: "\(count) sustained black frame section\(count == 1 ? "" : "s") detected",
            detail: detail
        )
    }

    // MARK: - Private helpers

    private static func pass(_ summary: String) -> CheckResult {
        CheckResult(checkName: "Black Frames", status: .pass, summary: summary, detail: nil)
    }

    /// Average luminance of a CGImage (0 = black, 1 = white).
    private static func averageLuminance(_ cgImage: CGImage) -> Double {
        let width  = cgImage.width
        let height = cgImage.height
        let pixelCount = width * height
        guard pixelCount > 0 else { return 0 }

        // Render into an 8-bit grayscale context for fast luminance sampling
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 0 }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return 0 }
        let bytes = data.bindMemory(to: UInt8.self, capacity: pixelCount)

        var sum: Int = 0
        for i in 0..<pixelCount {
            sum += Int(bytes[i])
        }
        return Double(sum) / (Double(pixelCount) * 255.0)
    }
}
