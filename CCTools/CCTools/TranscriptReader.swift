import Foundation

/// Reads the Claude Code transcript to extract the last assistant message.
enum TranscriptReader {

    /// Extract the last user message from a transcript JSONL file.
    /// This is what the user asked Claude to do — most useful for notifications.
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
                  let message = obj["message"] as? [String: Any],
                  message["role"] as? String == "user" else { continue }

            let content = message["content"]

            // Plain string
            if let text = content as? String, !text.isEmpty {
                return truncate(text, maxLength: 120)
            }

            // Array of blocks — join all text blocks
            if let blocks = content as? [[String: Any]] {
                let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                    .joined(separator: " ")
                if !text.isEmpty { return truncate(text, maxLength: 120) }
            }
        }

        return nil
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
