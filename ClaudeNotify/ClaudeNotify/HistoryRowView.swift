import SwiftUI

struct HistoryRowView: View {
    let record: NotificationRecord

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.event.displayName)
                    .font(.system(size: 11, weight: .semibold))

                Text(record.message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let project = record.project {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 7))
                        Text(project)
                    }
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 8)

            Text(record.timestamp.formatted(.relative(presentation: .named)))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize()
        }
    }

    private var statusColor: Color {
        switch record.event {
        case .stop: .green
        case .notification: .orange
        case .stopFailure: .red
        case .configBroken: .orange
        }
    }
}
