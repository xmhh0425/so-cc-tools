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
    private var pointerTimer: Timer?
    private var eventMonitors: [Any] = []
    private var cursorIsPointingHand = false
    private var wasLeftMouseDown = false
    private let closeHitArea = NSSize(width: 56, height: 48)

    private struct ScreenEntry {
        let window: NSWindow
        let viewModel: NotificationStackViewModel
        let hoverState: HoverState
    }

    init() {
        startPointerTracking()
        installPointerEventMonitors()
    }

    deinit {
        pointerTimer?.invalidate()
        eventMonitors.forEach(NSEvent.removeMonitor)
        NSCursor.arrow.set()
    }

    func show(event: HookEvent, message: String, project: String?) {
        let vm = FloatingNotificationViewModel(event: event, message: message, project: project)
        let duration = TimeInterval(UserDefaults.standard.integer(forKey: event.durationKey))

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for screen in NSScreen.screens {
                guard let id = screen.displayID else { continue }
                if let entry = self.stacks[id] {
                    self.addNotification(vm, duration: duration, to: entry.viewModel)
                } else {
                    self.createWindow(for: screen, id: id, initial: vm, duration: duration)
                }
            }
        }
    }

    // MARK: - Window creation

    private func createWindow(for screen: NSScreen, id: CGDirectDisplayID, initial vm: FloatingNotificationViewModel, duration: TimeInterval) {
        let stackVM = NotificationStackViewModel()
        addNotification(vm, duration: duration, to: stackVM)

        let hoverState = HoverState()
        let hosting = HoverTrackingHostingView(
            rootView: NotificationStackView(viewModel: stackVM)
                .environment(hoverState)
        )
        // AppKit still reports hover while the app is active; the manager's
        // pointer tracker below is the source of truth before activation.
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

    private func addNotification(
        _ vm: FloatingNotificationViewModel,
        duration: TimeInterval,
        to stackVM: NotificationStackViewModel
    ) {
        stackVM.addNotification(vm, duration: duration) { [weak self] id in
            self?.dismissNotification(id: id)
        }
    }

    // MARK: - Global pointer tracking

    private func startPointerTracking() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updatePointerState()
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
    }

    private func installPointerEventMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown]
        if let localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.updatePointerState(forceClick: event.type == .leftMouseDown)
            return event
        }) {
            eventMonitors.append(localMonitor)
        }

        if let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            DispatchQueue.main.async {
                self?.updatePointerState(forceClick: event.type == .leftMouseDown)
            }
        }) {
            eventMonitors.append(globalMonitor)
        }
    }

    private func updatePointerState(forceClick: Bool = false) {
        let mouse = NSEvent.mouseLocation
        var isOverCloseArea = false
        var clickedEntry: ScreenEntry?

        for entry in stacks.values {
            let isHoveringWindow = entry.window.isVisible && entry.window.frame.contains(mouse)
            setHovering(isHoveringWindow, for: entry.hoverState)
            let isHoveringClose = isHoveringWindow && closeArea(for: entry.window).contains(mouse)
            setCloseHovering(isHoveringClose, for: entry.hoverState)

            guard isHoveringClose else {
                continue
            }

            isOverCloseArea = true
            clickedEntry = entry
        }

        updateCursor(isOverCloseArea: isOverCloseArea)

        let isLeftMouseDown = (NSEvent.pressedMouseButtons & 1) == 1
        if (forceClick || (isLeftMouseDown && !wasLeftMouseDown)), let clickedEntry,
           let first = clickedEntry.viewModel.notifications.first {
            updateCursor(isOverCloseArea: false)
            dismissNotification(id: first.id)
        }
        wasLeftMouseDown = isLeftMouseDown
    }

    private func dismissNotification(id: FloatingNotificationViewModel.ID) {
        stacks.values.forEach { entry in
            entry.viewModel.dismiss(id: id)
        }
    }

    private func setHovering(_ isHovering: Bool, for hoverState: HoverState) {
        guard hoverState.isHovering != isHovering else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            hoverState.isHovering = isHovering
        }
    }

    private func setCloseHovering(_ isHovering: Bool, for hoverState: HoverState) {
        guard hoverState.isHoveringClose != isHovering else { return }
        withAnimation(.easeOut(duration: 0.10)) {
            hoverState.isHoveringClose = isHovering
        }
    }

    private func updateCursor(isOverCloseArea: Bool) {
        if isOverCloseArea {
            NSCursor.pointingHand.set()
            cursorIsPointingHand = true
        } else if cursorIsPointingHand {
            NSCursor.arrow.set()
            cursorIsPointingHand = false
        }
    }

    private func closeArea(for window: NSWindow) -> NSRect {
        let frame = window.frame
        return NSRect(
            x: frame.minX,
            y: frame.maxY - closeHitArea.height,
            width: closeHitArea.width,
            height: closeHitArea.height
        )
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
