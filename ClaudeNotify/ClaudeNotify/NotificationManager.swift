import Foundation
import UserNotifications
import os.log

/// Manages macOS notification permissions and posting.
@Observable
final class NotificationManager {
    private(set) var isAuthorized = false
    private let logger = Logger(subsystem: "com.claude-notify", category: "Notification")

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.isAuthorized = granted
                if let error {
                    self?.logger.error("Notification auth error: \(error)")
                }
            }
        }

        // Check current status
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    func postNotification(event: HookEvent, message: String, soundEnabled: Bool) {
        let content = UNMutableNotificationContent()

        switch event {
        case .stop:
            content.title = "Claude Code · 任务完成"
            content.body = message
            if soundEnabled {
                content.sound = UNNotificationSound(named: UNNotificationSoundName("Glass.aiff"))
            }
        case .notification:
            content.title = "Claude Code · 等待输入"
            content.body = message
            if soundEnabled {
                content.sound = UNNotificationSound.default
            }
        case .stopFailure:
            content.title = "Claude Code · 发生错误"
            content.body = message
            if soundEnabled {
                content.sound = UNNotificationSound.default
            }
        case .configBroken:
            content.title = "CC Tools · 配置异常"
            content.body = message
            if soundEnabled {
                content.sound = UNNotificationSound.default
            }
        }

        content.categoryIdentifier = "claude-code"

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error {
                self?.logger.error("Failed to post notification: \(error)")
            }
        }
    }
}
