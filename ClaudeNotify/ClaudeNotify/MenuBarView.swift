import SwiftUI

struct MenuBarView: View {
    let coordinator: AppCoordinator
    @State private var page: MenuPage = .main

    var body: some View {
        Group {
            switch page {
            case .main:
                mainPage
            case .setup:
                SetupPage(coordinator: coordinator, page: $page)
            case .settings:
                SettingsPage(coordinator: coordinator, page: $page)
            }
        }
        .frame(width: 340)
        .animation(.easeInOut(duration: 0.15), value: page)
    }

    // MARK: - Main Page

    private var mainPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider()
            statusSection
            Divider()

            if coordinator.history.records.isEmpty {
                emptyState
            } else {
                historyList
            }

            Divider()
            actionSection
        }
    }

    private var headerSection: some View {
        HStack(spacing: 6) {
            Image(systemName: "bell.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.blue)
            Text("ClaudeNotify")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text("v1.0")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var statusSection: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(coordinator.server.isRunning ? .green : .red)
                .frame(width: 6, height: 6)
            Text(coordinator.server.isRunning
                ? "监听中 127.0.0.1:\(coordinator.settings.port)"
                : "服务未运行")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "bell.slash")
                .font(.system(size: 20))
                .foregroundStyle(.tertiary)
            Text("暂无通知")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("请在 Claude Code 中配置 Hook")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var historyList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(coordinator.history.records.prefix(coordinator.settings.maxHistoryDisplay)) { record in
                    HistoryRowView(record: record)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    Divider()
                }
            }
        }
        .frame(maxHeight: 320)
    }

    private var actionSection: some View {
        VStack(spacing: 0) {
            actionRow(icon: "wrench.and.screwdriver", title: "配置 Hook") {
                page = .setup
            }
            actionRow(icon: "gear", title: "设置") {
                page = .settings
            }
            if !coordinator.history.records.isEmpty {
                actionRow(icon: "trash", title: "清空历史") {
                    coordinator.history.clearAll()
                }
            }
            Divider()
            QuitRow()
        }
        .padding(.vertical, 4)
    }

    private func actionRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        ActionRow(icon: icon, title: title, action: action)
    }
}

// MARK: - Reusable Components

private struct ActionRow: View {
    let icon: String
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(hovering ? Color.accentColor.opacity(0.12) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct QuitRow: View {
    @State private var hovering = false

    var body: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Text("退出")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(hovering ? Color.red.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
