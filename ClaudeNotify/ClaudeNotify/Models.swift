import Foundation

/// The type of Claude Code hook event.
enum HookEvent: String, Codable, CaseIterable {
    case stop = "Stop"
    case notification = "Notification"
    case stopFailure = "StopFailure"
    case configBroken = "ConfigBroken"

    var displayName: String {
        switch self {
        case .stop: return "任务完成"
        case .notification: return "需要输入"
        case .stopFailure: return "错误"
        case .configBroken: return "配置异常"
        }
    }

    var iconName: String {
        switch self {
        case .stop: return "checkmark.circle.fill"
        case .notification: return "bell.badge.fill"
        case .stopFailure: return "exclamationmark.triangle.fill"
        case .configBroken: return "exclamationmark.shield.fill"
        }
    }

    /// Returns the UserDefaults key for this event's display duration setting.
    var durationKey: String {
        switch self {
        case .stop: return "stopDuration"
        case .notification: return "notificationDuration"
        case .stopFailure: return "stopFailureDuration"
        case .configBroken: return "configBrokenDuration"
        }
    }

    /// Whether this event represents an installable Claude Code hook.
    var isInstallable: Bool {
        switch self {
        case .stop, .notification, .stopFailure: return true
        case .configBroken: return false
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

extension Bundle {
    /// 统一的版本号展示：v{marketing} ({build})，如 "v1.1.0 (2)"。
    /// 概览页 / 菜单栏速览面板 / 设置页共用，从 bundle 读取，避免硬编码导致多处不一致。
    var versionDisplay: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(short) (\(build))"
    }
}
