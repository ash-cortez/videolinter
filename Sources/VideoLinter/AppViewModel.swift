import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppViewModel: ObservableObject {
    @Published var reports: [VideoReport] = []

    private let supportedTypes: Set<String> = ["mp4", "mov", "m4v"]

    func addFiles(_ urls: [URL]) {
        let newURLs = urls.filter { url in
            supportedTypes.contains(url.pathExtension.lowercased()) &&
            !reports.contains(where: { $0.url == url })
        }

        let newReports = newURLs.map { VideoReport(url: $0) }
        reports.append(contentsOf: newReports)

        for report in newReports {
            Task { await startAnalysis(report) }
        }
    }

    func removeReport(_ report: VideoReport) {
        reports.removeAll { $0.id == report.id }
    }

    func clearAll() {
        reports.removeAll()
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        var loaded = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    Task { @MainActor in
                        self.addFiles([url])
                    }
                }
                loaded = true
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                    guard let url = item as? URL else { return }
                    Task { @MainActor in
                        self.addFiles([url])
                    }
                }
                loaded = true
            }
        }
        return loaded
    }

    // MARK: - Private

    private func startAnalysis(_ report: VideoReport) async {
        report.state = .analyzing(progress: 0, step: "Loading…")
        do {
            let checks = try await VideoAnalyzer.analyze(url: report.url) { progress, step in
                Task { @MainActor in
                    report.state = .analyzing(progress: progress, step: step)
                }
            }
            report.checks = checks
            report.state = .complete
        } catch {
            report.state = .failed(error.localizedDescription)
        }
    }
}
