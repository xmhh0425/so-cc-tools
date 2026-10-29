import Foundation

/// Simple view model for a single floating notification banner.
@Observable
final class FloatingNotificationViewModel: Identifiable {
    let id = UUID()
    let event: HookEvent
    let message: String
    let project: String?
    let timestamp: Date

    init(event: HookEvent, message: String, project: String?) {
        self.event = event
        self.message = message
        self.project = project
        self.timestamp = Date()
    }
}
