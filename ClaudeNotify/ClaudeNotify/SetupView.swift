import SwiftUI

struct SetupPage: View {
    let coordinator: AppCoordinator
    @Binding var page: MenuPage
    @State private var settingsManager = ClaudeSettingsManager()
    @State private var hookStatus: [HookEvent: Bool] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Button { page = .main } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)

                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
                Text("配置 Hook")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }

            Text("ClaudeNotify 需要在 Claude Code 中配置 HTTP Hook 才能接收事件通知。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Divider()

            ForEach(HookEvent.allCases, id: \.self) { event in
                HStack {
                    Image(systemName: hookStatus[event] == true ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(hookStatus[event] == true ? .green : .secondary)
                        .font(.system(size: 13))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.displayName)
                            .font(.system(size: 12, weight: .medium))
                        Text("http://127.0.0.1:\(coordinator.settings.port)/hook/\(hookPath(for: event))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Button(hookStatus[event] == true ? "卸载" : "安装") {
                        toggleHook(event: event)
                    }
                    .controlSize(.small)
                }
                .padding(.vertical, 4)
            }

            Divider()

            DisclosureGroup {
                Text(configPreview)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } label: {
                Text("手动配置")
                    .font(.system(size: 11, weight: .medium))
            }

            Spacer(minLength: 0)

            HStack {
                Button("全部安装") { installAll() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("全部卸载") { uninstallAll() }
                    .controlSize(.small)
                Spacer()
                Button("完成") { page = .main }
                    .controlSize(.small)
            }
        }
        .padding(16)
        .onAppear { refreshStatus() }
    }

    private func hookPath(for event: HookEvent) -> String {
        switch event {
        case .stop: return "stop"
        case .notification: return "notification"
        case .stopFailure: return "stopfailure"
        }
    }

    private func refreshStatus() {
        for event in HookEvent.allCases {
            hookStatus[event] = settingsManager.isHookInstalled(event: event)
        }
    }

    private func toggleHook(event: HookEvent) {
        do {
            if hookStatus[event] == true {
                try settingsManager.uninstallHook(event: event)
            } else {
                try settingsManager.installHook(event: event, port: coordinator.settings.port)
            }
            refreshStatus()
        } catch {
            print("Error: \(error)")
        }
    }

    private func installAll() {
        for event in HookEvent.allCases {
            if hookStatus[event] != true {
                try? settingsManager.installHook(event: event, port: coordinator.settings.port)
            }
        }
        refreshStatus()
    }

    private func uninstallAll() {
        for event in HookEvent.allCases {
            try? settingsManager.uninstallHook(event: event)
        }
        refreshStatus()
    }

    private var configPreview: String {
        """
        {
          "hooks": {
            "Stop": [{ "matcher": "", "hooks": [{ "type": "http", "url": "http://127.0.0.1:\(coordinator.settings.port)/hook/stop" }] }],
            "Notification": [{ "matcher": "", "hooks": [{ "type": "http", "url": "http://127.0.0.1:\(coordinator.settings.port)/hook/notification" }] }],
            "StopFailure": [{ "matcher": "", "hooks": [{ "type": "http", "url": "http://127.0.0.1:\(coordinator.settings.port)/hook/stopfailure" }] }]
          }
        }
        """
    }
}
