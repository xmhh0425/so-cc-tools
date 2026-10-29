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

    /// “完成通知”延迟确认秒数：Stop 通知先挂起这么久，期间会话继续活动则撤销。0 表示立即通知。
    var stopNotifyDelaySeconds: Int {
        didSet { UserDefaults.standard.set(stopNotifyDelaySeconds, forKey: "stopNotifyDelaySeconds") }
    }

    /// 同一会话“已停下”通知的去重窗口（秒）：窗口内同一会话不再重复提醒。0 表示不去重。
    var stopNotifyDedupSeconds: Int {
        didSet { UserDefaults.standard.set(stopNotifyDedupSeconds, forKey: "stopNotifyDedupSeconds") }
    }

    /// 空闲提醒（Claude 空闲等待输入时也弹通知）。默认关：只在完成一轮回复时提醒。
    var idleNotificationEnabled: Bool {
        didSet { UserDefaults.standard.set(idleNotificationEnabled, forKey: "idleNotificationEnabled") }
    }

    /// 快速检测：盯住 transcript，一轮输出结束后几秒内提醒（Stop 钩子仍作兜底）。
    var fastTurnDetectionEnabled: Bool {
        didSet { UserDefaults.standard.set(fastTurnDetectionEnabled, forKey: "fastTurnDetectionEnabled") }
    }

    /// 前台是终端类应用时不提醒（避免打断正在看输出的你）。
    var terminalFocusSuppressesNotifications: Bool {
        didSet { UserDefaults.standard.set(terminalFocusSuppressesNotifications, forKey: "terminalFocusSuppressesNotifications") }
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
            "stopNotifyDelaySeconds": 120,
            "stopNotifyDedupSeconds": 90,
            "idleNotificationEnabled": false,
            "fastTurnDetectionEnabled": true,
            "terminalFocusSuppressesNotifications": true,
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
        self.stopNotifyDelaySeconds = defaults.integer(forKey: "stopNotifyDelaySeconds")
        self.stopNotifyDedupSeconds = defaults.integer(forKey: "stopNotifyDedupSeconds")
        self.idleNotificationEnabled = defaults.bool(forKey: "idleNotificationEnabled")
        self.fastTurnDetectionEnabled = defaults.bool(forKey: "fastTurnDetectionEnabled")
        self.terminalFocusSuppressesNotifications = defaults.bool(forKey: "terminalFocusSuppressesNotifications")
    }
}
