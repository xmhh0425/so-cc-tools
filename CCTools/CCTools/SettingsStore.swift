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

    var stopDuration: Int {
        didSet { UserDefaults.standard.set(stopDuration, forKey: "stopDuration") }
    }

    var notificationDuration: Int {
        didSet { UserDefaults.standard.set(notificationDuration, forKey: "notificationDuration") }
    }

    var stopFailureDuration: Int {
        didSet { UserDefaults.standard.set(stopFailureDuration, forKey: "stopFailureDuration") }
    }

    var configBrokenDuration: Int {
        didSet { UserDefaults.standard.set(configBrokenDuration, forKey: "configBrokenDuration") }
    }

    var autoFixOnDrift: Bool {
        didSet { UserDefaults.standard.set(autoFixOnDrift, forKey: "autoFixOnDrift") }
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
            "stopDuration": 60,
            "notificationDuration": 60,
            "stopFailureDuration": 60,
            "configBrokenDuration": 60,
            "autoFixOnDrift": false,
        ])

        self.port = defaults.integer(forKey: "port")
        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        self.soundEnabled = defaults.bool(forKey: "soundEnabled")
        self.floatingNotificationEnabled = defaults.bool(forKey: "floatingNotificationEnabled")
        self.systemNotificationEnabled = defaults.bool(forKey: "systemNotificationEnabled")
        self.maxHistoryDisplay = defaults.integer(forKey: "maxHistoryDisplay")
        self.stopDuration = defaults.integer(forKey: "stopDuration")
        self.notificationDuration = defaults.integer(forKey: "notificationDuration")
        self.stopFailureDuration = defaults.integer(forKey: "stopFailureDuration")
        self.configBrokenDuration = defaults.integer(forKey: "configBrokenDuration")
        self.autoFixOnDrift = defaults.bool(forKey: "autoFixOnDrift")
    }
}
