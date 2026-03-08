import SwiftUI

struct InspectorView: View {
    let req: RequestLog
    let bodies: RequestBodies?
    @State private var tab: Tab = .overview

    enum Tab: String, CaseIterable {
        case overview = "Overview"
        case request  = "Request"
        case response = "Response"
        case tokens   = "Tokens"
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            tabContent
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 1) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button(t.rawValue) { tab = t }
                    .buttonStyle(InspectorTabStyle(active: tab == t))
            }
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.bar)
    }

    // MARK: - Content

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .overview: OverviewTab(req: req)
        case .request:  bodyTab(bodies?.requestBody)
        case .response: responseTab
        case .tokens:   TokensTab(req: req)
        }
    }

    @ViewBuilder
    private func bodyTab(_ text: String?) -> some View {
        if let text {
            JSONCodeView(rawJSON: text)
        } else {
            loadingPlaceholder
        }
    }

    @ViewBuilder
    private var responseTab: some View {
        if let b = bodies {
            ResponseTab(req: req, bodies: b)
        } else {
            loadingPlaceholder
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 8) {
            Spacer()
            ProgressView()
            Text("Loading…")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Overview tab

private struct OverviewTab: View {
    let req: RequestLog

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Model hero
                modelHero
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                Divider().padding(.horizontal, 14)

                // Metrics grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 0) {
                    metricCell("LATENCY",   value: req.displayDuration)
                    metricCell("STATUS",    value: "\(req.statusCode)",
                               valueColor: req.statusCode < 300 ? .green : .red)
                    metricCell("STREAMING", value: req.isStreaming ? "Yes" : "No")
                    metricCell("DATE",      value: req.displayDate)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                Divider().padding(.horizontal, 14)

                // Token summary
                VStack(alignment: .leading, spacing: 10) {
                    Text("TOKENS")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .tracking(1)
                    tokenRow("Input",  req.inputTokens,  color: .purple)
                    tokenRow("Output", req.outputTokens, color: Color(red: 0.2, green: 0.6, blue: 1))
                    tokenRow("Total",  req.totalTokens,  color: .secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
    }

    private var modelHero: some View {
        let (badge, color) = modelBadge(from: req.model)
        return HStack(spacing: 10) {
            // Badge pill
            Text(badge)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    LinearGradient(colors: [color, color.opacity(0.7)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 1) {
                Text(req.model)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("ID: \(req.id)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.quaternary)
            }
        }
    }

    @ViewBuilder
    private func metricCell(_ label: String, value: String, valueColor: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.8)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(valueColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func tokenRow(_ label: String, _ count: Int, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            Text("\(count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(count > 0 ? color : Color.secondary.opacity(0.4))
                .monospacedDigit()
        }
    }
}

// MARK: - Response tab

private struct ResponseTab: View {
    let req: RequestLog
    let bodies: RequestBodies
    @State private var showRaw = false

    var body: some View {
        VStack(spacing: 0) {
            if req.isStreaming {
                HStack {
                    Spacer()
                    Toggle("Raw SSE", isOn: $showRaw)
                        .toggleStyle(.button)
                        .controlSize(.mini)
                        .font(.system(size: 10))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .background(.bar)
                Divider()
            }
            if req.isStreaming && !showRaw {
                SSEProseView(raw: bodies.responseBody)
            } else if req.isStreaming && showRaw {
                SSEEventsView(raw: bodies.responseBody)
            } else {
                JSONCodeView(rawJSON: bodies.responseBody)
            }
        }
    }
}

// MARK: - SSE prose view

private struct SSEProseView: View {
    let raw: String
    private var result: SSEResult { parseSSE(raw) }

    var body: some View {
        let r = result
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if r.text.isEmpty {
                    Text("No text content (may be tool-use only)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(14)
                } else {
                    Text(r.text)
                        .font(.system(size: 13))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider().padding(.horizontal, 14)
                // Footer stats
                HStack(spacing: 14) {
                    if r.inputTokens > 0  { usageStat("In",    "\(r.inputTokens)") }
                    if r.outputTokens > 0 { usageStat("Out",   "\(r.outputTokens)") }
                    if let s = r.stopReason { usageStat("Stop", s) }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private func usageStat(_ label: String, _ val: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.8)
            Text(val)
                .font(.system(size: 11, design: .monospaced))
        }
    }
}

// MARK: - SSE events view

private struct SSEEventsView: View {
    let raw: String
    // Computed once in a background task, not on every render.
    @State private var events: [SSEEvent] = []

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(events) { evt in
                    SSEEventRow(event: evt)
                    Divider().opacity(0.4)
                }
            }
        }
        .task(id: raw) {
            let r = raw
            let computed = await Task.detached(priority: .userInitiated) {
                sseEvents(r)
            }.value
            events = computed
        }
    }
}

private struct SSEEventRow: View {
    let event: SSEEvent
    @State private var expanded = false
    // Highlight on demand, not on every render.
    @State private var highlighted: AttributedString?

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.12)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)
                    Text(event.eventType.isEmpty ? "data" : event.eventType)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(eventTypeColor(event.eventType))
                        .frame(width: 160, alignment: .leading)
                    Text(eventSummary)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Group {
                    if let attr = highlighted {
                        Text(attr)
                    } else {
                        Text(event.jsonString)
                            .font(.system(size: 10, design: .monospaced))
                    }
                }
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.03))
                .task(id: event.id) {
                    let json = event.jsonString
                    let result = await Task.detached(priority: .userInitiated) {
                        highlightedJSON(json)
                    }.value
                    highlighted = result
                }
            }
        }
    }

    private var eventSummary: String {
        guard let d = event.jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
        else { return String(event.jsonString.prefix(80)) }
        if let delta = obj["delta"] as? [String: Any] {
            if let t = delta["text"] as? String {
                return "\"\(t.prefix(60))\(t.count > 60 ? "…" : "")\""
            }
            if let s = delta["stop_reason"] as? String { return "stop_reason: \(s)" }
        }
        if let usage = obj["usage"] as? [String: Any] {
            return usage.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        }
        return String(event.jsonString.prefix(80))
    }

    private func eventTypeColor(_ type: String) -> Color {
        switch type {
        case "message_start":        return .blue
        case "content_block_start":  return .cyan
        case "content_block_delta":  return .green
        case "content_block_stop":   return .cyan
        case "message_delta":        return .orange
        case "message_stop":         return .red
        default:                     return .secondary
        }
    }
}

