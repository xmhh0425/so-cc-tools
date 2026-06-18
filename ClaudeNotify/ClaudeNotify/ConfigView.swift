import SwiftUI

/// Configuration page.
/// Editor content is the single source of truth for the draft.
/// Toggles derive from / mutate the editor text. Nothing is written to disk
/// until the user clicks 保存.
struct ConfigView: View {
    let coordinator: AppCoordinator
    let settingsManager: SettingsManager

    /// The draft. Toggles read/write this; saving persists it to disk.
    @State private var editorContent: String = ""
    /// Last-known on-disk content, used to detect dirty state and external changes.
    @State private var diskContent: String = ""
    @State private var editorError: String?
    @State private var externalChangeWhileEditing = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                statusBanner.fixedSize()
                togglesSection.fixedSize()
                configEditorSection
                    .frame(minWidth: 0, idealWidth: .infinity, maxWidth: .infinity, minHeight: 0, idealHeight: 300, alignment: .topLeading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)
            .background(Color(nsColor: .windowBackgroundColor))

            saveBar
        }
        .onAppear { reloadFromDisk(resetEditor: true) }
        .onChange(of: coordinator.settingsExternalChangeToken) { _, _ in
            handleExternalChange()
        }
    }

    // MARK: - Derived state (read editor JSON)

    /// Parsed editor JSON, or nil if invalid.
    private var parsedJSON: [String: Any]? {
        guard let data = editorContent.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    private var isJSONValid: Bool { parsedJSON != nil }

    private var hasUnsavedChanges: Bool { editorContent != diskContent }

    /// Notification hooks present iff the editor JSON has all three events covered
    /// by either HTTP /hook/ entries or command hooks pointing at notify-claude-notify.sh.
    private var notificationHooksOn: Bool {
        guard let json = parsedJSON,
              let hooks = json["hooks"] as? [String: Any] else { return false }
        return ["Stop", "Notification", "StopFailure"].allSatisfy { event in
            guard let groups = hooks[event] as? [[String: Any]] else { return false }
            return groups.contains { group in
                guard let handlers = group["hooks"] as? [[String: Any]] else { return false }
                return handlers.contains { h in
                    let isHTTP = (h["type"] as? String) == "http"
                        && ((h["url"] as? String)?.contains("/hook/") ?? false)
                    let isCommand = (h["type"] as? String) == "command"
                        && ((h["command"] as? String)?.contains("notify-claude-notify") ?? false)
                    return isHTTP || isCommand
                }
            }
        }
    }

    private var statusLineOn: Bool {
        guard let json = parsedJSON else { return false }
        return json["statusLine"] is [String: Any]
    }

    private var statusLineInterval: Int {
        guard let json = parsedJSON,
              let sl = json["statusLine"] as? [String: Any] else { return 5 }
        return sl["refreshInterval"] as? Int ?? 5
    }

    /// Per-line background colors for the editor. Blue for "hooks" sections,
    /// green for "statusLine" sections. Colors appear only when the
    /// corresponding toggle is ON.
    private var lineHighlights: [Int: Color] {
        var colors: [Int: Color] = [:]
        let sections: [(key: String, color: Color)] = [
            ("hooks", .blue.opacity(0.07)),
            ("statusLine", .green.opacity(0.07)),
        ]
        for (key, sectionColor) in sections {
            for (start, end) in jsonSectionRanges(editorContent, key: key) {
                // Only color when the matching toggle is active.
                let color = (key == "hooks" && notificationHooksOn)
                    || (key == "statusLine" && statusLineOn)
                    ? sectionColor : nil
                guard let color else { continue }
                for line in start...end { colors[line] = color }
            }
        }
        return colors
    }

    /// Find line ranges where a top-level JSON key's value block appears.
    /// Returns [(startLine, endLine)] (1-based, inclusive).
    private func jsonSectionRanges(_ text: String, key: String) -> [(Int, Int)] {
        let lines = text.components(separatedBy: "\n")
        var results: [(Int, Int)] = []
        var lineIndex = 0
        while lineIndex < lines.count {
            let trimmed = lines[lineIndex].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\"\(key)\"") && trimmed.contains(":") {
                let startLine = lineIndex + 1
                // Find the opening brace/bracket on this line or the next.
                var depth = 0
                var foundOpen = false
                var j = lineIndex
                while j < min(lineIndex + 2, lines.count) {
                    for ch in lines[j] {
                        if ch == "{" || ch == "[" {
                            depth += 1; foundOpen = true
                        } else if ch == "}" || ch == "]" { depth -= 1 }
                    }
                    if foundOpen && depth <= 0 {
                        results.append((startLine, j + 1))
                        lineIndex = j + 1
                        break
                    }
                    j += 1
                }
                if !foundOpen || depth > 0 {
                    // Value spans multiple lines; walk until matching close.
                    j = max(j, lineIndex + 1)
                    while j < lines.count && depth > 0 {
                        for ch in lines[j] {
                            if ch == "{" || ch == "[" { depth += 1 }
                            else if ch == "}" || ch == "]" { depth -= 1 }
                        }
                        j += 1
                    }
                    results.append((startLine, j))
                    lineIndex = j
                    continue
                }
                continue
            }
            lineIndex += 1
        }
        return results
    }

    // MARK: - Server Status

    private var statusBanner: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(coordinator.server.isRunning ? Color.green : Color.red)
                .frame(width: 7, height: 7)
            Text(coordinator.server.isRunning ? "运行中" : "未运行")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(coordinator.server.isRunning ? .green : .red)
            Text("·")
                .foregroundStyle(.quaternary)
            Text("127.0.0.1:\(coordinator.settings.port)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Toggles

    private var togglesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("配置")

            toggleCard(
                color: .blue,
                icon: "bell.badge",
                title: "通知 Hooks",
                description: "Stop / Notification / StopFailure — 任务完成、等待输入、API 错误时通知"
            ) {
                settingsToggleRow(
                    label: "通知 Hooks",
                    description: "Stop / Notification / StopFailure — 任务完成、等待输入、API 错误时通知",
                    isOn: notificationHooksOn,
                    disabled: !isJSONValid
                ) {
                    mutateJSON { setNotificationHooks(in: &$0, enabled: !notificationHooksOn) }
                }
            }

            toggleCard(
                color: .green,
                icon: "terminal",
                title: "状态栏",
                description: "在终端显示模型、上下文用量、Skill 历史"
            ) {
                settingsToggleRow(
                    label: "状态栏",
                    description: "在终端显示模型、上下文用量、Skill 历史",
                    isOn: statusLineOn,
                    disabled: !isJSONValid
                ) {
                    mutateJSON { setStatusLine(in: &$0, enabled: !statusLineOn) }
                }

                if statusLineOn {
                    Divider()
                    HStack {
                        Text("刷新间隔")
                            .font(.system(size: 13))
                        Spacer()
                        Stepper(
                            "\(statusLineInterval) 秒",
                            value: Binding(
                                get: { statusLineInterval },
                                set: { newValue in
                                    mutateJSON { setStatusLineInterval(in: &$0, seconds: newValue) }
                                }
                            ),
                            in: 1...30
                        )
                        .font(.system(size: 12))
                        .fixedSize()
                        .disabled(!isJSONValid)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: - Editor

    private var configEditorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("配置文件")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(settingsManager.settingsPath.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if externalChangeWhileEditing {
                infoBanner(
                    icon: "arrow.triangle.2.circlepath",
                    color: .blue,
                    text: "文件已被外部修改。点「重新加载」放弃当前改动并读取最新内容。"
                )
            } else if let error = editorError {
                infoBanner(icon: "exclamationmark.triangle.fill", color: .orange, text: error)
            }

            CodeTextEditor(text: $editorContent, lineHighlights: lineHighlights)
                .padding(2)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isJSONValid ? Color(nsColor: .separatorColor) : Color.orange.opacity(0.6),
                            lineWidth: 1
                        )
                )
                .frame(minHeight: 240, maxHeight: .infinity)
                .onChange(of: editorContent) { _, _ in
                    validateJSON(editorContent)
                }
        }
    }

    // MARK: - Bottom Save Bar

    private var saveBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                if hasUnsavedChanges {
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                    Text("未保存的修改")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text("已同步磁盘")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                reloadFromDisk(resetEditor: true)
            } label: {
                Label("重新加载", systemImage: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .controlSize(.regular)

            Button {
                saveEditorContent()
            } label: {
                Label("保存", systemImage: "square.and.arrow.down")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(!hasUnsavedChanges || !isJSONValid)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    // MARK: - Shared Components

    private func SectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func toggleCard<Content: View>(
        color: Color,
        icon: String,
        title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(.horizontal, 14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.7))
                .frame(width: 4)
        }
    }

    private func infoBanner(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 11))
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func settingsToggleRow(
        label: String,
        description: String,
        isOn: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 13))
                        .foregroundStyle(disabled ? .tertiary : .primary)
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(disabled ? .quaternary : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Capsule()
                    .fill(isOn ? Color.accentColor : Color(.separatorColor))
                    .frame(width: 38, height: 22)
                    .overlay(
                        Circle()
                            .fill(.white)
                            .frame(width: 18, height: 18)
                            .shadow(color: .black.opacity(0.15), radius: 1)
                            .offset(x: isOn ? 8 : -8)
                    )
                    .opacity(disabled ? 0.4 : 1)
                    .animation(.easeInOut(duration: 0.15), value: isOn)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: - JSON Mutation (editor as source of truth)

    /// Parse → mutate → re-serialize. No-op if JSON is invalid (toggle disabled).
    private func mutateJSON(_ mutator: (inout [String: Any]) -> Void) {
        guard var json = parsedJSON else { return }
        mutator(&json)
        guard let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ),
        let text = String(data: data, encoding: .utf8)
        else { return }
        editorContent = text
    }

    private func setNotificationHooks(in json: inout [String: Any], enabled: Bool) {
        var hooks = json["hooks"] as? [String: Any] ?? [:]
        let port = coordinator.settings.port
        let mapping: [(event: String, path: String)] = [
            ("Stop", "stop"),
            ("Notification", "notification"),
            ("StopFailure", "stopfailure"),
        ]

        for (event, path) in mapping {
            var eventGroups = hooks[event] as? [[String: Any]] ?? []
            // Drop any existing /hook/ HTTP entry AND command-type
            // notify-claude-notify entries for dedup.
            eventGroups.removeAll { group in
                guard let handlers = group["hooks"] as? [[String: Any]] else { return false }
                return handlers.contains { h in
                    let isHookHTTP = (h["type"] as? String) == "http"
                        && ((h["url"] as? String)?.contains("/hook/") ?? false)
                    let isCommandNotify = (h["type"] as? String) == "command"
                        && ((h["command"] as? String)?.contains("notify-claude-notify") ?? false)
                    return isHookHTTP || isCommandNotify
                }
            }
            if enabled {
                let url = "http://127.0.0.1:\(port)/hook/\(path)"
                eventGroups.append([
                    "matcher": "",
                    "hooks": [["type": "http", "url": url]],
                ])
            }
            if eventGroups.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = eventGroups
            }
        }

        if hooks.isEmpty {
            json.removeValue(forKey: "hooks")
        } else {
            json["hooks"] = hooks
        }
    }

    private func setStatusLine(in json: inout [String: Any], enabled: Bool) {
        if enabled {
            // Preserve existing command/refreshInterval if present, otherwise default.
            let existing = json["statusLine"] as? [String: Any]
            let command = (existing?["command"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? "bash ~/AI/so-cc-tools/statusline/statusline.sh"
            let interval = existing?["refreshInterval"] as? Int ?? 5
            json["statusLine"] = [
                "type": "command",
                "command": command,
                "refreshInterval": interval,
            ]
        } else {
            json.removeValue(forKey: "statusLine")
        }
    }

    private func setStatusLineInterval(in json: inout [String: Any], seconds: Int) {
        var sl = json["statusLine"] as? [String: Any] ?? [:]
        sl["refreshInterval"] = seconds
        if sl["type"] == nil { sl["type"] = "command" }
        if sl["command"] == nil {
            sl["command"] = "bash ~/AI/so-cc-tools/statusline/statusline.sh"
        }
        json["statusLine"] = sl
    }

    // MARK: - Disk I/O

    private func saveEditorContent() {
        guard let data = editorContent.data(using: .utf8) else {
            editorError = "编码错误"
            return
        }
        guard (try? JSONSerialization.jsonObject(with: data)) != nil else {
            editorError = "JSON 格式无效，无法保存"
            return
        }
        do {
            coordinator.settingsWatcher?.beginSelfWrite()
            try data.write(to: settingsManager.settingsPath, options: .atomic)
            coordinator.settingsWatcher?.endSelfWrite()
            diskContent = editorContent
            editorError = nil
            externalChangeWhileEditing = false
            coordinator.currentHealth = settingsManager.checkHealth()
        } catch {
            coordinator.settingsWatcher?.endSelfWrite()
            editorError = "保存失败: \(error.localizedDescription)"
        }
    }

    private func reloadFromDisk(resetEditor: Bool) {
        diskContent = readRawJSON()
        if resetEditor {
            editorContent = diskContent
            editorError = nil
        }
        externalChangeWhileEditing = false
        coordinator.currentHealth = settingsManager.checkHealth()
    }

    /// External change notification from SettingsWatcher.
    /// - If user has no draft, silently refresh both editor and diskContent.
    /// - Otherwise show a banner; user must click 重新加载 to discard their draft.
    private func handleExternalChange() {
        let latest = readRawJSON()
        if hasUnsavedChanges {
            // Don't stomp the user's draft. Just note the disk drift.
            if latest != diskContent {
                externalChangeWhileEditing = true
            }
            diskContent = latest
        } else {
            diskContent = latest
            editorContent = latest
            externalChangeWhileEditing = false
        }
        coordinator.currentHealth = settingsManager.checkHealth()
    }

    private func validateJSON(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            editorError = "编码错误"
            return
        }
        if (try? JSONSerialization.jsonObject(with: data)) != nil {
            editorError = nil
        } else {
            editorError = "JSON 格式无效"
        }
    }

    private func readRawJSON() -> String {
        let path = settingsManager.settingsPath
        guard FileManager.default.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path),
              let content = String(data: data, encoding: .utf8) else {
            return "{\n  \n}"
        }
        return content
    }
}
