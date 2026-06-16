import SwiftUI

/// Hook management page: view, install, uninstall all hooks.
struct HookManagerView: View {
    let coordinator: AppCoordinator
    let settingsManager: SettingsManager

    @State private var hooks: [HookConfig] = []
    @State private var statusLine: StatusLineConfig?
    @State private var statusLineEnabled = false
    @State private var statusLineInterval = 5
    @State private var showSaveConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                notificationHooksSection
                commandHooksSection
                statusLineSection
            }
            .padding(24)
        }
        .onAppear { refreshData() }
        .overlay(alignment: .bottom) {
            if showSaveConfirmation {
                Text("已保存")
                    .font(.system(size: 12))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.title2)
                .foregroundStyle(.blue)
            Text("Hook 管理")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            Button("全部重新安装") {
                reinstallAll()
            }
            .controlSize(.small)
        }
    }

    // MARK: - Notification Hooks (HTTP type)

    private var notificationHooksSection: some View {
        GroupBox("通知 Hook（HTTP）") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(notificationEvents, id: \.self) { event in
                    let hookPath = hookPathForEvent(event)
                    let isInstalled = hooks.contains {
                        $0.event == event && $0.type == .http && $0.target.contains("/hook/")
                    }
                    hookRow(
                        event: event,
                        eventLabel: eventDisplayName(event),
                        target: "http://127.0.0.1:\(coordinator.settings.port)/hook/\(hookPath)",
                        type: "HTTP",
                        isInstalled: isInstalled
                    ) {
                        toggleNotificationHook(event: event, hookPath: hookPath, installed: isInstalled)
                    }
                    if event != notificationEvents.last {
                        Divider().padding(.horizontal, -8)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Command Hooks

    private var commandHooksSection: some View {
        GroupBox("Skill 追踪 Hook（command）") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(commandHookConfigs, id: \.event) { config in
                    let isInstalled = hooks.contains {
                        $0.event == config.event && $0.type == .command && $0.target.contains(config.dedupKey)
                    }
                    hookRow(
                        event: config.event,
                        eventLabel: config.label,
                        target: config.target,
                        type: "command",
                        isInstalled: isInstalled
                    ) {
                        toggleCommandHook(config: config, installed: isInstalled)
                    }
                    if config.event != commandHookConfigs.last?.event {
                        Divider().padding(.horizontal, -8)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - StatusLine Section

    private var statusLineSection: some View {
        GroupBox("状态栏（statusLine）") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("启用状态栏", isOn: $statusLineEnabled)
                    .font(.system(size: 12))
                    .onChange(of: statusLineEnabled) { _, _ in saveStatusLine() }

                if statusLineEnabled {
                    HStack {
                        Text("刷新间隔")
                            .font(.system(size: 12))
                        Spacer()
                        Stepper("\(statusLineInterval) 秒", value: $statusLineInterval, in: 1...30)
                            .font(.system(size: 12))
                            .onChange(of: statusLineInterval) { _, _ in saveStatusLine() }
                    }

                    Text("命令：\(statusLine?.command ?? "未配置")")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                Text("状态栏通过 statusLine 字段配置，需终端支持。修改后重开会话生效。")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Hook Row Component

    private func hookRow(event: String, eventLabel: String, target: String, type: String, isInstalled: Bool, toggle: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isInstalled ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(isInstalled ? .green : .secondary)
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 2) {
                Text(eventLabel)
                    .font(.system(size: 12, weight: .medium))
                Text(target)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Text(type)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))

            Button(isInstalled ? "卸载" : "安装") {
                toggle()
            }
            .controlSize(.small)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }

    // MARK: - Data

    private var notificationEvents: [String] {
        ["Stop", "Notification", "StopFailure"]
    }

    private struct CommandHookDef {
        let event: String
        let label: String
        let matcher: String
        let target: String
        let dedupKey: String
    }

    private var commandHookConfigs: [CommandHookDef] {
        // Paths are derived from the repo; the settings.json stores absolute paths.
        // We match by filename for dedup, same as fix-settings.sh.
        [
            CommandHookDef(
                event: "PreToolUse",
                label: "PreToolUse（Skill 调用追踪）",
                matcher: "Skill",
                target: "hook-pre-skill.sh",
                dedupKey: "hook-pre-skill"
            ),
            CommandHookDef(
                event: "UserPromptExpansion",
                label: "UserPromptExpansion（斜杠命令追踪）",
                matcher: ".*",
                target: "hook-skill-tracker.sh",
                dedupKey: "hook-skill-tracker"
            ),
        ]
    }

    // MARK: - Actions

    private func toggleNotificationHook(event: String, hookPath: String, installed: Bool) {
        do {
            if installed {
                try settingsManager.uninstallHook(event: event, targetContains: "/hook/")
            } else {
                let config = HookConfig(
                    event: event,
                    matcher: "",
                    type: .http,
                    target: "http://127.0.0.1:\(coordinator.settings.port)/hook/\(hookPath)"
                )
                try settingsManager.ensureHook(config)
            }
            refreshData()
        } catch {
            print("Error: \(error)")
        }
    }

    private func toggleCommandHook(config: CommandHookDef, installed: Bool) {
        do {
            if installed {
                try settingsManager.uninstallHook(event: config.event, targetContains: config.dedupKey)
            } else {
                // We don't know the absolute repo path here, so we use a placeholder
                // that the user will need to adjust, or we can resolve it.
                // For now, let's try to resolve from the settings file itself.
                let existingTarget = hooks.first { $0.event == config.event && $0.type == .command }?.target
                let target: String
                if let existingTarget {
                    target = existingTarget
                } else {
                    // Best effort: look for the so-cc-tools repo
                    let home = FileManager.default.homeDirectoryForCurrentUser.path
                    target = "bash \(home)/AI/so-cc-tools/statusline/\(config.target)"
                }

                let hookConfig = HookConfig(
                    event: config.event,
                    matcher: config.matcher,
                    type: .command,
                    target: target
                )
                try settingsManager.ensureHook(hookConfig)
            }
            refreshData()
        } catch {
            print("Error: \(error)")
        }
    }

    private func reinstallAll() {
        try? settingsManager.backupSettings()

        // Reinstall notification hooks
        for event in notificationEvents {
            let hookPath = hookPathForEvent(event)
            let config = HookConfig(
                event: event,
                matcher: "",
                type: .http,
                target: "http://127.0.0.1:\(coordinator.settings.port)/hook/\(hookPath)"
            )
            try? settingsManager.ensureHook(config)
        }

        // Reinstall command hooks (preserve existing paths)
        for def in commandHookConfigs {
            let existingTarget = hooks.first { $0.event == def.event && $0.type == .command }?.target
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let target = existingTarget ?? "bash \(home)/AI/so-cc-tools/statusline/\(def.target)"
            let config = HookConfig(event: def.event, matcher: def.matcher, type: .command, target: target)
            try? settingsManager.ensureHook(config)
        }

        refreshData()
        flashConfirmation()
    }

    private func saveStatusLine() {
        if statusLineEnabled {
            let config = StatusLineConfig(
                enabled: true,
                command: statusLine?.command ?? "bash ~/AI/so-cc-tools/statusline/statusline.sh",
                refreshInterval: statusLineInterval
            )
            try? settingsManager.setStatusLine(config)
        } else {
            try? settingsManager.setStatusLine(nil)
        }
        flashConfirmation()
    }

    private func refreshData() {
        hooks = settingsManager.readAllHooks()
        statusLine = settingsManager.readStatusLine()
        statusLineEnabled = statusLine != nil
        statusLineInterval = statusLine?.refreshInterval ?? 5
    }

    private func flashConfirmation() {
        showSaveConfirmation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showSaveConfirmation = false
        }
    }

    // MARK: - Event display helpers

    private func eventDisplayName(_ event: String) -> String {
        switch event {
        case "Stop": return "Stop（任务完成）"
        case "Notification": return "Notification（等待输入）"
        case "StopFailure": return "StopFailure（API 错误）"
        default: return event
        }
    }

    private func hookPathForEvent(_ event: String) -> String {
        switch event {
        case "Stop": return "stop"
        case "Notification": return "notification"
        case "StopFailure": return "stopfailure"
        default: return event.lowercased()
        }
    }
}
