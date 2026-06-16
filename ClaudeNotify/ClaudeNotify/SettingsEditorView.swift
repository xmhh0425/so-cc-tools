import SwiftUI

/// Configuration repair page: run fix-settings.sh to restore overwritten settings.
struct SettingsEditorView: View {
    let settingsManager: SettingsManager

    @State private var isRunning = false
    @State private var result: FixResult?
    @State private var settings: [String: Any]?

    struct FixResult {
        let success: Bool
        let output: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                explanationCard
                actionCard
                if let result {
                    resultCard(result)
                }
                currentConfigCard
            }
            .padding(24)
        }
        .onAppear { refreshData() }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.title2)
                .foregroundStyle(.blue)
            Text("配置修复")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            Button("刷新") {
                refreshData()
            }
            .controlSize(.small)
        }
    }

    // MARK: - Explanation Card

    private var explanationCard: some View {
        GroupBox("为什么需要修复？") {
            VStack(alignment: .leading, spacing: 8) {
                Text("CC Switch 等代理切换工具会重写 `~/.claude/settings.json`，丢弃 `statusLine` 和 `hooks` 字段，导致状态栏和通知失效。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Text("修复脚本会将缺失的配置合并回去，不影响其他字段。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Action Card

    private var actionCard: some View {
        GroupBox("操作") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        runFixScript()
                    } label: {
                        Label(isRunning ? "修复中…" : "一键修复", systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(isRunning)

                    if isRunning {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }

                Text("执行 `fix-settings.sh`，合并回 statusLine + 全部 hooks，写前自动备份。")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Result Card

    @ViewBuilder
    private func resultCard(_ result: FixResult) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.success ? .green : .red)
                        .font(.system(size: 14))
                    Text(result.success ? "修复成功" : "修复失败")
                        .font(.system(size: 13, weight: .medium))
                }

                Text(result.output)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if result.success {
                    Text("若当前会话未立即生效，重开一个 Claude Code 会话即可。")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Current Config Card

    private var currentConfigCard: some View {
        GroupBox("当前配置状态") {
            VStack(alignment: .leading, spacing: 8) {
                if let settings {
                    configStatusRow("hooks", exists: settings["hooks"] != nil)
                    configStatusRow("statusLine", exists: settings["statusLine"] != nil)
                    configStatusRow("model", exists: settings["model"] != nil)
                    configStatusRow("env", exists: settings["env"] != nil)
                } else {
                    Text("无法读取 settings.json")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func configStatusRow(_ key: String, exists: Bool) -> some View {
        HStack {
            Image(systemName: exists ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(exists ? .green : .secondary)
                .font(.system(size: 12))
            Text(key)
                .font(.system(size: 12, design: .monospaced))
            Spacer()
            Text(exists ? "已配置" : "未配置")
                .font(.system(size: 11))
                .foregroundStyle(exists ? Color.secondary : Color.orange)
        }
    }

    // MARK: - Actions

    private func runFixScript() {
        isRunning = true
        result = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let scriptPath = resolveFixScriptPath()
            let success: Bool
            let output: String

            if let scriptPath {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = [scriptPath]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    success = process.terminationStatus == 0
                } catch {
                    output = "执行失败：\(error.localizedDescription)"
                    success = false
                }
            } else {
                output = "未找到 fix-settings.sh，请确认仓库路径。"
                success = false
            }

            DispatchQueue.main.async {
                self.isRunning = false
                self.result = FixResult(success: success, output: output)
                self.refreshData()
            }
        }
    }

    private func resolveFixScriptPath() -> String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/AI/so-cc-tools/fix-settings.sh",
            "\(home)/AI/claude-tools/fix-settings.sh",
        ]
        return candidates.first { fm.fileExists(atPath: $0) }
    }

    private func refreshData() {
        settings = settingsManager.readFullSettings()
    }
}
