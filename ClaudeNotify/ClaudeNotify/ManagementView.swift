import SwiftUI

/// Navigation pages for the management window sidebar.
enum ManagementPage: String, CaseIterable, Identifiable {
    case config = "配置"
    case notifications = "通知"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .config: return "gearshape.2"
        case .notifications: return "bell.badge"
        }
    }
}

/// Root view for the management window: sidebar + content area.
struct ManagementView: View {
    let coordinator: AppCoordinator
    @State var selectedPage: ManagementPage = .config

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
                case .config:
                    ConfigView(coordinator: coordinator, settingsManager: coordinator.settingsManager)
                case .notifications:
                    NotificationHistoryView(coordinator: coordinator)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbarBackground(.visible, for: .windowToolbar)
            .toolbarBackground(.regularMaterial, for: .windowToolbar)
        }
    }
}
