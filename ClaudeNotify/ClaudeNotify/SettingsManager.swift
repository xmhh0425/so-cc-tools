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
            // "http://127.0.0.1:18765/hook/stop" → "ClaudeNotify"
            return "ClaudeNotify"
        }
        // "bash /path/to/hook-pre-skill.sh" → "hook-pre-skill.sh"
        return URL(fileURLWithPath: target.replacingOccurrences(of: "bash ", with: "")).lastPathComponent
    }
}

/// Full representation of the statusLine configuration.
struct StatusLineConfig {
    var enabled: Bool
    var command: String
    var refreshInterval: Int
}

/// Manages the full ~/.claude/settings.json: hooks, statusLine, and all other fields.
/// Preserves unknown fields — only touches what it understands.
final class SettingsManager {
    private let logger = Logger(subsystem: "com.claude-notify", category: "SettingsManager")

    private var settingsPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("settings.json")
    }

    // MARK: - Read

    /// Read all hooks from settings.json, returned as typed configs.
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

    /// Read the statusLine configuration.
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

    /// Read the full settings as a dictionary (for the editor view).
    func readFullSettings() -> [String: Any]? {
        return readSettings()
    }

    /// Check if a specific hook event has any entry.
    func isHookInstalled(event: String, type: HookConfig.HookType? = nil, targetContains: String? = nil) -> Bool {
        let hooks = readAllHooks()
        return hooks.contains { hook in
            hook.event == event
                && (type == nil || hook.type == type)
                && (targetContains == nil || hook.target.contains(targetContains!))
        }
    }

    // MARK: - Write

    /// Install a hook idempotently. Removes existing entries for the same event
    /// that match by script filename (dedup), then appends the new entry.
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

        // Dedup: remove existing entries that match by script filename
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

    /// Uninstall hooks matching the given event + target dedup identifier.
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

    /// Install or remove the statusLine configuration.
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

    /// Create a .bak copy of settings.json before making changes.
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
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsPath, options: .atomic)
    }

    /// Extract the filename from a target string for dedup comparison.
    /// E.g. "bash /Users/sofun/AI/so-cc-tools/notify/notify-claude-notify.sh"
    ///      → "notify-claude-notify.sh"
    /// "http://127.0.0.1:18765/hook/stop" → "hook/stop"
    static func dedupIdentifier(from target: String) -> String {
        let cleaned = target.replacingOccurrences(of: "bash ", with: "")
        return URL(fileURLWithPath: cleaned).lastPathComponent
    }
}
