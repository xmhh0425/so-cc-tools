import SwiftUI
import AppKit

/// Manages the lifecycle of the standalone management window (singleton).
final class ManagementWindowController {
    private var window: NSWindow?
    private weak var coordinator: AppCoordinator?
    private var managementView: ManagementView?

    init(coordinator: AppCoordinator?) {
        self.coordinator = coordinator
    }

    func setCoordinator(_ coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func showWindow(page: ManagementPage = .dashboard) {
        guard let coordinator else { return }

        if let window, window.isVisible {
            // Switch to requested page if provided
            managementView?.selectedPage = page
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let mv = ManagementView(coordinator: coordinator, selectedPage: page)
        self.managementView = mv

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Claude Code Tools"
        newWindow.minSize = NSSize(width: 640, height: 480)
        newWindow.center()
        newWindow.isReleasedWhenClosed = false

        newWindow.contentView = NSHostingView(rootView: mv)

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = newWindow
    }
}
