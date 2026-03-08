import Foundation

enum TimeFormatter {
    /// Format a TimeInterval as HH:MM:SS or MM:SS
    static func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "??:??" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    /// Format a closed range as "HH:MM:SS – HH:MM:SS"
    static func formatRange(start: TimeInterval, end: TimeInterval) -> String {
        "\(format(start)) – \(format(end))"
    }
}
