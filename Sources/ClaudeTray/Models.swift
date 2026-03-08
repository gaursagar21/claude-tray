import Foundation

struct RequestLog: Identifiable, Hashable {
    static func == (lhs: RequestLog, rhs: RequestLog) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    let id: String
    let timestamp: Date
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let isStreaming: Bool
    let durationMs: Int
    let statusCode: Int

    // Precomputed at creation — never formatted in view body
    let displayTime: String
    let displayDate: String
    let displayDuration: String
    let shortModel: String

    var totalTokens: Int { inputTokens + outputTokens }

    init(id: String, timestamp: Date, model: String,
         inputTokens: Int, outputTokens: Int,
         isStreaming: Bool, durationMs: Int, statusCode: Int) {
        self.id = id
        self.timestamp = timestamp
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.isStreaming = isStreaming
        self.durationMs = durationMs
        self.statusCode = statusCode

        // Format once at init, not in every view render.
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm:ss"
        self.displayTime = tf.string(from: timestamp)

        let df = DateFormatter()
        df.dateFormat = "MMM d, HH:mm:ss"
        self.displayDate = df.string(from: timestamp)

        self.displayDuration = durationMs >= 1000
            ? String(format: "%.1fs", Double(durationMs) / 1000)
            : "\(durationMs)ms"

        self.shortModel = model
            .replacingOccurrences(of: "claude-", with: "")
            .components(separatedBy: "-")
            .prefix(3)
            .joined(separator: "-")
    }
}

// Raw body strings — fetched lazily from DB only when a request is selected.
struct RequestBodies: Sendable {
    let requestBody: String
    let responseBody: String
}
