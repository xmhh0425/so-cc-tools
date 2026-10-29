import Foundation
import os.log

/// 一轮结束的快速检测器。
///
/// 由 `UserPromptSubmit` 钩子喂入「某会话开始跑一轮」，随后按固定间隔轮询它的
/// transcript：一旦看到「最后一条助手输出是纯文本（不含 tool_use）」并且之后
/// 静默达到 `quietSeconds`，就判定这一轮结束并回调。
///
/// 与 Stop 钩子的关系：Stop 仍然保留为兜底（它要等 Claude Code 自身约 30 秒）；
/// 快速检测先报时会给会话打「已提醒」标记，兜底那条会被去重窗口挡掉。
///
/// 参照 Cindy 的做法（`apps/desktop/src/main/cc-debug-raw-tailer.ts`）：固定间隔
/// 轮询、按 offset 追加读取、单次读取有上限；但不靠“静默多久”硬猜完成，而是要求
/// 「最后一条助手输出是纯文本」这个正面信号，静默只用于确认没有后续记录。
///
/// 线程约定：只在主线程使用（钩子回调与定时器都在主线程）。
final class TranscriptWatcher: @unchecked Sendable {
    private struct Watched {
        var path: String
        var cwd: String?
        var offset: UInt64
        var candidateAt: Date?
        var firedForTurn: Bool
        var lastPromptID: String?
    }

    private var watched: [String: Watched] = [:]
    private var timer: Timer?
    private let pollInterval: TimeInterval = 1.5
    private let quietSeconds: TimeInterval = 4.0
    private let maxScanBytes = 2 * 1024 * 1024
    private let logger = Logger(subsystem: "com.cc-tools", category: "FastTurn")

    /// 触发前最后一道门（例如「前台是终端就不提醒」）。
    /// 返回 false 时不发通知，但仍打「已提醒」标记，避免兜底那条随后又冒出来。
    var shouldNotify: (() -> Bool)?
    /// 判定一轮结束时回调：(sessionID, transcriptPath, cwd)。
    var onTurnEnded: ((String, String, String?) -> Void)?

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// 由 UserPromptSubmit 调用：从当前位置开始盯这一轮。
    func startWatching(sessionID: String, transcriptPath: String, cwd: String?) {
        let size = Self.fileSize(transcriptPath) ?? 0
        watched[sessionID] = Watched(
            path: transcriptPath,
            cwd: cwd,
            offset: size,
            candidateAt: nil,
            firedForTurn: false,
            lastPromptID: nil
        )
        logger.info("开始快速检测：会话 \(sessionID, privacy: .public)")
    }

    func stopWatching(sessionID: String) {
        watched.removeValue(forKey: sessionID)
    }

    // MARK: - Private

    private func poll() {
        guard !watched.isEmpty else { return }
        for (sessionID, existing) in watched {
            var entry = existing

            if let size = Self.fileSize(entry.path), size > entry.offset,
               let handle = FileHandle(forReadingAtPath: entry.path) {
                defer { try? handle.close() }
                let toRead = min(size - entry.offset, UInt64(maxScanBytes))
                if (try? handle.seek(toOffset: entry.offset)) != nil,
                   let data = try? handle.read(upToCount: Int(toRead)) {
                    applyRecords(data, to: &entry)
                }
                entry.offset = size
            }

            if let candidateAt = entry.candidateAt, !entry.firedForTurn,
               Date().timeIntervalSince(candidateAt) >= quietSeconds {
                entry.firedForTurn = true
                if shouldNotify?() ?? true {
                    logger.info("快速检测判定一轮结束：会话 \(sessionID, privacy: .public)")
                    onTurnEnded?(sessionID, entry.path, entry.cwd)
                } else {
                    logger.info("快速检测命中，但前台在终端，跳过：会话 \(sessionID, privacy: .public)")
                }
            }

            watched[sessionID] = entry
        }
    }

    /// 逐条看新记录，判断这一轮是否还在进行。
    private func applyRecords(_ data: Data, to entry: inout Watched) {
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = obj["type"] as? String,
                  obj["isMeta"] as? Bool != true else { continue }

            switch type {
            case "user":
                // 带 promptId = 用户真的又发起了一轮；新一轮重新计数
                if let promptID = obj["promptId"] as? String, promptID != entry.lastPromptID {
                    entry.lastPromptID = promptID
                    entry.firedForTurn = false
                }
                // 工具结果等 user 记录说明这一轮还在跑
                entry.candidateAt = nil
            case "assistant":
                let blocks = ((obj["message"] as? [String: Any])?["content"] as? [[String: Any]]) ?? []
                let hasToolUse = blocks.contains { ($0["type"] as? String) == "tool_use" }
                let hasText = blocks.contains {
                    ($0["type"] as? String) == "text" && !(($0["text"] as? String) ?? "").isEmpty
                }
                if hasToolUse {
                    entry.candidateAt = nil      // 还要继续干活
                } else if hasText {
                    entry.candidateAt = Date()   // 像是一轮的最终输出，等一小段静默确认
                }
            default:
                break
            }
        }
    }

    private static func fileSize(_ path: String) -> UInt64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? NSNumber else { return nil }
        return size.uint64Value
    }
}
