import SwiftUI

/// Vertical stack of floating notification banners, newest on top.
struct NotificationStackView: View {
    let viewModel: NotificationStackViewModel

    var body: some View {
        VStack(spacing: 8) {
            ForEach(viewModel.notifications) { notification in
                FloatingNotificationView(viewModel: notification) {
                    viewModel.dismiss(notification)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 8)
        .padding(.trailing, 20)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.notifications.map(\.id))
    }
}
