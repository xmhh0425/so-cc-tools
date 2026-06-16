import SwiftUI

struct FloatingNotificationView: View {
    let viewModel: FloatingNotificationViewModel

    @Environment(HoverState.self) private var hoverState

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .shadow(color: statusColor.opacity(0.35), radius: 4, x: 0, y: 0)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 0) {
                Text(viewModel.event.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 7)

                Text(viewModel.message)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.white)
                    .lineSpacing(2)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if let project = viewModel.project {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 8))
                        Text(project)
                    }
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.57))
                    .lineLimit(1)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(.white.opacity(0.08))
                            .frame(height: 0.5)
                    }
                    .padding(.top, 9)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.black.opacity(0.84))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(hoverState.isHovering ? 0.15 : 0.08), lineWidth: 0.5)
        )
        .overlay(alignment: .topLeading) {
            if hoverState.isHovering {
                ZStack {
                    Circle()
                        .fill(.white.opacity(hoverState.isHoveringClose ? 1.0 : 0.9))
                        .shadow(
                            color: .black.opacity(hoverState.isHoveringClose ? 0.28 : 0.18),
                            radius: hoverState.isHoveringClose ? 7 : 4,
                            x: 0,
                            y: hoverState.isHoveringClose ? 2 : 1
                        )

                    Image(systemName: "xmark")
                        .font(.system(size: hoverState.isHoveringClose ? 17 : 16, weight: .semibold))
                        .foregroundStyle(.black.opacity(hoverState.isHoveringClose ? 0.82 : 0.68))
                }
                .frame(width: 34, height: 34)
                .contentShape(Circle())
                .allowsHitTesting(false)
                .scaleEffect(hoverState.isHoveringClose ? 1.08 : 1.0)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
                .animation(.easeOut(duration: 0.10), value: hoverState.isHoveringClose)
                .padding(8)
            }
        }
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
