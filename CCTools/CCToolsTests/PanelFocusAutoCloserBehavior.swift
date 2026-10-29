import AppKit

@main
struct PanelFocusAutoCloserBehavior {
    static func main() {
        let center = NotificationCenter()
        let panel = CountingPanel()
        let closer = PanelFocusAutoCloser(panel: panel, notificationCenter: center)

        center.post(name: NSWindow.didResignKeyNotification, object: panel)
        expectEqual(panel.closeCount, 1, "panel should close when it resigns key")

        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        expectEqual(panel.closeCount, 2, "panel should close when the app resigns active")

        withExtendedLifetime(closer) {}

        let ignoredPanel = CountingPanel()
        let ignoredCloser = PanelFocusAutoCloser(
            panel: ignoredPanel,
            notificationCenter: center,
            shouldIgnoreResignKey: { true }
        )

        center.post(name: NSWindow.didResignKeyNotification, object: ignoredPanel)
        expectEqual(ignoredPanel.closeCount, 0, "ignored resign key events should not close")

        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        expectEqual(ignoredPanel.closeCount, 1, "app deactivation should still close ignored panels")

        withExtendedLifetime(ignoredCloser) {}
    }

    private static func expectEqual(_ actual: Int, _ expected: Int, _ message: String) {
        precondition(actual == expected, "\(message): expected \(expected), got \(actual)")
    }
}

private final class CountingPanel: NSPanel {
    var closeCount = 0

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
    }

    override func close() {
        closeCount += 1
    }
}
