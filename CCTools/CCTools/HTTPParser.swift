import Foundation

/// Minimal HTTP/1.1 request parser for localhost hook payloads.
struct HTTPRequest {
    let method: String
    let path: String
    let body: Data?
}

enum HTTPParser {
    /// Accumulate raw bytes until we have a complete request (headers + body).
    static func parseComplete(from accumulated: Data) -> HTTPRequest? {
        // Find the header/body separator
        guard let separatorRange = accumulated.range(of: Data("\r\n\r\n".utf8)) else {
            return nil  // headers not complete yet
        }

        let headerData = accumulated[accumulated.startIndex..<separatorRange.lowerBound]
        let afterSeparator = accumulated[separatorRange.upperBound...]

        // Parse request line + headers
        let headerString = String(decoding: headerData, as: UTF8.self)
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0])
        let path = String(parts[1])

        // Find Content-Length
        var contentLength = 0
        for line in lines.dropFirst() {
            if line.lowercased().hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count)
                contentLength = Int(value.trimmingCharacters(in: .whitespaces)) ?? 0
                break
            }
        }

        let bodyReceived = Data(afterSeparator)
        guard bodyReceived.count >= contentLength else {
            return nil  // body not complete yet
        }

        let body = contentLength > 0 ? bodyReceived.prefix(contentLength) : nil
        return HTTPRequest(method: method, path: path, body: body)
    }
}
