import Foundation
import os.log

/// Unified representation of a hook entry, covering both HTTP and command types.
struct HookConfig: Identifiable {
    let event: String       // e.g. "Stop", "Notification", "PreToolUse"
    let matcher: String     // e.g. "" or "Skill" or ".*"
    let type: HookType      // .http or .command
    let target: String      // URL for HTTP, script path for command

    enum HookType: String {
        case http
        case command
    }

    var id: String { "\(event)-\(target)" }

    /// Whether this hook is managed by this project (for display grouping).
    var isProjectHook: Bool {
        target.contains("so-cc-tools") || target.contains("claude-tools") || target.contains("ClaudeNotify")
    }

    /// Extract a short display name from the target (e.g. script filename).
    var shortTarget: String {
        if type == .http {
            return "ClaudeNotify"
        }
        return URL(fileURLWithPath: target.replacingOccurrences(of: "bash ", with: "")).lastPathComponent
    }
}

/// Full representation of the statusLine configuration.
struct StatusLineConfig {
    var enabled: Bool
    var command: String
    var refreshInterval: Int
}

/// One unit of config this tool manages.
struct ManagedHookSpec: Identifiable {
    let id: String              // script filename used for dedup: "notify-claude-notify.sh", etc.
    let event: String           // "Stop", "PreToolUse", ...
    let matcher: String         // "", "Skill", ".*"
    let isNotificationHook: Bool
    let displayName: String
}

/// Health status of the managed configuration.
struct ConfigHealth {
    struct Item: Identifiable {
        let id: String
        let event: String
        let label: String
        let isPresent: Bool
        let encoding: String?   // "http", "command", or nil
    }
    let items: [Item]
    let statusLinePresent: Bool

    var isHealthy: Bool {
        items.allSatisfy(\.isPresent) && statusLinePresent
    }

    var missingCount: Int {
        items.filter { !$0.isPresent }.count + (statusLinePresent ? 0 : 1)
    }

    /// Stable signature for edge-triggered transition detection.
    var signature: String {
        items.map { "\($0.event):\($0.isPresent ? 1 : 0)" }.joined(separator: ",")
            + "|sl:\(statusLinePresent ? 1 : 0)"
    }
}

/// Manages the full ~/.claude/settings.json: hooks, statusLine, and all other fields.
/// Preserves unknown fields — only touches what it understands.
final class SettingsManager {
    private let logger = Logger(subsystem: "com.claude-notify", category: "SettingsManager")

    /// Canonical list of hooks managed by this tool. Single source of truth.
    static let managedSpecs: [ManagedHookSpec] = [
        ManagedHookSpec(id: "notify-claude-notify.sh", event: "Stop", matcher: "", isNotificationHook: true, displayName: "Stop（任务完成）"),
        ManagedHookSpec(id: "notify-claude-notify.sh", event: "Notification", matcher: "", isNotificationHook: true, displayName: "Notification（等待输入）"),
        ManagedHookSpec(id: "notify-claude-notify.sh", event: "StopFailure", matcher: "", isNotificationHook: true, displayName: "StopFailure（API 错误）"),
        ManagedHookSpec(id: "hook-pre-skill.sh", event: "PreToolUse", matcher: "Skill", isNotificationHook: false, displayName: "PreToolUse（Skill 追踪）"),
        ManagedHookSpec(id: "hook-skill-tracker.sh", event: "UserPromptExpansion", matcher: ".*", isNotificationHook: false, displayName: "UserPromptExpansion（命令追踪）"),
    ]

