import SwiftUI

/// Overview page: service status, hook summary, quick actions.
struct DashboardView: View {
    let coordinator: AppCoordinator
    let settingsManager: SettingsManager
    @State private var hooks: [HookConfig] = []
    @State private var statusLine: StatusLineConfig?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                serviceCard
                hookSummaryCard
                statusLineCard
                quickActionsCard
            }
            .padding(24)
        }
        .onAppear { refreshData() }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Image(systemName: "square.grid.2x2.fill")
                .font(.title2)
                .foregroundStyle(.blue)
            Text("概览")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            Text("Claude Code Tools")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Service Card

    private var serviceCard: some View {
        GroupBox("服务状态") {
            VStack(alignment: .leading, spacing: 10) {
                statusRow(
                    icon: "server.rack",
                    label: "HTTP Server",
                    status: coordinator.server.isRunning ? "运行中" : "未运行",
                    color: coordinator.server.isRunning ? .green : .red
                )
                statusRow(
                    icon: "network",
                    label: "监听地址",
                    status: "127.0.0.1:\(coordinator.settings.port)",
                    color: .primary
                )
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Hook Summary Card

    private var hookSummaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hook 状态").font(.headline)
            hookSummaryRow(event: "Stop", label: "Stop（任务完成）", typeLabel: "HTTP", targetContains: "/hook/stop")
            hookSummaryRow(event: "Notification", label: "Notification（等待输入）", typeLabel: "HTTP", targetContains: "/hook/notification")
            hookSummaryRow(event: "StopFailure", label: "StopFailure（API 错误）", typeLabel: "HTTP", targetContains: "/hook/stopfailure")
            hookSummaryRow(event: "PreToolUse", label: "PreToolUse（Skill 追踪）", typeLabel: "command", targetContains: "hook-pre-skill")
            hookSummaryRow(event: "UserPromptExpansion", label: "UserPromptExpansion（命令追踪）", typeLabel: "command", targetContains: "hook-skill-tracker")
        }
    }

    private func hookSummaryRow(event: String, label: String, typeLabel: String, targetContains: String?) -> some View {
        let installed = hooks.contains { hook in
            hook.event == event && (targetContains == nil || hook.target.contains(targetContains!))
        }
        return HStack {
            Image(systemName: installed ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(installed ? .green : .secondary)
                .font(.system(size: 13))
            Text(label)
                .font(.system(size: 12))
            Spacer()
            Text(installed ? typeLabel : "未安装")
                .font(.system(size: 11))
                .foregroundStyle(installed ? Color.secondary : Color.orange)
        }
    }

    // MARK: - StatusLine Card

    private var statusLineCard: some View {
        GroupBox("状态栏") {
            HStack {
                Image(systemName: statusLine != nil ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(statusLine != nil ? .green : .secondary)
                    .font(.system(size: 13))
                Text(statusLine != nil ? "已配置" : "未配置")
                    .font(.system(size: 12))
                Spacer()
                if let sl = statusLine {
                    Text("刷新间隔 \(sl.refreshInterval)s")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Quick Actions Card

    private var quickActionsCard: some View {
        GroupBox("快捷操作") {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    coordinator.repairConfig()
                    refreshData()
                } label: {
                    Label("一键修复配置", systemImage: "wrench.and.screwdriver")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Text("自动合并回 statusLine + 全部 hooks，不影响其他字段。")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Helpers

    private func statusRow(icon: String, label: String, status: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(label)
                .font(.system(size: 12))
            Spacer()
            Text(status)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(color == .primary ? .secondary : color)
        }
    }

    // MARK: - Expected hooks definition

    private func refreshData() {
        hooks = settingsManager.readAllHooks()
        statusLine = settingsManager.readStatusLine()
    }
}
