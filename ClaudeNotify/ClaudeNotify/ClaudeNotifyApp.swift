import SwiftUI
import AppKit

/// Owns all shared state and handles app lifecycle.
@Observable
final class AppCoordinator {
    let settings: SettingsStore
    let history: HistoryStore
    let notifications: NotificationManager
    let floatingNotifications: FloatingNotificationManager
    let server: HTTPServer
    let managementWindow: ManagementWindowController

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
        self.managementWindow = ManagementWindowController(coordinator: nil)

        setupCallbacks()
        startServer()

        // Wire up the management window controller
        managementWindow.setCoordinator(self)

        // The app is configured as an LSUIElement in Info.plist, so the menu
        // bar extra is created with the correct activation policy from launch.
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
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = AppCoordinator()
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(coordinator: coordinator)
    }
}

final class StatusBarController: NSObject {
    private static let panelWidth: CGFloat = 340
    private let panelState = MenuPanelState()
    private let statusItem: NSStatusItem
    private let panel: NSPanel

    init(coordinator: AppCoordinator) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        panel = StatusPanel(
            contentRect: NSRect(origin: .zero, size: Self.size(for: .main)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: "CC Tools")
                ?? NSImage(named: "MenuBarIcon")
            image?.isTemplate = true
            image?.size = NSSize(width: 18, height: 18)
            button.image = image
            button.imagePosition = .imageOnly
            button.toolTip = "CC Tools"
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        panel.contentViewController = NSHostingController(
            rootView: MenuBarView(
                coordinator: coordinator,
                panelState: panelState,
                onPageChange: { [weak self] page in
                    self?.resizePanel(for: page)
                }
            )
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                }
        )
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
    }

    @objc private func togglePopover(_ sender: Any?) {
        if panel.isVisible {
            panel.close()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }

        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let panelSize = panel.frame.size
        let screen = buttonWindow.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? buttonFrame

        var origin = NSPoint(
            x: buttonFrame.midX - panelSize.width / 2,
            y: buttonFrame.minY - panelSize.height - 8
        )
        origin.x = max(visibleFrame.minX + 8, min(origin.x, visibleFrame.maxX - panelSize.width - 8))
        if origin.y < visibleFrame.minY {
            origin.y = buttonFrame.maxY + 8
        }

        panel.setFrameOrigin(origin)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func resizePanel(for page: MenuPage) {
        let newSize = Self.size(for: page)
        if panel.isVisible {
            let frame = panel.frame
            panel.setFrame(
                NSRect(
                    x: frame.minX,
                    y: frame.maxY - newSize.height,
                    width: newSize.width,
                    height: newSize.height
                ),
                display: true,
                animate: false
            )
        } else {
            panel.setContentSize(newSize)
        }
    }

    private static func size(for page: MenuPage) -> NSSize {
        switch page {
        case .main:
            return NSSize(width: panelWidth, height: 328)
        case .setup, .settings:
            return NSSize(width: panelWidth, height: 500)
        }
    }
}

private final class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@Observable
final class MenuPanelState {
    var page: MenuPage = .main

    var height: CGFloat {
        switch page {
        case .main:
            return 328
        case .setup, .settings:
            return 500
        }
    }
}
