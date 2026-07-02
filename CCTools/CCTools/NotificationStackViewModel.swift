import Foundation

/// Callback holder — keeps the closure outside @Observable to avoid deinit crashes.
final class OnEmptyHandler {
    var handler: (() -> Void)?
    init(_ handler: @escaping () -> Void) { self.handler = handler }
}

/// Manages a stack of floating notifications with independent auto-dismiss timers.
@Observable
final class NotificationStackViewModel {
    var notifications: [FloatingNotificationViewModel] = []

    private var onEmptyRef: OnEmptyHandler?

    func setOnEmpty(_ handler: @escaping () -> Void) {
        onEmptyRef = OnEmptyHandler(handler)
    }

    /// Call only from the main thread.
    func addNotification(
        _ vm: FloatingNotificationViewModel,
        duration: TimeInterval,
        onTimeout: ((FloatingNotificationViewModel.ID) -> Void)? = nil
    ) {
        notifications.insert(vm, at: 0)
        let id = vm.id

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            if let onTimeout {
                DispatchQueue.main.async {
                    onTimeout(id)
                }
            } else {
                self?.dismiss(id: id)
            }
        }
    }

    func dismiss(_ vm: FloatingNotificationViewModel) {
        dismiss(id: vm.id)
    }

    func dismiss(id: FloatingNotificationViewModel.ID) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.notifications.removeAll { $0.id == id }
            if self.notifications.isEmpty {
                self.onEmptyRef?.handler?()
            }
        }
    }

    /// Safely break all references before the window is destroyed.
    /// Must be called BEFORE window.orderOut/close to avoid use-after-free.
    func destroy() {
        onEmptyRef = nil
        notifications.removeAll()
    }
}
