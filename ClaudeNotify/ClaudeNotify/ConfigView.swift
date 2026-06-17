import SwiftUI

/// Unified configuration page: health summary + one-click fix + per-item toggles.
struct ConfigView: View {
    let coordinator: AppCoordinator
    let settingsManager: SettingsManager

    @State private var hooks: [HookConfig] = []
    @State private var statusLine: StatusLineConfig?
    @State private var statusLineEnabled = false
    @State private var statusLineInterval = 5
    @State private var showSaveConfirmation = false
    @State private var isRepairing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                healthCard
                hookListSection
                statusLineSection
            }
            .padding(24)
        }
        .onAppear { refreshData() }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Image(systemName: "gearshape.2.fill")
                .font(.title2)
                .foregroundStyle(.blue)
            Text("配置")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            Button("刷新") { refreshData() }
                .controlSize(.small)
        }
    }

    // MARK: - Health Summary Card

    private var healthCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if let health = coordinator.currentHealth {
                    HStack(spacing: 8) {
                        Image(systemName: health.isHealthy ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .font(.title3)
                            .foregroundStyle(health.isHealthy ? .green : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(health.isHealthy ? "配置正常" : "检测到 \(health.missingCount) 项配置缺失")
                                .font(.system(size: 13, weight: .semibold))
                            if !health.isHealthy {
                                let missing = health.items.filter { !$0.isPresent }.map(\.label)
                                    + (health.statusLinePresent ? [] : ["statusLine"])
                                Text(missing.joined(separator: "、"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()

                        if !health.isHealthy {
                            Button {
                                repairConfig()
                            } label: {
                                Label(isRepairing ? "修复中…" : "一键修复", systemImage: "wrench.and.screwdriver")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(isRepairing)
                        }
                    }

                    Divider()

                    Toggle("配置被覆盖时自动修复", isOn: Binding(
                        get: { coordinator.settings.autoFixOnDrift },
                        set: { coordinator.settings.autoFixOnDrift = $0 }
                    ))
                    .font(.system(size: 12))

                    Text("CC Switch 等工具可能覆盖配置。开启后检测到配置失效时自动修复。")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("正在检查配置…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Per-item Hook List

    private var hookListSection: some View {
        GroupBox("Hook 配置") {
            VStack(alignment: .leading, spacing: 0) {
                // Notification hooks
                ForEach(["Stop", "Notification", "StopFailure"], id: \.self) { event in
                    let label = eventLabel(event)
                    let isPresent = isHookPresent(event: event)
                    hookRow(event: event, label: label, isPresent: isPresent) {
                        toggleNotificationHook(event: event)
                    }
                    Divider().padding(.horizontal, -8)
                }

                // Command hooks
                ForEach(["PreToolUse", "UserPromptExpansion"], id: \.self) { event in
                    let label = eventLabel(event)
                    let isPresent = isHookPresent(event: event)
                    hookRow(event: event, label: label, isPresent: isPresent) {
                        toggleCommandHook(event: event)
                    }
                    if event != "UserPromptExpansion" {
                        Divider().padding(.horizontal, -8)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func hookRow(event: String, label: String, isPresent: Bool, toggle: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isPresent ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(isPresent ? .green : .secondary)
                .font(.system(size: 14))
            Text(label)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Button(isPresent ? "卸载" : "安装") { toggle() }
                .controlSize(.small)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
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

                Text("状态栏通过终端显示模型信息、上下文用量、Skill 历史。")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Actions

    private func isHookPresent(event: String) -> Bool {
        hooks.contains { h in
            h.event == event && (
                (h.type == .http && h.target.contains("/hook/"))
                || (h.type == .command && h.target.contains(commandDedupKey(event)))
            )
        }
    }

    private func commandDedupKey(_ event: String) -> String {
        switch event {
        case "PreToolUse": return "hook-pre-skill"
        case "UserPromptExpansion": return "hook-skill-tracker"
        case "Stop", "Notification", "StopFailure": return "notify-claude-notify"
        default: return event
        }
    }

    private func eventLabel(_ event: String) -> String {
        switch event {
        case "Stop": return "Stop（任务完成）"
        case "Notification": return "Notification（等待输入）"
        case "StopFailure": return "StopFailure（API 错误）"
        case "PreToolUse": return "PreToolUse（Skill 追踪）"
        case "UserPromptExpansion": return "UserPromptExpansion（命令追踪）"
        default: return event
        }
    }

    private func toggleNotificationHook(event: String) {
        let hookPath: String
        switch event {
        case "Stop": hookPath = "stop"
        case "Notification": hookPath = "notification"
        case "StopFailure": hookPath = "stopfailure"
        default: return
        }
        do {
            if isHookPresent(event: event) {
                try settingsManager.uninstallHook(event: event, targetContains: "/hook/")
            } else {
                let config = HookConfig(event: event, matcher: "", type: .http, target: "http://127.0.0.1:\(coordinator.settings.port)/hook/\(hookPath)")
                try settingsManager.ensureHook(config)
            }
            refreshData()
        } catch {
            print("Error: \(error)")
        }
    }

    private func toggleCommandHook(event: String) {
        do {
            if isHookPresent(event: event) {
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
            print("Error: \(error)")
        }
    }

    private func repairConfig() {
        isRepairing = true
        coordinator.repairConfig()
        refreshData()
        isRepairing = false
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
        // Sync coordinator health state so all views stay consistent
        coordinator.currentHealth = settingsManager.checkHealth()
    }

    private func flashConfirmation() {
        showSaveConfirmation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showSaveConfirmation = false
        }
    }
}
