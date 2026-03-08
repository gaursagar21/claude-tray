import Foundation

// MARK: - Session message

struct SessionMessage: Identifiable {
    let id: String          // uuid
    let parentId: String?   // parentUuid
    let role: Role
    let timestamp: Date
    let text: String        // concatenated text blocks
    let toolUses: [ToolUseBlock]
    let model: String?
    let isError: Bool

    enum Role { case user, assistant }

    struct ToolUseBlock: Identifiable {
        let id: String
        let name: String
        let inputJSON: String
    }
}

// MARK: - Conversation session

struct ConversationSession: Identifiable {
    let id: String              // sessionId
    let projectName: String     // human-readable from folder name
    let cwd: String
    let messages: [SessionMessage]
    let startTime: Date
    let lastActivity: Date

    var firstUserMessage: String {
        messages.first(where: { $0.role == .user })?.text ?? ""
    }

    var messageCount: Int { messages.count }
}

// MARK: - Parser

enum ConversationService {

    static func loadAllSessions() -> [ConversationSession] {
        let base = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")

        guard let projectDirs = try? FileManager.default
            .contentsOfDirectory(at: base, includingPropertiesForKeys: nil)
            .filter(\.hasDirectoryPath)
        else { return [] }

        var sessions: [ConversationSession] = []
        for dir in projectDirs {
            let projectName = humanizeProjectName(dir.lastPathComponent)
            guard let jsonlFiles = try? FileManager.default
                .contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
                .filter({ $0.pathExtension == "jsonl" })
            else { continue }

            for file in jsonlFiles {
                if let session = parseJSONL(at: file, projectName: projectName) {
                    sessions.append(session)
                }
            }
        }

        return sessions.sorted { $0.lastActivity > $1.lastActivity }
    }

    private static func parseJSONL(at url: URL, projectName: String) -> ConversationSession? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)

        var sessionId: String?
        var cwd: String = ""
        var messages: [SessionMessage] = []

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            let type = json["type"] as? String ?? ""
            guard type == "user" || type == "assistant" else { continue }

            let sid = json["sessionId"] as? String ?? ""
            if sessionId == nil && !sid.isEmpty { sessionId = sid }
            if cwd.isEmpty { cwd = json["cwd"] as? String ?? "" }

            let uuid = json["uuid"] as? String ?? UUID().uuidString
            let parentUuid = json["parentUuid"] as? String
            let tsStr = json["timestamp"] as? String ?? ""
            let timestamp = iso.date(from: tsStr) ?? Date.distantPast

            guard let msgDict = json["message"] as? [String: Any] else { continue }

            let role: SessionMessage.Role = type == "user" ? .user : .assistant
            let model = msgDict["model"] as? String
            let isError = (json["isApiErrorMessage"] as? Bool) == true

            let content = msgDict["content"]
            let (text, toolUses) = extractContent(content, role: role)

            // skip empty messages (e.g. pure thinking blocks)
            if text.isEmpty && toolUses.isEmpty && !isError { continue }

            messages.append(SessionMessage(
                id: uuid,
                parentId: parentUuid,
                role: role,
                timestamp: timestamp,
                text: text,
                toolUses: toolUses,
                model: model,
                isError: isError
            ))
        }

        guard let sid = sessionId, !messages.isEmpty else { return nil }
        let sorted = messages.sorted { $0.timestamp < $1.timestamp }
        return ConversationSession(
            id: sid,
            projectName: projectName,
            cwd: cwd,
            messages: sorted,
            startTime: sorted.first!.timestamp,
            lastActivity: sorted.last!.timestamp
        )
    }

    private static func extractContent(
        _ content: Any?,
        role: SessionMessage.Role
    ) -> (text: String, toolUses: [SessionMessage.ToolUseBlock]) {
        var textParts: [String] = []
        var toolUses: [SessionMessage.ToolUseBlock] = []

        if let str = content as? String {
            textParts.append(str)
        } else if let arr = content as? [[String: Any]] {
            for block in arr {
                let blockType = block["type"] as? String ?? ""
                switch blockType {
                case "text":
                    if let t = block["text"] as? String, !t.isEmpty {
                        textParts.append(t)
                    }
                case "tool_use":
                    let id   = block["id"]   as? String ?? UUID().uuidString
                    let name = block["name"] as? String ?? "unknown"
                    let inputJSON: String
                    if let inp = block["input"],
                       let d = try? JSONSerialization.data(withJSONObject: inp, options: [.prettyPrinted]),
                       let s = String(data: d, encoding: .utf8) {
                        inputJSON = s
                    } else { inputJSON = "{}" }
                    toolUses.append(SessionMessage.ToolUseBlock(id: id, name: name, inputJSON: inputJSON))
                case "tool_result":
                    break  // tool results are noise in user rows — shown via preceding tool_use chips
                default:
                    break  // skip thinking, etc.
                }
            }
        }

        return (textParts.joined(separator: "\n\n"), toolUses)
    }

    private static func humanizeProjectName(_ folderName: String) -> String {
        // "-Users-sagar-SagarGithub-claude-tray" → "claude-tray"
        let parts = folderName.split(separator: "-").map(String.init)
        // drop leading path segments (Users, username, etc.) — take last meaningful part(s)
        if let last = parts.last, last.count > 2 {
            // try to find a multi-part name like "claude-tray"
            let suffix = parts.suffix(2)
            let candidate = suffix.joined(separator: "-")
            if candidate.count > 4 { return candidate }
            return last
        }
        return folderName
    }
}

// MARK: - Session extensions

extension ConversationSession {
    /// Total steps including tool calls within messages
    var stepCount: Int {
        messages.reduce(0) { $0 + 1 + $1.toolUses.count }
    }
    var hasErrors: Bool {
        messages.contains { $0.isError }
    }
    var toolCount: Int {
        messages.reduce(0) { $0 + $1.toolUses.count }
    }
    /// Activity within last 5 minutes
    var isLive: Bool {
        Date().timeIntervalSince(lastActivity) < 300
    }
}

/// The currently selected step in the trace timeline.
enum SelectedStep {
    case message(SessionMessage)
    case toolUse(SessionMessage.ToolUseBlock, parent: SessionMessage)

    var stepId: String {
        switch self {
        case .message(let m):   return m.id
        case .toolUse(let t, _): return t.id
        }
    }
}