    /// Public path for SettingsWatcher access.
    var settingsPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("settings.json")
    }

    /// Weak reference to watcher for self-write suppression.
    weak var watcher: SettingsWatcher?

    // MARK: - Read

    func readAllHooks() -> [HookConfig] {
        guard let settings = readSettings(),
              let hooks = settings["hooks"] as? [String: Any] else {
            return []
        }

        var result: [HookConfig] = []
        for (event, groups) in hooks {
            guard let groupList = groups as? [[String: Any]] else { continue }
            for group in groupList {
                let matcher = group["matcher"] as? String ?? ""
                guard let handlers = group["hooks"] as? [[String: Any]] else { continue }
                for handler in handlers {
                    if let url = handler["url"] as? String, handler["type"] as? String == "http" {
                        result.append(HookConfig(event: event, matcher: matcher, type: .http, target: url))
                    } else if let command = handler["command"] as? String, handler["type"] as? String == "command" {
                        result.append(HookConfig(event: event, matcher: matcher, type: .command, target: command))
                    }
                }
            }
        }
        return result
    }

    func readStatusLine() -> StatusLineConfig? {
        guard let settings = readSettings(),
              let sl = settings["statusLine"] as? [String: Any] else {
            return nil
        }
        return StatusLineConfig(
            enabled: true,
            command: sl["command"] as? String ?? "",
            refreshInterval: sl["refreshInterval"] as? Int ?? 5
        )
    }

    func readFullSettings() -> [String: Any]? {
        return readSettings()
    }

    func isHookInstalled(event: String, type: HookConfig.HookType? = nil, targetContains: String? = nil) -> Bool {
        let hooks = readAllHooks()
        return hooks.contains { hook in
            hook.event == event
                && (type == nil || hook.type == type)
                && (targetContains == nil || hook.target.contains(targetContains!))
        }
    }

    // MARK: - Health Check

    /// Check health of all managed config items. Accepts BOTH http and command encodings.
    func checkHealth() -> ConfigHealth {
        let hooks = readAllHooks()
        let slPresent = readStatusLine() != nil

        let items: [ConfigHealth.Item] = Self.managedSpecs.map { spec in
            let matching = hooks.first { h in
                h.event == spec.event && (
                    (h.type == .http && h.target.contains("/hook/"))
                    || (h.type == .command && h.target.contains(spec.id))
                )
            }
            return ConfigHealth.Item(
                id: spec.id,
                event: spec.event,
                label: spec.displayName,
                isPresent: matching != nil,
                encoding: matching?.type.rawValue
            )
        }

        return ConfigHealth(items: items, statusLinePresent: slPresent)
    }

    // MARK: - Repair

    /// Native one-click fix: backup, resolve repo path, install missing hooks + statusLine.
    func repairManaged() throws {
        try backupSettings()
        let existing = readAllHooks()
        let repoBase = Self.resolveRepoBase(from: existing)

        // statusLine
        let existingSL = readStatusLine()
        let slCommand = existingSL?.command.isEmpty == false
            ? existingSL!.command
            : "bash \(repoBase)/statusline/statusline.sh"
        let slInterval = existingSL?.refreshInterval ?? 5
        try setStatusLine(StatusLineConfig(enabled: true, command: slCommand, refreshInterval: slInterval))

        // notification hooks — only add if missing
        let health = checkHealth()
        let notifyTarget = "bash \(repoBase)/notify/notify-claude-notify.sh"
        for item in health.items where item.event != "PreToolUse" && item.event != "UserPromptExpansion" {
            if !item.isPresent {
                try ensureHook(HookConfig(event: item.event, matcher: "", type: .command, target: notifyTarget))
            }
        }

        // statusline command hooks
        let preskillTarget = "bash \(repoBase)/statusline/hook-pre-skill.sh"
        let trackerTarget = "bash \(repoBase)/statusline/hook-skill-tracker.sh"

        let preskillPresent = health.items.first { $0.event == "PreToolUse" }?.isPresent ?? false
        if !preskillPresent {
            try ensureHook(HookConfig(event: "PreToolUse", matcher: "Skill", type: .command, target: preskillTarget))
        }

        let trackerPresent = health.items.first { $0.event == "UserPromptExpansion" }?.isPresent ?? false
        if !trackerPresent {
            try ensureHook(HookConfig(event: "UserPromptExpansion", matcher: ".*", type: .command, target: trackerTarget))
        }

        logger.info("repairManaged completed")
    }

    /// Resolve the repo base directory from existing hooks or candidate paths.
    static func resolveRepoBase(from hooks: [HookConfig]) -> String {
        // Try to find from existing hook targets
        for hook in hooks {
            if hook.type == .command && hook.target.contains("so-cc-tools") {
                let scriptPath = hook.target.replacingOccurrences(of: "bash ", with: "")
                let scriptURL = URL(fileURLWithPath: scriptPath)
                // Walk up from script to repo root (script is in statusline/ or notify/)
                let repo = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
                return repo.path
            }
        }

        // Fallback: candidate paths
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/AI/so-cc-tools",
            "\(home)/AI/claude-tools",
        ]
        for candidate in candidates {
            if FileManager.default.fileExists(atPath: "\(candidate)/fix-settings.sh") {
                return candidate
            }
        }

        // Last resort
        return "\(home)/AI/so-cc-tools"
    }

    // MARK: - Write

    func ensureHook(_ config: HookConfig) throws {
        var settings = readSettings() ?? [:]
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        let hookEntry: [String: Any]
        switch config.type {
        case .http:
            hookEntry = ["type": "http", "url": config.target]
        case .command:
            hookEntry = ["type": "command", "command": config.target]
        }

        let hookGroup: [String: Any] = [
            "matcher": config.matcher,
            "hooks": [hookEntry]
        ]

        let dedupId = Self.dedupIdentifier(from: config.target)

        if var eventHooks = hooks[config.event] as? [[String: Any]] {
            eventHooks.removeAll { group in
                guard let handlers = group["hooks"] as? [[String: Any]] else { return false }
                return handlers.contains { handler in
                    let existing = (handler["url"] as? String) ?? (handler["command"] as? String) ?? ""
                    return Self.dedupIdentifier(from: existing) == dedupId
                }
            }
            eventHooks.append(hookGroup)
            hooks[config.event] = eventHooks
        } else {
            hooks[config.event] = [hookGroup]
        }

        settings["hooks"] = hooks
        try writeSettings(settings)
        logger.info("Ensured hook: \(config.event) → \(config.target)")
    }

    func uninstallHook(event: String, targetContains: String) throws {
        guard var settings = readSettings(),
              var hooks = settings["hooks"] as? [String: Any],
              var eventHooks = hooks[event] as? [[String: Any]] else {
            return
        }

        let dedupId = Self.dedupIdentifier(from: targetContains)

        eventHooks.removeAll { group in
            guard let handlers = group["hooks"] as? [[String: Any]] else { return false }
            return handlers.contains { handler in
                let existing = (handler["url"] as? String) ?? (handler["command"] as? String) ?? ""
                return Self.dedupIdentifier(from: existing) == dedupId
            }
        }

        if eventHooks.isEmpty {
            hooks.removeValue(forKey: event)
        } else {
            hooks[event] = eventHooks
        }

        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }

        try writeSettings(settings)
        logger.info("Uninstalled hook: \(event) containing \(targetContains)")
    }

    func setStatusLine(_ config: StatusLineConfig?) throws {
        var settings = readSettings() ?? [:]

        if let config {
            settings["statusLine"] = [
                "type": "command",
                "command": config.command,
                "refreshInterval": config.refreshInterval
            ]
        } else {
            settings.removeValue(forKey: "statusLine")
        }

        try writeSettings(settings)
        logger.info("StatusLine \(config != nil ? "enabled" : "disabled")")
    }

    // MARK: - Backup

    func backupSettings() throws {
        let bakPath = settingsPath.appendingPathExtension("bak")
        let fm = FileManager.default
        if fm.fileExists(atPath: settingsPath.path) {
            if fm.fileExists(atPath: bakPath.path) {
                try fm.removeItem(at: bakPath)
            }
            try fm.copyItem(at: settingsPath, to: bakPath)
            logger.info("Backup created: \(bakPath.path)")
        }
    }

    // MARK: - Private

    private func readSettings() -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: settingsPath.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: settingsPath)
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            logger.error("Failed to read settings: \(error)")
            return nil
        }
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        watcher?.beginSelfWrite()
        defer { watcher?.endSelfWrite() }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsPath, options: .atomic)
    }

    static func dedupIdentifier(from target: String) -> String {
        let cleaned = target.replacingOccurrences(of: "bash ", with: "")
        return URL(fileURLWithPath: cleaned).lastPathComponent
    }
}
