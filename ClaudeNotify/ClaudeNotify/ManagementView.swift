import SwiftUI

/// Navigation pages for the management window sidebar.
enum ManagementPage: String, CaseIterable, Identifiable {
    case dashboard = "概览"
    case hooks = "Hook 管理"
    case settings = "配置修复"
    case notifications = "通知"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .hooks: return "point.3.connected.trianglepath.dotted"
        case .settings: return "wrench.and.screwdriver"
        case .notifications: return "bell.badge"
        }
    }
}

/// Root view for the management window: sidebar + content area.
struct ManagementView: View {
    let coordinator: AppCoordinator
    @State private var selectedPage: ManagementPage = .dashboard
    @State private var settingsManager = SettingsManager()

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
                    DashboardView(coordinator: coordinator, settingsManager: settingsManager)
                case .hooks:
                    HookManagerView(coordinator: coordinator, settingsManager: settingsManager)
                case .settings:
                    SettingsEditorView(settingsManager: settingsManager)
                case .notifications:
                    NotificationHistoryView(coordinator: coordinator)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
