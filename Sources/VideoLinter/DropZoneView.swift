import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    let compact: Bool
    let onDrop: ([NSItemProvider]) -> Bool

    @State private var isDragging = false

    init(compact: Bool = false, onDrop: @escaping ([NSItemProvider]) -> Bool) {
        self.compact  = compact
        self.onDrop   = onDrop
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: compact ? 10 : 16, style: .continuous)
                .fill(isDragging
                      ? Color.accentColor.opacity(0.08)
                      : Color(NSColor.controlBackgroundColor).opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: compact ? 10 : 16, style: .continuous)
                        .strokeBorder(
                            isDragging ? Color.accentColor : Color(NSColor.separatorColor),
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                        )
                )

            if compact {
                compactContent
            } else {
                fullContent
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isDragging)
        .onDrop(of: [UTType.fileURL, UTType.url], isTargeted: $isDragging, perform: onDrop)
    }

    // MARK: - Full drop zone (shown when no files loaded)

    private var fullContent: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(isDragging ? 0.15 : 0.08))
                    .frame(width: 72, height: 72)
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 34, weight: .light))
                    .foregroundColor(.accentColor)
            }

            VStack(spacing: 6) {
                Text("Drop video files here")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)

                Text("or click the button in the toolbar to browse")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Text("MP4 · MOV · M4V")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(40)
    }

    // MARK: - Compact drop zone (shown below the file list)

    private var compactContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            Text("Drop more files here")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 12)
    }
}
