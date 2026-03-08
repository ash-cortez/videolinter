import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var vm = AppViewModel()
    @State private var isFilePickerPresented = false

    var body: some View {
        VStack(spacing: 0) {
            if vm.reports.isEmpty {
                // ── Empty state: full drop zone ────────────────────────────────
                DropZoneView(compact: false, onDrop: vm.handleDrop)
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // ── File list ──────────────────────────────────────────────────
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(vm.reports) { report in
                            FileResultView(report: report) {
                                vm.removeReport(report)
                            }
                        }

                        DropZoneView(compact: true, onDrop: vm.handleDrop)
                            .padding(.top, 2)
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.accentColor)
                    Text("Video Linter")
                        .font(.system(size: 13, weight: .semibold))
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if !vm.reports.isEmpty {
                    // Summary counts
                    let failCount = vm.reports.filter { $0.overallStatus == .fail }.count
                    let passCount = vm.reports.filter { $0.overallStatus == .pass }.count

                    HStack(spacing: 8) {
                        if passCount > 0 {
                            Label("\(passCount) pass", systemImage: "checkmark.circle.fill")
                                .foregroundColor(Color(red: 0.18, green: 0.72, blue: 0.38))
                                .font(.system(size: 12, weight: .medium))
                        }
                        if failCount > 0 {
                            Label("\(failCount) fail", systemImage: "xmark.circle.fill")
                                .foregroundColor(Color(red: 0.90, green: 0.25, blue: 0.25))
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .padding(.trailing, 4)

                    Button {
                        vm.clearAll()
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                    .help("Remove all files")
                }

                Button {
                    isFilePickerPresented = true
                } label: {
                    Label("Add Files", systemImage: "plus")
                }
                .help("Add video files")
                .keyboardShortcut("o", modifiers: .command)
            }
        }
        .fileImporter(
            isPresented: $isFilePickerPresented,
            allowedContentTypes: [
                UTType(filenameExtension: "mp4") ?? .movie,
                UTType(filenameExtension: "mov") ?? .movie,
                UTType(filenameExtension: "m4v") ?? .movie,
            ],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                // Attempt security-scoped access (required in sandboxed builds; no-op otherwise)
                urls.forEach { _ = $0.startAccessingSecurityScopedResource() }
                vm.addFiles(urls)
            }
        }
        // Also accept drag & drop onto the whole window
        .onDrop(of: [UTType.fileURL, UTType.url], isTargeted: nil, perform: vm.handleDrop)
    }
}
