import SwiftUI
import ServiceManagement

/// Notification page: settings + compact history list.
struct NotificationHistoryView: View {
    let coordinator: AppCoordinator

    @State private var filterEvent: HookEvent?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                settingsSection
                historySection
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Toggles row
            HStack(spacing: 0) {
                Toggle("浮动横幅", isOn: Binding(
                    get: { coordinator.settings.floatingNotificationEnabled },
                    set: {
                        coordinator.settings.floatingNotificationEnabled = $0
                        if $0 { coordinator.settings.systemNotificationEnabled = false }
                    }
                ))
                .font(.system(size: 12))
                .frame(maxWidth: .infinity)

                Divider().frame(height: 18)

                Toggle("系统通知", isOn: Binding(
                    get: { coordinator.settings.systemNotificationEnabled },
                    set: {
                        coordinator.settings.systemNotificationEnabled = $0
                        if $0 { coordinator.settings.floatingNotificationEnabled = false }
                    }
                ))
                .font(.system(size: 12))
                .frame(maxWidth: .infinity)

                Divider().frame(height: 18)

                Toggle("提示音", isOn: Binding(
                    get: { coordinator.settings.soundEnabled },
                    set: { coordinator.settings.soundEnabled = $0 }
                ))
                .font(.system(size: 12))
                .frame(maxWidth: .infinity)
            }

            Divider()

            // 空闲提醒开关
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("空闲提醒")
                        .font(.system(size: 12))
                    Text("Claude 空闲等待输入时也提醒；关闭后只在完成一轮回复时提醒")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { coordinator.settings.idleNotificationEnabled },
                    set: { coordinator.settings.idleNotificationEnabled = $0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            // 快速检测（更快的完成提醒）
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("快速检测")
                        .font(.system(size: 12))
                    Text("盯住 transcript，一轮输出结束后几秒内提醒；Stop 钩子仍作为兜底")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { coordinator.settings.fastTurnDetectionEnabled },
                    set: { coordinator.settings.fastTurnDetectionEnabled = $0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            // 前台是终端时不提醒
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("前台是终端时不提醒")
                        .font(.system(size: 12))
                    Text("你正盯着终端时不再打断；切走后才提醒")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { coordinator.settings.terminalFocusSuppressesNotifications },
                    set: { coordinator.settings.terminalFocusSuppressesNotifications = $0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            // “完成通知”延迟确认
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("完成通知延迟")
                        .font(.system(size: 12))
                    Text("等待设定秒数再通知，实际还会叠加 Claude Code 自身的约 30 秒；期间你继续对话则撤销；0 秒为立即通知")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Stepper(
                    "\(coordinator.settings.stopNotifyDelaySeconds)s",
                    value: Binding(
                        get: { coordinator.settings.stopNotifyDelaySeconds },
                        set: { coordinator.settings.stopNotifyDelaySeconds = $0 }
                    ),
                    in: 0...600,
                    step: 30
                )
                .font(.system(size: 11))
                .fixedSize()
            }

            // 同一会话的通知去重窗口
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("通知去重窗口")
                        .font(.system(size: 12))
                    Text("同一会话在这段时间内只提醒一次；0 表示不去重")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Stepper(
                    "\(coordinator.settings.stopNotifyDedupSeconds)s",
                    value: Binding(
                        get: { coordinator.settings.stopNotifyDedupSeconds },
                        set: { coordinator.settings.stopNotifyDedupSeconds = $0 }
                    ),
                    in: 0...600,
                    step: 30
                )
                .font(.system(size: 11))
                .fixedSize()
            }

            Divider()

            // Duration steppers in compact 2-column grid
            if coordinator.settings.floatingNotificationEnabled {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ], spacing: 10) {
                    compactDurationStepper(
                        label: "任务完成",
                        value: Binding(
                            get: { coordinator.settings.stopDuration },
                            set: { coordinator.settings.stopDuration = $0 }
                        )
                    )
                    if coordinator.settings.idleNotificationEnabled {
                        compactDurationStepper(
                            label: "等待输入",
                            value: Binding(
                                get: { coordinator.settings.notificationDuration },
                                set: { coordinator.settings.notificationDuration = $0 }
                            )
                        )
                    }
                    compactDurationStepper(
                        label: "错误",
                        value: Binding(
                            get: { coordinator.settings.stopFailureDuration },
                            set: { coordinator.settings.stopFailureDuration = $0 }
                        )
                    )
                    compactDurationStepper(
                        label: "配置异常",
                        value: Binding(
                            get: { coordinator.settings.configBrokenDuration },
                            set: { coordinator.settings.configBrokenDuration = $0 }
                        )
                    )
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(.blue.opacity(0.7))
                .frame(width: 4)
        }
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("最近通知")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                if !coordinator.history.records.isEmpty {
                    HStack(spacing: 6) {
                        Menu {
                            Button("全部", action: { filterEvent = nil })
                            ForEach(HookEvent.allCases, id: \.self) { event in
                                Button(event.displayName, action: { filterEvent = event })
                            }
                        } label: {
                            Text(filterEvent?.displayName ?? "全部")
                                .font(.system(size: 11))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()

                        Button("清空") {
                            coordinator.history.clearAll()
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                    }
                }
            }

            if filteredRecords.isEmpty {
                Text(filterEvent != nil ? "没有 \(filterEvent!.displayName) 类型的通知" : "暂无通知记录")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 48)
            } else {
                VStack(spacing: 0) {
                    ForEach(filteredRecords) { record in
                        HistoryRowView(record: record)
                            .padding(.vertical, 8)
                        if record.id != filteredRecords.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Components

    private func compactDurationStepper(label: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Stepper(
                "\(value.wrappedValue)s",
                value: value,
                in: 5...600,
                step: 5
            )
            .font(.system(size: 11))
            .fixedSize()
        }
    }

    // MARK: - Helpers

    private var filteredRecords: [NotificationRecord] {
        if let filterEvent {
            return coordinator.history.records.filter { $0.event == filterEvent }
        }
        return coordinator.history.records
    }
}
