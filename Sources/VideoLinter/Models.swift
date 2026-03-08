import Foundation
import SwiftUI

// MARK: - Check Status

enum CheckStatus {
    case pass, fail, warning, skipped

    var color: Color {
        switch self {
        case .pass:    return Color(red: 0.18, green: 0.72, blue: 0.38)
        case .fail:    return Color(red: 0.90, green: 0.25, blue: 0.25)
        case .warning: return Color(red: 0.95, green: 0.65, blue: 0.12)
        case .skipped: return Color.secondary
        }
    }

    var icon: String {
        switch self {
        case .pass:    return "checkmark.circle.fill"
        case .fail:    return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .skipped: return "minus.circle"
        }
    }

    var label: String {
        switch self {
        case .pass:    return "Pass"
        case .fail:    return "Fail"
        case .warning: return "Warn"
        case .skipped: return "Skip"
        }
    }
}

// MARK: - Check Result

struct CheckResult: Identifiable {
    let id = UUID()
    let checkName: String
    let status: CheckStatus
    let summary: String
    /// Optional multi-line detail (e.g., timestamps of black frames or silence gaps)
    let detail: String?
}

// MARK: - Analysis State

enum AnalysisState {
    case idle
    case analyzing(progress: Double, step: String)
    case complete
    case failed(String)
}

// MARK: - Video Report

@MainActor
final class VideoReport: ObservableObject, Identifiable, @unchecked Sendable {
    let id = UUID()
    let url: URL

    @Published var state: AnalysisState = .idle
    @Published var checks: [CheckResult] = []
    @Published var isExpanded: Bool = true

    var filename: String { url.lastPathComponent }

    var overallStatus: CheckStatus {
        guard !checks.isEmpty else { return .warning }
        if checks.contains(where: { $0.status == .fail })    { return .fail }
        if checks.contains(where: { $0.status == .warning }) { return .warning }
        return .pass
    }

    var progressValue: Double {
        if case .analyzing(let p, _) = state { return p }
        return 0
    }

    var progressStep: String {
        if case .analyzing(_, let s) = state { return s }
        return ""
    }

    var isAnalyzing: Bool {
        if case .analyzing = state { return true }
        return false
    }

    var isComplete: Bool {
        if case .complete = state { return true }
        return false
    }

    init(url: URL) {
        self.url = url
    }
}
