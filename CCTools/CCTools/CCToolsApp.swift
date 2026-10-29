import SwiftUI
import AppKit
import os.log

/// Owns all shared state and handles app lifecycle.
@Observable
final class AppCoordinator {
    let settings: SettingsStore
    let history: HistoryStore
    let notifications: NotificationManager
    let floatingNotifications: FloatingNotificationManager
    let server: HTTPServer
    let managementWindow: ManagementWindowController
    let settingsManager: SettingsManager
    /// Stop 通知的延迟确认器（见 StopNotificationDebouncer）。
    private let stopDebouncer = StopNotificationDebouncer()

    /// 一轮结束的快速检测器（见 TranscriptWatcher）。
    private let transcriptWatcher = TranscriptWatcher()

    /// beginActivity 返回的 token 必须持有，否则 activity 立即失效（App Nap / 睡眠抑制都会失效）。
    private var systemActivity: NSObjectProtocol?

    var settingsWatcher: SettingsWatcher?
    var currentHealth: ConfigHealth?
    /// Bumped whenever settings.json changes externally — ConfigView observes
    /// this and reloads its in-memory copy of the file.
    var settingsExternalChangeToken: Int = 0
    private var lastHealthySignature: String?

    init() {
        let s = SettingsStore()
        let h = HistoryStore()
        let n = NotificationManager()
        let fn = FloatingNotificationManager()
        let port = UInt16(s.port > 0 ? s.port : 18765)
        let srv = HTTPServer(port: port)
        let sm = SettingsManager()

        self.settings = s
        self.history = h
        self.notifications = n
        self.floatingNotifications = fn
        self.server = srv
        self.managementWindow = ManagementWindowController(coordinator: nil)
        self.settingsManager = sm

        setupCallbacks()
        startServer()

        managementWindow.setCoordinator(self)

        // Seed health state (don't notify for pre-existing broken state)
        let health = sm.checkHealth()
        self.currentHealth = health
        self.lastHealthySignature = health.signature

        // Start watching settings.json for drift
        let watcher = SettingsWatcher(fileURL: sm.settingsPath)
        sm.watcher = watcher
        watcher.onChange = { [weak self] in self?.handleSettingsChanged() }
        watcher.start()
        self.settingsWatcher = watcher
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
                case .configBroken: message = "配置被覆盖，Hook 或状态栏丢失"
                }
            }

            let project = Self.resolveProjectName(from: payload.cwd)

            switch event {
            case .stop:
                handleStop(payload: payload, message: message, project: project)
            case .notification:
                handleNotification(payload: payload, message: message, project: project)
            case .stopFailure, .configBroken:
                deliver(event: event, message: message, project: project)
            }
        }

        // 用户提交输入：撤销可能挂着的提醒，并开始快速检测这一轮何时结束
        server.onUserPromptSubmit = { [weak self] payload in
            guard let self, let sessionID = payload.session_id else { return }
            stopDebouncer.cancelPending(sessionID: sessionID)
            if settings.fastTurnDetectionEnabled, let path = payload.transcript_path {
                transcriptWatcher.startWatching(
                    sessionID: sessionID,
                    transcriptPath: path,
                    cwd: payload.cwd
                )
            }
        }
    }

    /// Stop 钩子每轮回复结束都会触发，这里做“延迟确认”：
    /// 后台任务还在跑就不算完成；延迟期间会话继续活动则撤销这次通知。
    private func handleStop(payload: HookPayload, message: String, project: String?) {
        let delay = settings.stopNotifyDelaySeconds
        guard delay > 0, let sessionID = payload.session_id else {
            deliver(event: .stop, message: message, project: project)
            return
        }
        if payload.hasActiveBackgroundWork { return }

        stopDebouncer.schedule(
            sessionID: sessionID,
            transcriptPath: payload.transcript_path,
            turnPromptID: payload.prompt_id,
            delay: TimeInterval(delay),
            dedupWindow: TimeInterval(settings.stopNotifyDedupSeconds)
        ) { [weak self] in
            self?.deliver(event: .stop, message: message, project: project)
        }
    }

    /// idle 提醒（“Claude is waiting for your input”）默认不弹：只在“一轮回复结束”
    /// （Stop）时提醒。开启后同一会话只保留一条：有等待确认的 Stop 时让位给 Stop
    /// 通知，刚通知过则跳过。权限请求等其他类型不受影响，照常立即通知。
    private func handleNotification(payload: HookPayload, message: String, project: String?) {
        if payload.notification_type == "idle_prompt" {
            guard settings.idleNotificationEnabled else { return }
            if let sessionID = payload.session_id,
               !stopDebouncer.shouldDeliverIdleNotification(
                   sessionID: sessionID,
                   dedupWindow: TimeInterval(settings.stopNotifyDedupSeconds)
               ) {
                return
            }
        }
        deliver(event: .notification, message: message, project: project)
    }

    /// 落盘历史 + 按设置展示浮窗 / 系统通知。
    private func deliver(event: HookEvent, message: String, project: String?) {
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

    private func startServer() {
        server.start()
        writePortFile()
        notifications.requestAuthorization()
        setupTurnWatcher()

        systemActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled, .idleDisplaySleepDisabled],
            reason: "Listening for Claude Code hooks"
        )
    }

    /// Write the active port to ~/.config/cc-tools/port so that
    /// shell hook scripts (notify-cc-tools.sh) can discover it.
    private func writePortFile() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cc-tools")
        let file = dir.appendingPathComponent("port")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try "\(settings.port)".write(to: file, atomically: true, encoding: .utf8)
        } catch {
            Logger(subsystem: "com.cc-tools", category: "Coordinator")
                .error("Failed to write port file: \(error)")
        }
    }

    /// 快速检测器的接线：前台闸门 + 结束回调（走与 Stop 相同的投递路径，并打标记去重）。
    private func setupTurnWatcher() {
        transcriptWatcher.shouldNotify = { [weak self] in
            guard let self else { return true }
            guard settings.terminalFocusSuppressesNotifications else { return true }
            return !Self.isTerminalFrontmost()
        }
        transcriptWatcher.onTurnEnded = { [weak self] sessionID, transcriptPath, cwd in
            guard let self else { return }
            let message = TranscriptReader.lastUserMessage(from: transcriptPath) ?? "Claude 完成了任务"
            let project = Self.resolveProjectName(from: cwd)
            deliver(event: .stop, message: message, project: project)
            stopDebouncer.markNotified(
                sessionID: sessionID,
                dedupWindow: TimeInterval(settings.stopNotifyDedupSeconds)
            )
            transcriptWatcher.stopWatching(sessionID: sessionID)
        }
        transcriptWatcher.start()
    }

    /// 前台是终端类应用时，认为用户就坐在那儿看输出，不再弹提醒（可在通知页关掉）。
    private static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "com.github.wez.wezterm",
        "dev.warp.Warp-Stable",
        "io.alacritty",
        "net.kovidgoyal.kitty",
        "co.zeit.hyper",
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",
    ]

    private static func isTerminalFrontmost() -> Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return terminalBundleIDs.contains(bundleID)
    }

    // MARK: - Config Drift Detection

    /// Called by SettingsWatcher when settings.json changes externally.
    private func handleSettingsChanged() {
        let health = settingsManager.checkHealth()
        let prevSignature = lastHealthySignature
        currentHealth = health
        lastHealthySignature = health.signature

        // Bump token so ConfigView reloads its editor / toggles.
        settingsExternalChangeToken &+= 1

        // Seed: first observation records state without notifying
        guard let prevSignature else { return }

        // Edge-triggered: only notify on transition (signature changed while unhealthy)
        if !health.isHealthy && prevSignature != health.signature {
            notifyConfigBroken(health: health)
        }
    }

    private func notifyConfigBroken(health: ConfigHealth) {
        let missing = health.items.filter { !$0.isPresent }.map(\.label)
        let parts = missing + (health.statusLinePresent ? [] : ["statusLine"])
        let message = "配置失效：\(parts.joined(separator: "、"))"

        if settings.floatingNotificationEnabled {
            floatingNotifications.show(event: .configBroken, message: message, project: nil)
        }
        if settings.systemNotificationEnabled {
            notifications.postNotification(
                event: .configBroken, message: message, soundEnabled: settings.soundEnabled
            )
        }
        history.add(event: .configBroken, message: message, project: nil)

        if settings.autoFixOnDrift {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.repairConfig()
            }
        }
    }

    /// One-click repair called from UI or auto-fix.
    func repairConfig() {
        settingsWatcher?.beginSelfWrite()
        defer { settingsWatcher?.endSelfWrite() }
        do {
            try settingsManager.repairManaged()
        } catch {
            Logger(subsystem: "com.cc-tools", category: "Coordinator")
                .error("repairManaged failed: \(error)")
        }
        let health = settingsManager.checkHealth()
        currentHealth = health
        lastHealthySignature = health.signature
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
struct CCToolsApp: App {
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
    private static let panelWidth = MenuPanelLayout.panelWidth
    private let statusItem: NSStatusItem
    private let panel: NSPanel
    private var panelFocusAutoCloser: PanelFocusAutoCloser?

    init(coordinator: AppCoordinator) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        panel = StatusPanel(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(width: MenuPanelLayout.panelWidth, height: MenuPanelLayout.panelMinHeight)
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        super.init()

        if let button = statusItem.button {
            let image = NSImage(named: "MenuBarIcon")
                ?? NSImage(systemSymbolName: "bell.fill", accessibilityDescription: "CC Tools")
            image?.isTemplate = true
            image?.size = NSSize(width: 18, height: 18)
            button.image = image
            button.imagePosition = .imageOnly
            button.toolTip = "CC Tools"
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let hostingView = NSHostingView(
            rootView: MenuBarView(
                coordinator: coordinator
            )
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                }
        )
        panel.contentView = hostingView
        panel.minSize = NSSize(width: MenuPanelLayout.panelWidth, height: MenuPanelLayout.panelMinHeight)
        panel.maxSize = NSSize(width: MenuPanelLayout.panelWidth, height: MenuPanelLayout.panelMaxHeight)
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
        panelFocusAutoCloser = PanelFocusAutoCloser(panel: panel) { [weak self] in
            self?.isPointerInsideStatusButton() ?? false
        }

        // Resize panel when SwiftUI content changes
        hostingView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: hostingView,
            queue: .main
        ) { [weak self] _ in
            self?.resizePanelToContent()
        }
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

    private func isPointerInsideStatusButton() -> Bool {
        guard let button = statusItem.button, let buttonWindow = button.window else { return false }

        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        return buttonFrame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation)
    }

    /// Resize the panel to fit its SwiftUI content, pinned below the menu bar.
    private func resizePanelToContent() {
        guard let contentView = panel.contentView else { return }
        let fittingHeight = contentView.fittingSize.height
        let clampedHeight = max(panel.minSize.height, min(fittingHeight, panel.maxSize.height))
        let width = Self.panelWidth

        guard abs(panel.frame.height - clampedHeight) > 1 else { return }

        let topY = panel.frame.maxY
        panel.setFrame(
            NSRect(x: panel.frame.origin.x, y: topY - clampedHeight, width: width, height: clampedHeight),
            display: true,
            animate: false
        )
    }
}

private final class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