// MARK: - Tokens tab

private struct TokensTab: View {
    let req: RequestLog

    private let promptColor  = Color.purple
    private let responseColor = Color(red: 0.2, green: 0.6, blue: 1.0)
    private var total: Double { Double(max(req.totalTokens, 1)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // Big total hero
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(req.totalTokens)")
                        .font(.system(size: 42, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    Text("TOTAL TOKENS")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .tracking(1.2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 14)

                Divider().padding(.horizontal, 14)

                // Distribution bars
                VStack(alignment: .leading, spacing: 16) {
                    Text("DISTRIBUTION")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .tracking(1)

                    tokenBar(label: "Prompt",   count: req.inputTokens,  color: promptColor)
                    tokenBar(label: "Response", count: req.outputTokens, color: responseColor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider().padding(.horizontal, 14)

                // Split ratio bar
                if req.totalTokens > 0 {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("RATIO")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .tracking(1)

                        GeometryReader { geo in
                            HStack(spacing: 0) {
                                Rectangle()
                                    .fill(promptColor)
                                    .frame(width: max(geo.size.width * Double(req.inputTokens) / total, 4))
                                Rectangle()
                                    .fill(responseColor)
                                    .frame(maxWidth: .infinity)
                            }
                            .frame(height: 12)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .frame(height: 12)

                        HStack {
                            legendDot(promptColor,   label: "Prompt",   pct: req.inputTokens)
                            Spacer()
                            legendDot(responseColor, label: "Response", pct: req.outputTokens)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
        }
    }

    @ViewBuilder
    private func tokenBar(label: String, count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(count > 0 ? color : Color.secondary.opacity(0.4))
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(color.opacity(0.10))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(LinearGradient(colors: [color.opacity(0.6), color],
                                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(geo.size.width * Double(count) / total, 0))
                }
            }
            .frame(height: 18)
        }
    }

    @ViewBuilder
    private func legendDot(_ color: Color, label: String, pct: Int) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(String(format: "%.0f%%", Double(pct) / total * 100))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - JSON code view  (async to keep tab switches instant)

struct JSONCodeView: View {
    let rawJSON: String
    var wrapLines: Bool = false
    @State private var attributed: AttributedString?

    var body: some View {
        ScrollView(wrapLines ? [.vertical] : [.vertical, .horizontal]) {
            // Show plain monospaced immediately; swap in highlighted version when ready.
            Group {
                if let attr = attributed {
                    Text(attr)
                } else {
                    Text(rawJSON)
                        .font(.system(size: 12, design: .monospaced))
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: rawJSON) {
            let json = rawJSON
            // Detach so regex work doesn't block the main thread.
            let result = await Task.detached(priority: .userInitiated) {
                highlightedJSON(json)
            }.value
            attributed = result
        }
    }
}

// MARK: - Tab button style  (DevTools-style pill with border)

private struct InspectorTabStyle: ButtonStyle {
    let active: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: active ? .semibold : .regular))
            .foregroundStyle(active ? Color.primary : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(active ? Color.primary.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(active ? Color.primary.opacity(0.18) : Color.clear, lineWidth: 0.5)
            )
    }
}
