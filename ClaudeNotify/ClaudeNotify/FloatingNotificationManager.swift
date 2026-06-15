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

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for screen in NSScreen.screens {
                guard let id = screen.displayID else { continue }
                if let entry = self.stacks[id] {
                    entry.viewModel.addNotification(vm)
                } else {
                    self.createWindow(for: screen, id: id, initial: vm)
                }
            }
        }
    }

    private func createWindow(for screen: NSScreen, id: CGDirectDisplayID, initial vm: FloatingNotificationViewModel) {
        let stackVM = NotificationStackViewModel()
        stackVM.addNotification(vm)

        let hosting = NSHostingView(rootView: NotificationStackView(viewModel: stackVM))

        let bannerWidth: CGFloat = 360
        let bannerMaxHeight: CGFloat = 300
        let menuBarHeight: CGFloat = 25
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
        window.ignoresMouseEvents = true

        let entry = ScreenEntry(window: window, viewModel: stackVM)
        stacks[id] = entry

        window.orderFront(nil)

        // Weak capture of stackVM — breaks the retain cycle
        // stackVM → onEmptyRef → handler → [weak stackVM]
        stackVM.setOnEmpty { [weak self, weak stackVM] in
            guard let self else { return }
            stackVM?.destroy()
            window.orderOut(nil)
            // Do NOT call window.close() — it triggers dealloc during CA animation → crash
            // orderOut removes the window; stacks dictionary cleanup handles dealloc safely
            self.stacks.removeValue(forKey: id)
        }
    }
}
