import SwiftUI

/// Owns all shared state and handles app lifecycle.
@Observable
final class AppCoordinator {
    let settings: SettingsStore
    let history: HistoryStore
    let notifications: NotificationManager
    let floatingNotifications: FloatingNotificationManager
    let server: HTTPServer

    init() {
        let s = SettingsStore()
        let h = HistoryStore()
        let n = NotificationManager()
        let fn = FloatingNotificationManager()
        let port = UInt16(s.port > 0 ? s.port : 18765)
        let srv = HTTPServer(port: port)

        self.settings = s
        self.history = h
        self.notifications = n
        self.floatingNotifications = fn
        self.server = srv

        setupCallbacks()
        startServer()

        // Hide Dock icon.  Deferred to avoid crash during SwiftUI app init.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func setupCallbacks() {
        server.onHookReceived = { [weak self] event, payload in
            guard let self else { return }

            // Extract message: prefer payload.message, fallback to transcript
            let message: String
            if let msg = payload.message, !msg.isEmpty {
                message = msg
            } else if event == .stop, let transcriptMsg = TranscriptReader.lastUserMessage(from: payload.transcript_path) {
                message = transcriptMsg
            } else {
                switch event {
                case .stop:        message = "Claude 完成了任务"
                case .notification: message = "Claude 等待你的输入"
                case .stopFailure: message = "发生了 API 错误"
                }
            }

            let project = Self.resolveProjectName(from: payload.cwd)

            history.add(event: event, message: message, project: project)

            if settings.floatingNotificationEnabled {
                floatingNotifications.show(event: event, message: message, project: project)
            }

            if settings.systemNotificationEnabled {
                notifications.postNotification(
                    event: event,
                    message: message,
                    soundEnabled: settings.soundEnabled
                )
            }
        }
    }

    private func startServer() {
        server.start()
        notifications.requestAuthorization()

        ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .idleDisplaySleepDisabled],
            reason: "Listening for Claude Code hooks"
        )
    }

    /// Walk up from cwd to find the project root (containing .git or .claude).
    static func resolveProjectName(from cwd: String?) -> String? {
        guard let cwd else { return nil }
        var dir = URL(fileURLWithPath: cwd)
        let fm = FileManager.default

        // Check cwd itself first
        if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) ||
           fm.fileExists(atPath: dir.appendingPathComponent(".claude").path) {
            return dir.lastPathComponent
        }

        // Walk up to 5 levels
        for _ in 1...5 {
            dir = dir.deletingLastPathComponent()
            if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) ||
               fm.fileExists(atPath: dir.appendingPathComponent(".claude").path) {
                return dir.lastPathComponent
            }
            // Stop at home directory
            if dir.path == FileManager.default.homeDirectoryForCurrentUser.path {
                break
            }
        }

        // Fallback: return the original cwd's last component
        return URL(fileURLWithPath: cwd).lastPathComponent
    }
}

@main
struct ClaudeNotifyApp: App {
    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(coordinator: coordinator)
        } label: {
            Image(systemName: "bell.fill")
        }
        .menuBarExtraStyle(.window)
        .defaultSize(width: 340, height: 500)
    }
}
