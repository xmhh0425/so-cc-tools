import SwiftUI
import ServiceManagement

/// Notification history page: full history list, filtering, and notification settings.
struct NotificationHistoryView: View {
    let coordinator: AppCoordinator

    @State private var filterEvent: HookEvent?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                notificationSettingsCard
                generalSettingsCard

                if filteredRecords.isEmpty {
                    emptyState
                } else {
                    historyList
                }
            }
            .padding(24)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Image(systemName: "bell.badge")
                .font(.title2)
                .foregroundStyle(.blue)
            Text("通知历史")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            Menu {
                Button("全部", action: { filterEvent = nil })
                ForEach(HookEvent.allCases, id: \.self) { event in
                    Button(event.displayName, action: { filterEvent = event })
                }
            } label: {
                HStack(spacing: 4) {
                    Text(filterEvent?.displayName ?? "全部")
                        .font(.system(size: 12))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9))
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if !coordinator.history.records.isEmpty {
                Button("清空") {
                    coordinator.history.clearAll()
                }
                .controlSize(.small)
                .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Notification Settings Card

    private var notificationSettingsCard: some View {
        GroupBox("通知设置") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("浮动横幅", isOn: Binding(
                    get: { coordinator.settings.floatingNotificationEnabled },
                    set: {
                        coordinator.settings.floatingNotificationEnabled = $0
                        if $0 { coordinator.settings.systemNotificationEnabled = false }
                    }
                ))
                .font(.system(size: 12))

                Toggle("系统通知", isOn: Binding(
                    get: { coordinator.settings.systemNotificationEnabled },
                    set: {
                        coordinator.settings.systemNotificationEnabled = $0
                        if $0 { coordinator.settings.floatingNotificationEnabled = false }
                    }
                ))
                .font(.system(size: 12))

                if coordinator.settings.systemNotificationEnabled {
                    Toggle("播放声音", isOn: Binding(
                        get: { coordinator.settings.soundEnabled },
                        set: { coordinator.settings.soundEnabled = $0 }
                    ))
                    .font(.system(size: 12))
                }

                if coordinator.settings.floatingNotificationEnabled {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        durationStepper("任务完成", value: Binding(
                            get: { coordinator.settings.stopDuration },
                            set: { coordinator.settings.stopDuration = $0 }
                        ))
                        durationStepper("等待输入", value: Binding(
                            get: { coordinator.settings.notificationDuration },
                            set: { coordinator.settings.notificationDuration = $0 }
                        ))
                        durationStepper("错误", value: Binding(
                            get: { coordinator.settings.stopFailureDuration },
                            set: { coordinator.settings.stopFailureDuration = $0 }
                        ))
                        durationStepper("配置异常", value: Binding(
                            get: { coordinator.settings.configBrokenDuration },
                            set: { coordinator.settings.configBrokenDuration = $0 }
                        ))
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - General Settings Card

    private var generalSettingsCard: some View {
        GroupBox("通用") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("登录时启动", isOn: Binding(
                    get: { coordinator.settings.launchAtLogin },
                    set: { coordinator.settings.launchAtLogin = $0; setLaunchAtLogin($0) }
                ))
                .font(.system(size: 12))

                Stepper(
                    "历史记录：\(coordinator.settings.maxHistoryDisplay) 条",
                    value: Binding(
                        get: { coordinator.settings.maxHistoryDisplay },
                        set: { coordinator.settings.maxHistoryDisplay = $0 }
                    ),
                    in: 5...50
                )
                .font(.system(size: 12))
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - History List

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(filteredRecords) { record in
                HistoryRowView(record: record)
                    .padding(.vertical, 8)
                Divider()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bell.slash")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(filterEvent != nil ? "没有 \(filterEvent!.displayName) 类型的通知" : "暂无通知记录")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text("Claude Code 发送 Hook 事件后，通知记录会出现在这里。")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Helpers

    private var filteredRecords: [NotificationRecord] {
        if let filterEvent {
            return coordinator.history.records.filter { $0.event == filterEvent }
        }
        return coordinator.history.records
    }

    private func durationStepper(_ label: String, value: Binding<Int>) -> some View {
        Stepper(
            "\(label): \(value.wrappedValue)s",
            value: value,
            in: 5...600,
            step: 5
        )
        .font(.system(size: 11))
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        if enabled {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }
}
