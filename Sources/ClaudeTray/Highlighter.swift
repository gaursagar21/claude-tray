import AppKit
import SwiftUI

// MARK: - JSON syntax highlighting

// Pre-compiled regex patterns — compiling NSRegularExpression is expensive, do it once.
private let jsonRegexes: [(NSRegularExpression, Int, NSColor)] = {
    let patterns: [(String, Int, NSColor)] = [
        (#"\b-?\d+\.?\d*(?:[eE][+-]?\d+)?\b"#,           0, .systemOrange),
        (#"\b(true|false|null)\b"#,                        0, .systemPurple),
        (#"(\"(?:[^\"\\\\]|\\\\.)*\")\s*:"#,               1, .systemBlue),
        (#":\s*(\"(?:[^\"\\\\]|\\\\.)*\")"#,               1, .systemGreen),
        (#"^\s*(\"(?:[^\"\\\\]|\\\\.)*\"),?\s*$"#,         1, .systemGreen),
    ]
    return patterns.compactMap { (pat, group, color) in
        guard let rx = try? NSRegularExpression(pattern: pat, options: .anchorsMatchLines) else { return nil }
        return (rx, group, color)
    }
}()

func highlightedJSON(_ rawJSON: String) -> AttributedString {
    // Pretty-print if small enough to be worth it.
    let pretty: String
    if rawJSON.count < 150_000,
       let data = rawJSON.data(using: .utf8),
       let obj  = try? JSONSerialization.jsonObject(with: data),
       let pd   = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]),
       let s    = String(data: pd, encoding: .utf8) {
        pretty = s
    } else {
        pretty = rawJSON
    }

    // For very large strings skip syntax coloring — regex over 50KB is noticeably slow.
    guard pretty.count <= 40_000 else {
        var attr = AttributedString(pretty)
        attr.font = .init(NSFont.monospacedSystemFont(ofSize: 12, weight: .regular))
        return attr
    }

    let baseAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
        .foregroundColor: NSColor.labelColor
    ]
    let ns = NSMutableAttributedString(string: pretty, attributes: baseAttrs)
    let fullRange = NSRange(location: 0, length: (pretty as NSString).length)

    for (rx, group, color) in jsonRegexes {
        rx.enumerateMatches(in: pretty, range: fullRange) { m, _, _ in
            guard let m else { return }
            let r = group > 0 && m.numberOfRanges > group ? m.range(at: group) : m.range
            guard r.location != NSNotFound else { return }
            ns.addAttribute(.foregroundColor, value: color, range: r)
        }
    }

    return (try? AttributedString(ns, including: \.appKit)) ?? AttributedString(pretty)
}

// MARK: - SSE parsing

struct SSEResult {
    var text: String         // concatenated assistant text
    var inputTokens: Int
    var outputTokens: Int
    var cacheReadTokens: Int
    var stopReason: String?
    var model: String?
}

func parseSSE(_ raw: String) -> SSEResult {
    var text = ""
    var inputTokens  = 0
    var outputTokens = 0
    var cacheReadTokens = 0
    var stopReason: String?
    var model: String?

    for line in raw.components(separatedBy: "\n") {
        guard line.hasPrefix("data: ") else { continue }
        let jsonStr = String(line.dropFirst(6))
        guard let data = jsonStr.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String
        else { continue }

        switch type {
        case "message_start":
            if let msg = obj["message"] as? [String: Any] {
                model = msg["model"] as? String
                if let usage = msg["usage"] as? [String: Any] {
                    inputTokens     = usage["input_tokens"]      as? Int ?? 0
                    cacheReadTokens = usage["cache_read_input_tokens"] as? Int ?? 0
                }
            }
        case "content_block_delta":
            if let delta = obj["delta"] as? [String: Any],
               delta["type"] as? String == "text_delta",
               let chunk = delta["text"] as? String {
                text += chunk
            }
        case "message_delta":
            if let delta = obj["delta"] as? [String: Any] {
                stopReason = delta["stop_reason"] as? String
            }
            if let usage = obj["usage"] as? [String: Any] {
                outputTokens = usage["output_tokens"] as? Int ?? 0
            }
        default:
            break
        }
    }

    return SSEResult(text: text, inputTokens: inputTokens, outputTokens: outputTokens,
                     cacheReadTokens: cacheReadTokens, stopReason: stopReason, model: model)
}

// MARK: - SSE event list (for raw view)

struct SSEEvent: Identifiable {
    let id = UUID()
    let eventType: String
    let jsonString: String

    var highlighted: AttributedString { highlightedJSON(jsonString) }
}

func sseEvents(_ raw: String) -> [SSEEvent] {
    var events: [SSEEvent] = []
    var currentEvent = ""

    for line in raw.components(separatedBy: "\n") {
        if line.hasPrefix("event: ") {
            currentEvent = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data: ") {
            let json = String(line.dropFirst(6))
            if json != "[DONE]" {
                events.append(SSEEvent(eventType: currentEvent, jsonString: json))
            }
            currentEvent = ""
        }
    }
    return events
}

// MARK: - Chat message parsing

struct ChatMessage: Identifiable {
    enum Role { case system, user, assistant }
    let id = UUID()
    let role: Role
    let text: String
}

func parseChatMessages(requestBody: String, responseBody: String, isStreaming: Bool) -> [ChatMessage] {
    guard let data = requestBody.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [] }

    var messages: [ChatMessage] = []

    // System
    if let arr = json["system"] as? [[String: Any]] {
        let t = arr.compactMap { b -> String? in
            guard b["type"] as? String == "text" else { return nil }
            return b["text"] as? String
        }.joined(separator: "\n\n")
        if !t.isEmpty { messages.append(ChatMessage(role: .system, text: t)) }
    } else if let s = json["system"] as? String, !s.isEmpty {
        messages.append(ChatMessage(role: .system, text: s))
    }

    // Messages
    if let msgs = json["messages"] as? [[String: Any]] {
        for msg in msgs {
            let roleStr = msg["role"] as? String ?? "user"
            let text = extractContentText(msg["content"])
            let role: ChatMessage.Role = roleStr == "assistant" ? .assistant : .user
            if !text.isEmpty { messages.append(ChatMessage(role: role, text: text)) }
        }
    }

    // Assistant response
    let responseText: String
    if isStreaming {
        responseText = parseSSE(responseBody).text
    } else if let d = responseBody.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let content = j["content"] as? [[String: Any]] {
        responseText = content.compactMap { b -> String? in
            guard b["type"] as? String == "text" else { return nil }
            return b["text"] as? String
        }.joined(separator: "\n")
    } else {
        responseText = ""
    }
    if !responseText.isEmpty {
        messages.append(ChatMessage(role: .assistant, text: responseText))
    }

    return messages
}

func extractContentText(_ content: Any?) -> String {
    if let s = content as? String { return s }
    if let arr = content as? [[String: Any]] {
        return arr.compactMap { b -> String? in
            guard b["type"] as? String == "text" else { return nil }
            return b["text"] as? String
        }.joined(separator: "\n")
    }
    return ""
}

// MARK: - Model badge info

func modelBadge(from model: String) -> (badge: String, color: Color) {
    let lower = model.lowercased()
    if lower.contains("opus")   { return ("OPUS",   Color.purple) }
    if lower.contains("sonnet") { return ("SONNET", Color(red: 0.2, green: 0.6, blue: 1.0)) }
    if lower.contains("haiku")  { return ("HAIKU",  Color(red: 0.2, green: 0.78, blue: 0.65)) }
    return (String(model.prefix(6)).uppercased(), Color.secondary)
}
