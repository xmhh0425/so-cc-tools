import SwiftUI
import AppKit

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        guard let desc = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        return desc.uint32Value
    }
}

/// Creates notification windows on demand per screen. Destroys them when empty.
final class FloatingNotificationManager {
    private var stacks: [CGDirectDisplayID: ScreenEntry] = [:]

    private struct ScreenEntry {
        let window: NSWindow
        let viewModel: NotificationStackViewModel
    }

    func show(event: HookEvent, message: String, project: String?) {
        let vm = FloatingNotificationViewModel(event: event, message: message, project: project)
        let duration = TimeInterval(UserDefaults.standard.integer(forKey: event.durationKey))

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for screen in NSScreen.screens {
                guard let id = screen.displayID else { continue }
                if let entry = self.stacks[id] {
                    entry.viewModel.addNotification(vm, duration: duration)
                } else {
                    self.createWindow(for: screen, id: id, initial: vm, duration: duration)
                }
            }
        }
    }

    private func createWindow(for screen: NSScreen, id: CGDirectDisplayID, initial vm: FloatingNotificationViewModel, duration: TimeInterval) {
        let stackVM = NotificationStackViewModel()
        stackVM.addNotification(vm, duration: duration)

        let hoverState = HoverState()
        let hosting = NSHostingView(
            rootView: NotificationStackView(viewModel: stackVM)
                .environment(hoverState)
        )

        let bannerWidth: CGFloat = 360
        let bannerMaxHeight: CGFloat = 300
        let menuBarHeight: CGFloat = 50
        let screenFrame = screen.frame

        let x = screenFrame.maxX - bannerWidth - 20
        let y = screenFrame.maxY - menuBarHeight - bannerMaxHeight

        let window = NSWindow(
            contentRect: NSRect(x: x, y: y, width: bannerWidth, height: bannerMaxHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isMovableByWindowBackground = false
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true

        hosting.postsFrameChangedNotifications = true
        var frameObserver: NSObjectProtocol?
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: hosting,
            queue: .main
        ) { [weak window, weak hosting] _ in
            guard let window, let hosting else { return }
            Self.fitWindowToContent(window: window, hosting: hosting, maxHeight: bannerMaxHeight)
        }
        DispatchQueue.main.async {
            Self.fitWindowToContent(window: window, hosting: hosting, maxHeight: bannerMaxHeight)
        }

        let entry = ScreenEntry(window: window, viewModel: stackVM)
        stacks[id] = entry

        window.orderFront(nil)

        stackVM.setOnEmpty { [weak self, weak stackVM] in
            guard let self else { return }
            if let frameObserver {
                NotificationCenter.default.removeObserver(frameObserver)
            }
            stackVM?.destroy()
            window.orderOut(nil)
            self.stacks.removeValue(forKey: id)
        }
    }

    private static func fitWindowToContent(window: NSWindow, hosting: NSHostingView<some View>, maxHeight: CGFloat) {
        let contentHeight = hosting.fittingSize.height
        guard contentHeight > 0 else { return }
        // Add bottom padding so the window doesn't clip the notification's
        // rounded corners and shadow at the bottom edge.
        let paddedHeight = contentHeight + 8
        let clampedHeight = min(paddedHeight, maxHeight)
        let topY = window.frame.maxY
        let newFrame = NSRect(
            x: window.frame.origin.x,
            y: topY - clampedHeight,
            width: window.frame.width,
            height: clampedHeight
        )
        if abs(newFrame.height - window.frame.height) > 1 {
            window.setFrame(newFrame, display: true, animate: false)
        }
    }
}
