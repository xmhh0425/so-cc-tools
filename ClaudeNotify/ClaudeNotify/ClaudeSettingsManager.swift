import Foundation
import os.log

/// Manages Claude Code's ~/.claude/settings.json to install/uninstall HTTP hooks.
final class ClaudeSettingsManager {
    private let logger = Logger(subsystem: "com.claude-notify", category: "Settings")

    private var settingsPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("settings.json")
    }

    /// Check if our hook for the given event is installed.
    func isHookInstalled(event: HookEvent) -> Bool {
        guard let settings = readSettings(),
              let hooks = settings["hooks"] as? [String: Any],
              let eventHooks = hooks[event.rawValue] as? [[String: Any]] else {
            return false
        }

        return eventHooks.contains { group in
            guard let handlers = group["hooks"] as? [[String: Any]] else { return false }
            return handlers.contains { handler in
                guard let type = handler["type"] as? String,
                      let url = handler["url"] as? String else { return false }
                return type == "http" && url.contains("/hook/")
            }
        }
    }

    /// Install HTTP hooks for the given event into settings.json.
    func installHook(event: HookEvent, port: Int) throws {
        var settings = readSettings() ?? [:]
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        let hookPath: String
        switch event {
        case .stop: hookPath = "stop"
        case .notification: hookPath = "notification"
        case .stopFailure: hookPath = "stopfailure"
        }

        let hookEntry: [String: Any] = [
            "type": "http",
            "url": "http://127.0.0.1:\(port)/hook/\(hookPath)"
        ]
        let hookGroup: [String: Any] = [
            "matcher": "",
            "hooks": [hookEntry]
        ]

        // Check if we already have an entry for this event
        if var eventHooks = hooks[event.rawValue] as? [[String: Any]] {
            // Remove any existing ClaudeNotify hooks for this event
            eventHooks.removeAll { group in
                guard let handlers = group["hooks"] as? [[String: Any]] else { return false }
                return handlers.contains { handler in
                    (handler["url"] as? String)?.contains("/hook/") == true
                }
            }
            eventHooks.append(hookGroup)
            hooks[event.rawValue] = eventHooks
        } else {
            hooks[event.rawValue] = [hookGroup]
        }

        settings["hooks"] = hooks
        try writeSettings(settings)
        logger.info("Installed \(event.rawValue) hook on port \(port)")
    }

    /// Uninstall HTTP hooks for the given event.
    func uninstallHook(event: HookEvent) throws {
        guard var settings = readSettings(),
              var hooks = settings["hooks"] as? [String: Any],
              var eventHooks = hooks[event.rawValue] as? [[String: Any]] else {
            return
        }

        // Remove our hooks
        eventHooks.removeAll { group in
            guard let handlers = group["hooks"] as? [[String: Any]] else { return false }
            return handlers.contains { handler in
                (handler["url"] as? String)?.contains("/hook/") == true
            }
        }

        if eventHooks.isEmpty {
            hooks.removeValue(forKey: event.rawValue)
        } else {
            hooks[event.rawValue] = eventHooks
        }

        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }

        try writeSettings(settings)
        logger.info("Uninstalled \(event.rawValue) hook")
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
}
