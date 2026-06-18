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
                    compactDurationStepper(
                        label: "等待输入",
                        value: Binding(
                            get: { coordinator.settings.notificationDuration },
                            set: { coordinator.settings.notificationDuration = $0 }
                        )
                    )
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
