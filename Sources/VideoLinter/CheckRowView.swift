import SwiftUI

struct CheckRowView: View {
    let result: CheckResult
    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: result.status.icon)
                    .foregroundColor(result.status.color)
                    .frame(width: 16)

                Text(result.checkName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)

                Spacer()

                Text(result.summary)
                    .font(.system(size: 12))
                    .foregroundColor(result.status == .pass ? .secondary : result.status.color)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)

                if result.detail != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showDetail.toggle()
                        }
                    } label: {
                        Image(systemName: showDetail ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 16)
                }
            }

            if showDetail, let detail = result.detail {
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.leading, 24)
                    .padding(.top, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }
}
