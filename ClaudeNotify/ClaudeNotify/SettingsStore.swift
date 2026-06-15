import Foundation

/// App settings backed by UserDefaults.
@Observable
final class SettingsStore {
    var port: Int {
        didSet { UserDefaults.standard.set(port, forKey: "port") }
    }

    var launchAtLogin: Bool {
        didSet { UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin") }
    }

    var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }

    var floatingNotificationEnabled: Bool {
        didSet { UserDefaults.standard.set(floatingNotificationEnabled, forKey: "floatingNotificationEnabled") }
    }

    var systemNotificationEnabled: Bool {
        didSet { UserDefaults.standard.set(systemNotificationEnabled, forKey: "systemNotificationEnabled") }
    }

    var maxHistoryDisplay: Int {
        didSet { UserDefaults.standard.set(maxHistoryDisplay, forKey: "maxHistoryDisplay") }
    }

    init() {
        let defaults = UserDefaults.standard
        // Register defaults
        defaults.register(defaults: [
            "port": 18765,
            "launchAtLogin": false,
            "soundEnabled": true,
            "floatingNotificationEnabled": true,
            "systemNotificationEnabled": false,
            "maxHistoryDisplay": 20,
        ])

        self.port = defaults.integer(forKey: "port")
        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        self.soundEnabled = defaults.bool(forKey: "soundEnabled")
        self.floatingNotificationEnabled = defaults.bool(forKey: "floatingNotificationEnabled")
        self.systemNotificationEnabled = defaults.bool(forKey: "systemNotificationEnabled")
        self.maxHistoryDisplay = defaults.integer(forKey: "maxHistoryDisplay")
    }
}
