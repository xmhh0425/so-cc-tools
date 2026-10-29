import Foundation

/// Decodable model for Claude Code hook payloads.
/// All fields are optional — we decode leniently to handle any hook event.
struct HookPayload: Decodable {
    let hook_event_name: String?
    let session_id: String?
    let cwd: String?
    let transcript_path: String?

    // Notification-specific
    let message: String?

    // Stop-specific
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case hook_event_name
        case session_id
        case cwd
        case transcript_path
        case message
        case stopReason = "stop_reason"
    }
}
