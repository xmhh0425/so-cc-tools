import Foundation
import os.log

/// “本轮完成”通知的延迟确认器。
///
/// Claude Code 的 Stop 钩子在每轮回复结束时都会触发（它自己已延后约 30 秒），
/// 但用户常常马上又继续对话，此时发“任务完成”通知没有意义。这里把 Stop 通知
/// 挂起一段时间再发：
///
/// - 等待期间同一会话出现新的用户输入（user 记录且 promptId 不同于本轮）→ 撤销；
/// - 同一会话又来了新的 Stop → 新的排定替换旧的；
/// - 同一会话在去重窗口内已通知过 → 跳过（窗口可配置，0 表示不去重）；
/// - 有挂起中的 Stop 时，同会话的 idle 提醒（“Claude 在等待输入”）让位给 Stop 通知。
///
/// 挂起状态只存在内存里，App 重启后丢失，最坏是少发一条通知，不影响正确性。
///
/// 线程约定：HTTPServer 已把钩子回调派发到主线程，因此状态只在主线程读写；
/// 延迟任务固定在主 actor 上恢复，和调用方、UI 调用保持同一线程。
final class StopNotificationDebouncer: @unchecked Sendable {
    /// session_id → 已排定的延迟通知任务
    private var pending: [String: Task<Void, Never>] = [:]
    /// session_id → 最近一次“已停下”通知（Stop 或 idle 提醒）的时间
    private var lastNotified: [String: Date] = [:]
    /// 单次追加扫描的上限；超过说明这段时间活动量很大，直接按“有活动”处理
    private let maxScanBytes = 4 * 1024 * 1024
    private let logger = Logger(subsystem: "com.cc-tools", category: "StopDebounce")

    /// 排定一条 Stop 通知：delay 秒后若会话没有继续活动，则调用 fire。
    /// dedupWindow 秒内同一会话已通知过则跳过。
    func schedule(
        sessionID: String,
        transcriptPath: String?,
        turnPromptID: String?,
        delay: TimeInterval,
        dedupWindow: TimeInterval,
        fire: @escaping () -> Void
    ) {
        // 同一会话的新 Stop 取代旧的排定
        pending[sessionID]?.cancel()

        let mark = Self.fileSize(at: transcriptPath)
        // 对照绝对截止时间分段等待：单个长 sleep 会被系统的定时器合并/节流推迟（实测 120 秒拖到 129 秒以上）
        let deadline = Date().addingTimeInterval(delay)
        pending[sessionID] = Task { @MainActor in
            while true {
                let remaining = deadline.timeIntervalSinceNow
                if remaining <= 0 { break }
                try? await Task.sleep(for: .seconds(min(remaining, 5)))
                if Task.isCancelled { return }
            }
            guard !Task.isCancelled else { return }
            self.pending[sessionID] = nil

            if self.hasNewUserPrompt(transcriptPath: transcriptPath, from: mark, excludingPromptID: turnPromptID) {
                self.logger.info("撤销 Stop 通知：会话 \(sessionID, privacy: .public) 出现了新的用户输入")
                return
            }
            if let last = self.lastNotified[sessionID], Date().timeIntervalSince(last) < dedupWindow {
                self.logger.info("跳过 Stop 通知：会话 \(sessionID, privacy: .public) 刚刚通知过")
                return
            }
            self.pruneNotified(within: dedupWindow)
            self.lastNotified[sessionID] = Date()
            fire()
        }
    }

    /// idle 提醒是否应该发出。有等待确认的 Stop 时让位给它；去重窗口内已通知过则跳过。
    /// 返回 true 表示应当发出，并记录本次通知。
    func shouldDeliverIdleNotification(sessionID: String, dedupWindow: TimeInterval) -> Bool {
        if pending[sessionID] != nil { return false }
        if let last = lastNotified[sessionID], Date().timeIntervalSince(last) < dedupWindow { return false }
        pruneNotified(within: dedupWindow)
        lastNotified[sessionID] = Date()
        return true
    }

    /// 快速检测路径已发出提醒：给会话打标记，让 Stop 兜底被去重窗口挡掉。
    func markNotified(sessionID: String, dedupWindow: TimeInterval) {
        pruneNotified(within: dedupWindow)
        lastNotified[sessionID] = Date()
    }

    /// 用户又开始输入（UserPromptSubmit）：撤销这一会话挂起中的 Stop 通知。
    func cancelPending(sessionID: String) {
        pending[sessionID]?.cancel()
        pending[sessionID] = nil
        logger.info("撤销挂起中的 Stop 通知：会话 \(sessionID, privacy: .public) 用户已开始新输入")
    }

    // MARK: - Private

    private func pruneNotified(within window: TimeInterval) {
        let cutoff = Date().addingTimeInterval(-window * 4)
        lastNotified = lastNotified.filter { $0.value > cutoff }
    }

    private static func fileSize(at path: String?) -> UInt64? {
        guard let path,
              let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? NSNumber else { return nil }
        return size.uint64Value
    }

    /// 从 mark 偏移起是否出现了「新的用户输入」。
    ///
    /// 只看 user 记录，并且要求它带一个不同于本轮 Stop 的 `promptId`：
    /// 本轮自己的助手记录/工具结果（可能晚于钩子才落盘）以及各类簿记记录
    /// （attachment、system、file-history-snapshot 等）都不会被误判为“继续活动”。
    private func hasNewUserPrompt(transcriptPath: String?, from mark: UInt64?, excludingPromptID: String?) -> Bool {
        guard let transcriptPath, let mark else { return false }
        guard let size = Self.fileSize(at: transcriptPath), size > mark else { return false }

        let appended = size - mark
        let toRead = min(appended, UInt64(maxScanBytes))
        guard let handle = FileHandle(forReadingAtPath: transcriptPath) else { return false }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: mark)) != nil,
              let data = try? handle.read(upToCount: Int(toRead)) else { return false }

        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  obj["type"] as? String == "user",
                  let promptID = obj["promptId"] as? String else { continue }
            if promptID != excludingPromptID { return true }
        }
        return false
    }
}
