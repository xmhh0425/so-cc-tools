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
    private var clickTap: Any? // CGEventTap for click detection

    private struct ScreenEntry {
        let window: NSWindow
        let viewModel: NotificationStackViewModel
        let hoverState: HoverState
    }

    init() {
        installClickTap()
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

    // MARK: - CGEventTap for global click detection

    private func installClickTap() {
        let mask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue)
        let ptr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: clickTapCallback,
            userInfo: ptr
        ) else {
            print("[ClaudeNotify] CGEventTap failed — grant Accessibility permission in System Settings → Privacy & Security → Accessibility")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        clickTap = tap
    }

    /// Called by the global CGEventTap callback when a click lands on a notification window.
    func handleClick(at point: NSPoint) {
        for entry in stacks.values {
            if entry.window.isVisible && entry.window.frame.contains(point) {
                if let first = entry.viewModel.notifications.first {
                    entry.viewModel.dismiss(first)
                }
                return
            }
        }
    }

    // MARK: - Window creation

    private func createWindow(for screen: NSScreen, id: CGDirectDisplayID, initial vm: FloatingNotificationViewModel, duration: TimeInterval) {
        let stackVM = NotificationStackViewModel()
        stackVM.addNotification(vm, duration: duration)

        let hoverState = HoverState()
        let hosting = HoverTrackingHostingView(
            rootView: NotificationStackView(viewModel: stackVM)
                .environment(hoverState)
        )
        // Event-driven hover: the × appears the instant the cursor enters the
        // banner, and disappears when it leaves — no polling, no focus needed.
        hosting.onHoverChange = { [weak hoverState] hovering in
            guard let hoverState else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                hoverState.isHovering = hovering
            }
        }

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

        hoverState.onDismiss = { [weak stackVM] in
            guard let stackVM, let first = stackVM.notifications.first else { return }
            stackVM.dismiss(first)
        }

        let entry = ScreenEntry(window: window, viewModel: stackVM, hoverState: hoverState)
        stacks[id] = entry

        // Resize window to fit SwiftUI content
        hosting.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
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

        window.orderFront(nil)

        stackVM.setOnEmpty { [weak self, weak stackVM] in
            guard let self else { return }
            // Restore the cursor in case the banner auto-dismissed while the
            // pointer was over the × button.
            NSCursor.arrow.set()
            stackVM?.destroy()
            window.orderOut(nil)
            self.stacks.removeValue(forKey: id)
        }
    }

    private static func fitWindowToContent(window: NSWindow, hosting: NSView, maxHeight: CGFloat) {
        let contentHeight = hosting.fittingSize.height
        guard contentHeight > 0 else { return }
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

// MARK: - Global CGEventTap callback (must not capture context)

private func clickTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        return Unmanaged.passRetained(event)
    }
    guard type == .leftMouseDown, let userInfo else {
        return Unmanaged.passRetained(event)
    }
    let manager = Unmanaged<FloatingNotificationManager>.fromOpaque(userInfo).takeUnretainedValue()

    let loc = event.location
    for screen in NSScreen.screens {
        let relX = loc.x - screen.frame.origin.x
        let relY = loc.y - screen.frame.origin.y
        guard relX >= 0, relX <= screen.frame.width,
              relY >= 0, relY <= screen.frame.height else { continue }
        let akPoint = NSPoint(x: relX, y: screen.frame.height - relY)
        DispatchQueue.main.async {
            manager.handleClick(at: akPoint)
        }
        return Unmanaged.passRetained(event)
    }
    return Unmanaged.passRetained(event)
}
