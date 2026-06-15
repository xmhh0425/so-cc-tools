import Foundation

/// Navigation state for the menu bar dropdown
enum MenuPage {
    case main
    case setup
    case settings
}

/// The type of Claude Code hook event.
enum HookEvent: String, Codable, CaseIterable {
    case stop = "Stop"
    case notification = "Notification"
    case stopFailure = "StopFailure"

    var displayName: String {
        switch self {
        case .stop: return "任务完成"
        case .notification: return "需要输入"
        case .stopFailure: return "错误"
        }
    }

    var iconName: String {
        switch self {
        case .stop: return "checkmark.circle.fill"
        case .notification: return "bell.badge.fill"
        case .stopFailure: return "exclamationmark.triangle.fill"
        }
    }
}

/// A single notification record stored in history.
struct NotificationRecord: Codable, Identifiable {
    let id: UUID
    let event: HookEvent
    let message: String
    let project: String?
    let timestamp: Date

    init(event: HookEvent, message: String, project: String?) {
        self.id = UUID()
        self.event = event
        self.message = message
        self.project = project
        self.timestamp = Date()
    }
}
