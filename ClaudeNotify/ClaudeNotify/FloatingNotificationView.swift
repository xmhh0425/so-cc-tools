import SwiftUI

struct FloatingNotificationView: View {
    let viewModel: FloatingNotificationViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                // Line 1: Event type
                Text(viewModel.event.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))

                // Line 2: Message content (main focus)
                Text(viewModel.message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                // Line 3: Project name
                if let project = viewModel.project {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 8))
                        Text(project)
                    }
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 6)
    }

    private var statusColor: Color {
        switch viewModel.event {
        case .stop: .green
        case .notification: .orange
        case .stopFailure: .red
        }
    }
}
