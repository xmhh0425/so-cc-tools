import SwiftUI

/// Navigation pages for the management window sidebar.
enum ManagementPage: String, CaseIterable, Identifiable {
    case dashboard = "概览"
    case config = "配置"
    case notifications = "通知"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .config: return "gearshape.2"
        case .notifications: return "bell.badge"
        }
    }
}

/// Root view for the management window: sidebar + content area.
struct ManagementView: View {
    let coordinator: AppCoordinator
    @State var selectedPage: ManagementPage = .dashboard

    var body: some View {
        NavigationSplitView {
            List(ManagementPage.allCases, selection: $selectedPage) { page in
                Label(page.rawValue, systemImage: page.icon)
                    .tag(page)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            Group {
                switch selectedPage {
                case .dashboard:
                    DashboardView(coordinator: coordinator, settingsManager: coordinator.settingsManager)
                case .config:
                    ConfigView(coordinator: coordinator, settingsManager: coordinator.settingsManager)
                case .notifications:
                    NotificationHistoryView(coordinator: coordinator)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
