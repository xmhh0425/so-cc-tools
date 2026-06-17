import SwiftUI

/// Unified configuration page: grouped feature toggles + editable settings.json.
struct ConfigView: View {
    let coordinator: AppCoordinator
    let settingsManager: SettingsManager

    @State private var hooks: [HookConfig] = []
    @State private var statusLine: StatusLineConfig?
    @State private var statusLineEnabled = false
    @State private var statusLineInterval = 5
    @State private var editorContent: String = ""
    @State private var hasUnsavedChanges = false
    @State private var editorError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                statusBanner
                notificationSection
                statusLineSection
                configEditorSection
            }
            .padding(24)
        }
        .onAppear { refreshData() }
    }

    // MARK: - Server Status

    private var statusBanner: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(coordinator.server.isRunning ? Color.green : Color.red)
                .frame(width: 7, height: 7)
            Text(coordinator.server.isRunning ? "运行中" : "未运行")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(coordinator.server.isRunning ? .green : .red)
            Text("·")
                .foregroundStyle(.quaternary)
            Text("127.0.0.1:\(coordinator.settings.port)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Notification Section

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("通知")

            toggleCard {
                settingsToggleRow(
                    label: "通知 Hooks",
                    description: "任务完成、等待输入、API 错误时发送通知",
                    isOn: isAllNotificationHooksPresent()
                ) {
                    toggleAllNotificationHooks(install: !isAllNotificationHooksPresent())
                }

                Divider()

                settingsToggleRow(
                    label: "桌面浮窗通知",
                    description: "任务完成或需要输入时显示浮动通知窗口",
                    isOn: coordinator.settings.floatingNotificationEnabled
                ) {
                    coordinator.settings.floatingNotificationEnabled.toggle()
                }

                Divider()

                settingsToggleRow(
                    label: "系统通知",
                    description: "通过 macOS 系统通知中心发送通知",
                    isOn: coordinator.settings.systemNotificationEnabled
                ) {
                    coordinator.settings.systemNotificationEnabled.toggle()
                }

                Divider()

                settingsToggleRow(
                    label: "提示音",
                    description: "收到通知时播放提示音",
                    isOn: coordinator.settings.soundEnabled
                ) {
                    coordinator.settings.soundEnabled.toggle()
                }
            }
        }
    }

    // MARK: - StatusLine Section

    private var statusLineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("状态栏")

            toggleCard {
                settingsToggleRow(
                    label: "启用状态栏",
                    description: "在终端显示模型信息、上下文用量、Skill 历史",
                    isOn: statusLineEnabled
                ) {
                    statusLineEnabled.toggle()
                    saveStatusLine()
                }

                if statusLineEnabled {
                    Divider()

                    HStack {
                        Text("刷新间隔")
                            .font(.system(size: 13))
                        Spacer()
                        Stepper("\(statusLineInterval) 秒", value: $statusLineInterval, in: 1...30)
                            .font(.system(size: 12))
                            .fixedSize()
                            .onChange(of: statusLineInterval) { _, _ in saveStatusLine() }
                    }
                    .padding(.vertical, 6)

                    Divider()

                    settingsToggleRow(
                        label: "Skill 追踪",
                        description: "PreToolUse — 在状态栏记录 Skill 使用历史",
                        isOn: isCommandHookPresent(key: "hook-pre-skill")
                    ) {
                        toggleCommandHook(event: "PreToolUse")
                    }

                    Divider()

                    settingsToggleRow(
                        label: "命令追踪",
                        description: "UserPromptExpansion — 追踪 / 命令执行",
                        isOn: isCommandHookPresent(key: "hook-skill-tracker")
                    ) {
                        toggleCommandHook(event: "UserPromptExpansion")
                    }
                }
            }
        }
    }

    // MARK: - Config Editor

    private var configEditorSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("配置文件")
                        .font(.system(size: 13, weight: .semibold))
                    Text(settingsManager.settingsPath.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                HStack(spacing: 8) {
                    if hasUnsavedChanges {
                        Button("还原") {
                            editorContent = readRawJSON()
                            hasUnsavedChanges = false
                            editorError = nil
                        }
                        .controlSize(.small)
                    }
                    Button {
                        saveEditorContent()
                    } label: {
                        Label("保存", systemImage: "square.and.arrow.down")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!hasUnsavedChanges)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if let error = editorError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 11))
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.08))
            }

            TextEditor(text: $editorContent)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(minHeight: 200, maxHeight: 400)
                .onChange(of: editorContent) { _, _ in
                    hasUnsavedChanges = editorContent != readRawJSON()
                    if hasUnsavedChanges { validateJSON(editorContent) }
                }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Shared Components

    private func SectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func toggleCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(.horizontal, 14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// A settings-style toggle row: label + description left, switch right.
    private func settingsToggleRow(
        label: String,
        description: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Capsule()
                    .fill(isOn ? Color.accentColor : Color(.separatorColor))
                    .frame(width: 38, height: 22)
                    .overlay(
                        Circle()
                            .fill(.white)
                            .frame(width: 18, height: 18)
                            .shadow(color: .black.opacity(0.15), radius: 1)
                            .offset(x: isOn ? 8 : -8)
                    )
                    .animation(.easeInOut(duration: 0.15), value: isOn)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hook Queries

    private func isAllNotificationHooksPresent() -> Bool {
        ["Stop", "Notification", "StopFailure"].allSatisfy {
            isNotificationHookPresent(event: $0)
        }
    }

    private func isNotificationHookPresent(event: String) -> Bool {
        hooks.contains { $0.event == event && $0.type == .http && $0.target.contains("/hook/") }
    }

    private func isCommandHookPresent(key: String) -> Bool {
        hooks.contains { $0.type == .command && $0.target.contains(key) }
    }

    // MARK: - Toggle Actions

    private func toggleAllNotificationHooks(install: Bool) {
        let events = ["Stop", "Notification", "StopFailure"]
        let hookPaths = ["stop", "notification", "stopfailure"]
        do {
            if install {
                for (event, path) in zip(events, hookPaths) {
                    let config = HookConfig(
                        event: event, matcher: "", type: .http,
                        target: "http://127.0.0.1:\(coordinator.settings.port)/hook/\(path)"
                    )
                    try settingsManager.ensureHook(config)
                }
            } else {
                for event in events {
                    try settingsManager.uninstallHook(event: event, targetContains: "/hook/")
                }
            }
            refreshData()
        } catch {
            print("Toggle notification hooks error: \(error)")
        }
    }

    private func toggleCommandHook(event: String) {
        do {
            if isCommandHookPresent(key: commandDedupKey(event)) {
                try settingsManager.uninstallHook(event: event, targetContains: commandDedupKey(event))
            } else {
                let existing = hooks.first { $0.event == event && $0.type == .command }
                let base = SettingsManager.resolveRepoBase(from: hooks)
                let target: String
                if let existing {
                    target = existing.target
                } else {
                    switch event {
                    case "PreToolUse": target = "bash \(base)/statusline/hook-pre-skill.sh"
                    case "UserPromptExpansion": target = "bash \(base)/statusline/hook-skill-tracker.sh"
                    default: return
                    }
                }
                let matcher = event == "PreToolUse" ? "Skill" : ".*"
                try settingsManager.ensureHook(HookConfig(event: event, matcher: matcher, type: .command, target: target))
            }
            refreshData()
        } catch {
            print("Toggle command hook error: \(error)")
        }
    }

    private func commandDedupKey(_ event: String) -> String {
        switch event {
        case "PreToolUse": return "hook-pre-skill"
        case "UserPromptExpansion": return "hook-skill-tracker"
        default: return event
        }
    }

    // MARK: - Actions

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
    }

    private func saveEditorContent() {
        guard let data = editorContent.data(using: .utf8) else {
            editorError = "编码错误"
            return
        }
        guard (try? JSONSerialization.jsonObject(with: data)) != nil else {
            editorError = "JSON 格式无效，无法保存"
            return
        }
        do {
            try data.write(to: settingsManager.settingsPath, options: .atomic)
            hasUnsavedChanges = false
            editorError = nil
            refreshData()
        } catch {
            editorError = "保存失败: \(error.localizedDescription)"
        }
    }

    private func validateJSON(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            editorError = "编码错误"
            return
        }
        if (try? JSONSerialization.jsonObject(with: data)) != nil {
            editorError = nil
        } else {
            editorError = "JSON 格式无效"
        }
    }

    private func refreshData() {
        hooks = settingsManager.readAllHooks()
        statusLine = settingsManager.readStatusLine()
        statusLineEnabled = statusLine != nil
        statusLineInterval = statusLine?.refreshInterval ?? 5
        coordinator.currentHealth = settingsManager.checkHealth()
        let raw = readRawJSON()
        editorContent = raw
        hasUnsavedChanges = false
        editorError = nil
    }

    private func readRawJSON() -> String {
        let path = settingsManager.settingsPath
        guard FileManager.default.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path),
              let content = String(data: data, encoding: .utf8) else {
            return "{\n  \n}"
        }
        return content
    }
}
