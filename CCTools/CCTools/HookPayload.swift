import Foundation

/// Decodable model for Claude Code hook payloads.
/// All fields are optional — we decode leniently to handle any hook event.
struct HookPayload: Decodable {
    let hook_event_name: String?
    let session_id: String?
    let cwd: String?
    let transcript_path: String?
    /// 本轮用户输入的标识；Stop 事件也会带上，用来区分“新的用户输入”和本轮自己的记录。
    let prompt_id: String?

    // Notification-specific
    let message: String?
    let notification_type: String?

    // Stop-specific
    let stopReason: String?
    /// 触发 Stop 时仍在运行的后台任务 / 定时任务。非空表示 Claude 还会被唤醒
    /// 继续干活，“停止”不等于完成（Claude Code 提供这两个字段就是给 hook 做此判断）。
    let background_tasks: [LooseJSON]?
    let session_crons: [LooseJSON]?

    enum CodingKeys: String, CodingKey {
        case hook_event_name
        case session_id
        case cwd
        case transcript_path
        case prompt_id
        case message
        case notification_type
        case stopReason = "stop_reason"
        case background_tasks
        case session_crons
    }

    /// Claude 是否还在等后台任务把它唤醒。
    var hasActiveBackgroundWork: Bool {
        !(background_tasks ?? []).isEmpty || !(session_crons ?? []).isEmpty
    }
}

/// 只用于判断数组是否为空，内容一律忽略。
struct LooseJSON: Decodable {
    init(from decoder: Decoder) throws {}
}
