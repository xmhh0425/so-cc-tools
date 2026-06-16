import SwiftUI
import ServiceManagement

struct SettingsPage: View {
    let coordinator: AppCoordinator
    @Binding var page: MenuPage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Button { page = .main } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)

                    Image(systemName: "gear")
                        .font(.title3)
                        .foregroundStyle(.blue)
                    Text("设置")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                }

                Divider()

                // 服务器
                sectionHeader("服务器")
                settingRow("端口", value: "\(coordinator.settings.port)")
                settingRow("状态", value: coordinator.server.isRunning ? "运行中" : "未运行",
                           valueColor: coordinator.server.isRunning ? .green : .red)

                Divider()

                // 通知方式（互斥）
                sectionHeader("通知方式")

                Toggle("浮动横幅", isOn: Binding(
                    get: { coordinator.settings.floatingNotificationEnabled },
                    set: { coordinator.settings.floatingNotificationEnabled = $0; if $0 { coordinator.settings.systemNotificationEnabled = false } }
                ))
                .font(.system(size: 12))

                Toggle("系统通知", isOn: Binding(
                    get: { coordinator.settings.systemNotificationEnabled },
                    set: { coordinator.settings.systemNotificationEnabled = $0; if $0 { coordinator.settings.floatingNotificationEnabled = false } }
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

                    sectionHeader("显示时长（秒）")

                    durationStepper("任务完成", value: Binding(
                        get: { coordinator.settings.stopDuration },
                        set: { coordinator.settings.stopDuration = $0 }
                    ))
                    durationStepper("需要输入", value: Binding(
                        get: { coordinator.settings.notificationDuration },
                        set: { coordinator.settings.notificationDuration = $0 }
                    ))
                    durationStepper("错误", value: Binding(
                        get: { coordinator.settings.stopFailureDuration },
                        set: { coordinator.settings.stopFailureDuration = $0 }
                    ))
                }

                Divider()

                // 通用
                sectionHeader("通用")

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

                Spacer(minLength: 0)

                HStack {
                    Text("v1.0.0")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("完成") { page = .main }
                        .controlSize(.small)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func settingRow(_ label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label).font(.system(size: 12))
            Spacer()
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(valueColor == .primary ? .secondary : valueColor)
        }
    }

    private func durationStepper(_ label: String, value: Binding<Int>) -> some View {
        Stepper(
            "\(label)：\(value.wrappedValue) 秒",
            value: value,
            in: 5...600,
            step: 5
        )
        .font(.system(size: 12))
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        if enabled {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }
}
