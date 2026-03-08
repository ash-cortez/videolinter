import SwiftUI

struct FileResultView: View {
    @ObservedObject var report: VideoReport
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────────────────────
            HStack(spacing: 10) {
                // Expand/collapse toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        report.isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: report.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 14)
                }
                .buttonStyle(.plain)

                // File icon + name
                Image(systemName: "film")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))

                Text(report.filename)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                // State indicator
                switch report.state {
                case .idle:
                    EmptyView()

                case .analyzing(_, let step):
                    Text(step)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)

                case .complete:
                    OverallBadgeView(status: report.overallStatus)

                case .failed(let msg):
                    Text("Error")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.red)
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                }

                // Remove button
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(0.6)
                .help("Remove file")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // ── Progress bar (while analysing) ────────────────────────────────
            if report.isAnalyzing {
                ProgressView(value: report.progressValue)
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }

            // ── Expanded check list ───────────────────────────────────────────
            if report.isExpanded {
                if case .failed(let msg) = report.state {
                    Text(msg)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                } else if !report.checks.isEmpty {
                    Divider()
                        .padding(.horizontal, 14)

                    VStack(spacing: 0) {
                        ForEach(Array(report.checks.enumerated()), id: \.element.id) { index, check in
                            CheckRowView(result: check)

                            if index < report.checks.count - 1 {
                                Divider()
                                    .padding(.leading, 36)
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var borderColor: Color {
        switch report.state {
        case .complete:
            switch report.overallStatus {
            case .pass:    return Color(red: 0.18, green: 0.72, blue: 0.38).opacity(0.4)
            case .fail:    return Color(red: 0.90, green: 0.25, blue: 0.25).opacity(0.4)
            case .warning: return Color(red: 0.95, green: 0.65, blue: 0.12).opacity(0.4)
            case .skipped: return Color.secondary.opacity(0.3)
            }
        default:
            return Color(NSColor.separatorColor)
        }
    }
}

// MARK: - Overall badge

private struct OverallBadgeView: View {
    let status: CheckStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.icon)
                .font(.system(size: 11, weight: .semibold))
            Text(status.label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
        }
        .foregroundColor(status.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(status.color.opacity(0.12))
        )
        .overlay(
            Capsule()
                .stroke(status.color.opacity(0.3), lineWidth: 1)
        )
    }
}
