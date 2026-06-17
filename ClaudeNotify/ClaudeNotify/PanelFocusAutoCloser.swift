import AppKit

final class PanelFocusAutoCloser {
    private weak var panel: NSWindow?
    private let notificationCenter: NotificationCenter
    private let shouldIgnoreResignKey: () -> Bool
    private var resignKeyObserver: NSObjectProtocol?
    private var appDeactivateObserver: NSObjectProtocol?

    init(
        panel: NSWindow,
        notificationCenter: NotificationCenter = .default,
        shouldIgnoreResignKey: @escaping () -> Bool = { false }
    ) {
        self.panel = panel
        self.notificationCenter = notificationCenter
        self.shouldIgnoreResignKey = shouldIgnoreResignKey

        resignKeyObserver = notificationCenter.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: nil
        ) { [weak self] _ in
            guard let self, !self.shouldIgnoreResignKey() else { return }
            self.panel?.close()
        }

        appDeactivateObserver = notificationCenter.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.panel?.close()
        }
    }

    deinit {
        if let resignKeyObserver {
            notificationCenter.removeObserver(resignKeyObserver)
        }
        if let appDeactivateObserver {
            notificationCenter.removeObserver(appDeactivateObserver)
        }
    }
}
