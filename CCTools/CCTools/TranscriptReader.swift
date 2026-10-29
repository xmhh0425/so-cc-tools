import Foundation

/// Reads the Claude Code transcript to extract the last user message.
enum TranscriptReader {

    /// Extract the last real user message from a transcript JSONL file.
    /// This is what the user asked Claude to do — most useful for notifications.
    ///
    /// Transcript 里不只有真实对话：CC 还会写入 `api-request-blob` 调试记录（同样带
    /// `message.role == "user"`，内容是注入过 system-reminder 的完整请求），以及
    /// slash 命令 / skill 展开出来的注入文本、带 `isMeta` 的注入记录（例如粘贴图片
    /// 时额外写入的 `[Image: source: …]` 占位）。它们都不能当作“用户说了什么”，需要
    /// 逐条过滤；全部过滤后返回 nil，由调用方使用兜底文案。
    static func lastUserMessage(from path: String?) -> String? {
        guard let path else { return nil }

        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else { return nil }

        let lines = String(decoding: data, as: UTF8.self)
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }

        for line in lines.reversed() {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  // 只认真正的会话记录，跳过 api-request-blob 之类的调试记录
                  obj["type"] as? String == "user",
                  // 跳过 CC 注入的 meta 记录（图片占位、命令回显等）
                  obj["isMeta"] as? Bool != true,
                  let message = obj["message"] as? [String: Any],
                  message["role"] as? String == "user",
                  let text = plainText(from: message["content"]) else { continue }

            let cleaned = stripInjectedBlocks(text)
            guard !isInjectionOnly(cleaned) else { continue }

            // 清洗后可能什么都不剩（例如整条只是图片/路径占位），继续往前找
            let preview = truncate(cleaned, maxLength: 120)
            guard !preview.isEmpty else { continue }

            return preview
        }

        return nil
    }

    // MARK: - Injection handling

    /// 取出消息里的纯文本（字符串内容或 text 块；tool_result 等块忽略）。
    private static func plainText(from content: Any?) -> String? {
        if let text = content as? String, !text.isEmpty {
            return text
        }
        if let blocks = content as? [[String: Any]] {
            let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                .joined(separator: " ")
            return text.isEmpty ? nil : text
        }
        return nil
    }

    /// 剥掉 CC 注入的 XML 片段（system-reminder、slash 命令回显等）。
    private static func stripInjectedBlocks(_ text: String) -> String {
        var result = text
        for tag in ["system-reminder", "command-name", "command-message",
                    "local-command-caveat", "local-command-stdout"] {
            result = result.replacingOccurrences(
                of: "<\(tag)>[\\s\\S]*?</\(tag)>",
                with: " ",
                options: .regularExpression
            )
        }
        return result
    }

    /// 剥掉注入片段后是否已不剩有效内容，或整条本身就是注入文本。
    private static func isInjectionOnly(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        // skill 展开文本没有 XML 包裹，用固定前缀识别
        return trimmed.hasPrefix("Base directory for this skill:")
    }

    private static func truncate(_ text: String, maxLength: Int) -> String {
        let cleaned = text
            // Remove code blocks
            .replacingOccurrences(of: "```[\\s\\S]*?```", with: " ", options: .regularExpression)
            // Remove inline code
            .replacingOccurrences(of: "`[^`]+`", with: " ", options: .regularExpression)
            // Remove bold/italic markers
            .replacingOccurrences(of: "\\*\\*?([^*]+)\\*\\*?", with: "$1", options: .regularExpression)
            // Remove image references: [Image #N], [Image: source: ...], [image]
            .replacingOccurrences(of: "\\[Image\\s*#?\\d*\\s*:?.*?\\]", with: " ", options: .regularExpression)
            // Remove absolute file paths
            .replacingOccurrences(of: "/[\\w.\\-]+/[\\w.\\-/]+", with: " ", options: .regularExpression)
            // Remove standalone filenames
            .replacingOccurrences(of: "\\b[A-Z][\\w]*\\.(swift|plist|json|md|txt|sh|py|js|ts|rb|go|rs|icns|png|jpg)\\b", with: " ", options: .regularExpression)
            // Collapse multiple spaces
            .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.count <= maxLength { return cleaned }
        return String(cleaned.prefix(maxLength)) + "…"
    }
}
