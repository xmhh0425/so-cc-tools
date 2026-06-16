import SwiftUI

/// Settings editor page: visualize settings.json by sections, with raw JSON fallback.
struct SettingsEditorView: View {
    let settingsManager: SettingsManager

    @State private var settings: [String: Any]?
    @State private var showRawJSON = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection

                if let errorMessage {
                    errorBanner(errorMessage)
                }

                if let settings {
                    modelSection(settings)
                    envSection(settings)
                    pluginsSection(settings)
                    hooksSection(settings)
                    statusLineSection(settings)
                    rawJSONSection(settings)
                } else {
                    Text("无法读取 settings.json")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .padding(24)
        }
        .onAppear { refreshData() }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Image(systemName: "doc.text")
                .font(.title2)
                .foregroundStyle(.blue)
            Text("设置编辑")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            Button("在编辑器中打开") {
                openInEditor()
            }
            .controlSize(.small)
            Button("刷新") {
                refreshData()
            }
            .controlSize(.small)
        }
    }

    // MARK: - Model Section

    @ViewBuilder
    private func modelSection(_ settings: [String: Any]) -> some View {
        GroupBox("模型") {
            VStack(alignment: .leading, spacing: 8) {
                readonlyRow("默认模型", value: settings["model"] as? String ?? "未设置")
                readonlyRow("Effort 等级", value: settings["effortLevel"] as? String ?? "未设置")
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Environment Variables Section

    @ViewBuilder
    private func envSection(_ settings: [String: Any]) -> some View {
        if let env = settings["env"] as? [String: Any], !env.isEmpty {
            GroupBox("环境变量（env）") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(env.keys.sorted(), id: \.self) { key in
                        let value = env[key] as? String ?? "—"
                        HStack(alignment: .top) {
                            Text(key)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 220, alignment: .leading)
                            Text(maskSensitive(key, value: value))
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Plugins Section

    @ViewBuilder
    private func pluginsSection(_ settings: [String: Any]) -> some View {
        if let plugins = settings["enabledPlugins"] as? [String: Bool], !plugins.isEmpty {
            GroupBox("已启用插件") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(plugins.keys.sorted(), id: \.self) { key in
                        HStack {
                            Image(systemName: plugins[key] == true ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(plugins[key] == true ? .green : .secondary)
                                .font(.system(size: 11))
                            Text(key)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Hooks Section

    @ViewBuilder
    private func hooksSection(_ settings: [String: Any]) -> some View {
        if let hooks = settings["hooks"] as? [String: Any] {
            GroupBox("Hooks") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("共 \(hooks.keys.count) 个事件类型，在「Hook 管理」页可编辑")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    ForEach(hooks.keys.sorted(), id: \.self) { event in
                        HStack {
                            Text(event)
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            if let groups = hooks[event] as? [[String: Any]] {
                                Text("\(groups.count) 条规则")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - StatusLine Section

    @ViewBuilder
    private func statusLineSection(_ settings: [String: Any]) -> some View {
        if let sl = settings["statusLine"] as? [String: Any] {
            GroupBox("statusLine") {
                VStack(alignment: .leading, spacing: 4) {
                    readonlyRow("类型", value: sl["type"] as? String ?? "—")
                    readonlyRow("命令", value: sl["command"] as? String ?? "—")
                    readonlyRow("刷新间隔", value: "\(sl["refreshInterval"] as? Int ?? 0)s")
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Raw JSON Section

    @ViewBuilder
    private func rawJSONSection(_ settings: [String: Any]) -> some View {
        DisclosureGroup("原始 JSON") {
            Text(formatJSON(settings))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        }
    }

    // MARK: - Helpers

    private func readonlyRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    private func maskSensitive(_ key: String, value: String) -> String {
        let sensitiveKeys = ["TOKEN", "SECRET", "KEY", "PASSWORD", "AUTH"]
        let isSensitive = sensitiveKeys.contains { key.uppercased().contains($0) }
        if isSensitive && value.count > 10 {
            return String(value.prefix(6)) + "…" + String(value.suffix(4))
        }
        return value
    }

    private func formatJSON(_ obj: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]),
              let str = String(data: data, encoding: .utf8) else {
            return "无法格式化"
        }
        return str
    }

    private func openInEditor() {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("settings.json")
        NSWorkspace.shared.open(path)
    }

    private func refreshData() {
        settings = settingsManager.readFullSettings()
    }
}
