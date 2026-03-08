import SwiftUI

// MARK: - Root Traces View (3-panel)

struct ConversationsView: View {
    @State private var sessions: [ConversationSession] = []
    @State private var selection: ConversationSession?
    @State private var selectedStep: SelectedStep?
    @State private var isLoading = true
    @State private var showDetails = true

    private var liveSessions:   [ConversationSession] { sessions.filter { $0.isLive } }
    private var errorSessions:  [ConversationSession] { sessions.filter { !$0.isLive && $0.hasErrors } }
    private var recentSessions: [ConversationSession] { sessions.filter { !$0.isLive && !$0.hasErrors } }

    var body: some View {
        HSplitView {
            traceListSidebar
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

            centerPane

            if showDetails {
                StepDetailView(session: selection, step: selectedStep)
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
            }
        }
        .task {
            let loaded = await Task.detached(priority: .userInitiated) {
                ConversationService.loadAllSessions()
            }.value
            sessions = loaded
            isLoading = false
        }
    }

    // MARK: - Sidebar

    private var traceListSidebar: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("TRACES")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(1.2)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { showDetails.toggle() }
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 10))
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)

                Button {
                    Task {
                        isLoading = true
                        let loaded = await Task.detached(priority: .userInitiated) {
                            ConversationService.loadAllSessions()
                        }.value
                        sessions = loaded
                        isLoading = false
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.bar)

            Divider()

            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if sessions.isEmpty {
                emptyTraces
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if !liveSessions.isEmpty {
                            sectionHeader("LIVE", dot: true)
                            ForEach(liveSessions) { s in
                                TraceListRow(session: s, isSelected: selection?.id == s.id)
                                    .onTapGesture { selectTrace(s) }
                            }
                        }
                        if !recentSessions.isEmpty {
                            sectionHeader("RECENT", dot: false)
                            ForEach(recentSessions) { s in
                                TraceListRow(session: s, isSelected: selection?.id == s.id)
                                    .onTapGesture { selectTrace(s) }
                            }
                        }
                        if !errorSessions.isEmpty {
                            sectionHeader("ERRORS", dot: false)
                            ForEach(errorSessions) { s in
                                TraceListRow(session: s, isSelected: selection?.id == s.id)
                                    .onTapGesture { selectTrace(s) }
                            }
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func selectTrace(_ session: ConversationSession) {
        selection = session
        selectedStep = nil
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, dot: Bool) -> some View {
        HStack(spacing: 5) {
            if dot {
                Circle().fill(Color.green).frame(width: 5, height: 5)
            }
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(1.2)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    // MARK: - Center

    private var centerPane: some View {
        Group {
            if let session = selection {
                TraceTimelineView(session: session, selectedStep: $selectedStep)
                    .id(session.id)
            } else if !isLoading {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: 28)).foregroundStyle(.quaternary)
                    Text("Select a trace")
                        .font(.system(size: 12)).foregroundStyle(.quaternary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var emptyTraces: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 28)).foregroundStyle(.quaternary)
            Text("No traces found")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
            Text("~/.claude/projects/")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.quaternary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Trace list row (sidebar)

private struct TraceListRow: View {
    let session: ConversationSession
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(isSelected ? Color.accentColor : Color.clear)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(session.projectName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(relativeTime(session.lastActivity))
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                        .monospacedDigit()
                }

                if !session.firstUserMessage.isEmpty {
                    Text(session.firstUserMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }

                HStack(spacing: 4) {
                    Text("\(session.stepCount) steps")
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                    if session.toolCount > 0 {
                        Text("·")
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                        Image(systemName: "wrench")
                            .font(.system(size: 8))
                            .foregroundStyle(.quaternary)
                        Text("\(session.toolCount)")
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                    }
                    if session.hasErrors {
                        Text("·")
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.red.opacity(0.7))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }

    private func relativeTime(_ date: Date) -> String {
        let diff = Int(Date().timeIntervalSince(date))
        if diff < 60    { return "\(diff)s" }
        if diff < 3600  { return "\(diff / 60)m" }
        if diff < 86400 { return "\(diff / 3600)h" }
        return "\(diff / 86400)d"
    }
}

// MARK: - Trace timeline (center)

struct TraceTimelineView: View {
    let session: ConversationSession
    @Binding var selectedStep: SelectedStep?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Header
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.projectName)
                            .font(.system(size: 13, weight: .semibold))
                        Text(session.cwd)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    Divider()

                    ForEach(Array(session.messages.enumerated()), id: \.element.id) { idx, msg in
                        TraceStepRow(
                            message: msg,
                            isLast: idx == session.messages.count - 1,
                            selectedStep: $selectedStep
                        )
                        .id(msg.id)
                    }
                }
            }
            .onAppear {
                if let last = session.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - Individual step row

private struct TraceStepRow: View {
    let message: SessionMessage
    let isLast: Bool
    @Binding var selectedStep: SelectedStep?

    private var isUser: Bool { message.role == .user }

    private var isMessageSelected: Bool {
        if case .message(let m) = selectedStep { return m.id == message.id }
        return false
    }

    // Visual hierarchy: Claude = primary/accent, User = secondary/blue
    private var dotColor: Color {
        if message.isError { return .red }
        return isUser ? Color.blue.opacity(0.7) : Color.accentColor
    }

    // Claude gets a larger dot to signal primary importance
    private var dotSize: CGFloat  { isUser ? 6  : 9  }
    private var haloSize: CGFloat { isUser ? 16 : 22 }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Selection accent bar
            Rectangle()
                .fill(isMessageSelected ? Color.accentColor : Color.clear)
                .frame(width: 2)

            // Gutter: connector + dot
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(dotColor.opacity(isMessageSelected ? 0.22 : 0.10))
                        .frame(width: haloSize, height: haloSize)
                    Circle()
                        .fill(dotColor)
                        .frame(width: dotSize, height: dotSize)
                }
                .padding(.top, 10)

                if !isLast {
                    Rectangle()
                        .fill(Color.primary.opacity(0.14))   // stronger spine
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 34)

            // Content
            VStack(alignment: .leading, spacing: 0) {
                // Actor label — tap to select
                HStack(spacing: 6) {
                    Text(isUser ? "User" : "Claude")
                        .font(.system(size: isUser ? 11 : 12,
                                      weight: isUser ? .medium : .semibold))
                        .foregroundStyle(isUser
                            ? Color.primary.opacity(0.45)
                            : Color.primary)

                    if let model = message.model, !isUser {
                        let (badge, color) = modelBadge(from: model)
                        Text(badge)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(color)
                            .padding(.horizontal, 4).padding(.vertical, 1.5)
                            .background(color.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }

                    Spacer()
                }
                .padding(.top, 10)
                .padding(.bottom, 4)
                .contentShape(Rectangle())
                .onTapGesture { selectedStep = .message(message) }

                // Tool uses (selectable chips)
                if !message.toolUses.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(message.toolUses) { tool in
                            let isToolSelected: Bool = {
                                if case .toolUse(let t, _) = selectedStep { return t.id == tool.id }
                                return false
                            }()
                            ToolStepChip(
                                tool: tool,
                                parent: message,
                                isSelected: isToolSelected,
                                selectedStep: $selectedStep
                            )
                        }
                    }
                    .padding(.bottom, message.text.isEmpty ? 0 : 6)
                }

                // Text body — Claude gets larger, primary text; User gets smaller, secondary
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: isUser ? 12 : 13))
                        .lineSpacing(isUser ? 1 : 2)
                        .foregroundStyle(message.isError
                            ? Color.red
                            : (isUser ? Color.secondary : Color.primary.opacity(0.85)))
                        .lineLimit(isMessageSelected ? nil : (isUser ? 2 : 3))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedStep = .message(message) }
                }

                Spacer(minLength: 14)
            }
            .padding(.trailing, 16)
        }
        .background(isMessageSelected ? Color.accentColor.opacity(0.07) : Color.clear)
        .animation(.easeInOut(duration: 0.15), value: isMessageSelected)
    }
}

// MARK: - Tool chip (selectable)

private struct ToolStepChip: View {
    let tool: SessionMessage.ToolUseBlock
    let parent: SessionMessage
    let isSelected: Bool
    @Binding var selectedStep: SelectedStep?

    private let amber = Color(red: 0.95, green: 0.65, blue: 0.15)

    var body: some View {
        Button {
            selectedStep = .toolUse(tool, parent: parent)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: toolIcon(tool.name))
                    .font(.system(size: 9))
                    .foregroundStyle(amber)
                Text(tool.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(amber)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 8))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .background(isSelected ? amber.opacity(0.2) : amber.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(isSelected ? amber.opacity(0.5) : amber.opacity(0.2), lineWidth: 0.5)
        )
    }

    private func toolIcon(_ name: String) -> String { stepToolIcon(name) }
}

// MARK: - Step detail panel (right)

struct StepDetailView: View {
    let session: ConversationSession?
    let step: SelectedStep?

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text(headerTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch step {
                    case .message(let msg):
                        MessageDetailContent(message: msg)
                    case .toolUse(let tool, _):
                        ToolDetailContent(tool: tool)
                    case nil:
                        if let s = session {
                            SessionOverviewContent(session: s)
                        } else {
                            emptyDetail
                        }
                    }
                }
            }
        }
    }

    private var headerTitle: String {
        switch step {
        case .message(let m): return m.role == .user ? "User Message" : "Claude Response"
        case .toolUse(let t, _): return t.name
        case nil: return session != nil ? "Trace Info" : "Details"
        }
    }

    private var emptyDetail: some View {
        VStack(spacing: 8) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 24)).foregroundStyle(.quaternary)
            Text("Select a step")
                .font(.system(size: 12)).foregroundStyle(.quaternary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(.top, 60)
    }
}

// MARK: - Session overview (shown when no step selected)

private struct SessionOverviewContent: View {
    let session: ConversationSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            detailRow("PROJECT", session.projectName)
            Divider().padding(.horizontal, 14)
            detailRow("DIRECTORY", session.cwd)
            Divider().padding(.horizontal, 14)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 0) {
                metricCell("STEPS",    "\(session.stepCount)")
                metricCell("MESSAGES", "\(session.messageCount)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider().padding(.horizontal, 14)
            detailRow("STARTED", shortTime(session.startTime))
            Divider().padding(.horizontal, 14)
            detailRow("LAST ACTIVE", shortTime(session.lastActivity))
        }
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.8)
            Text(value)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func metricCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.8)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }

    private func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, HH:mm"
        return f.string(from: date)
    }
}

// MARK: - Message detail

private struct MessageDetailContent: View {
    let message: SessionMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(message.role == .user ? "User" : "Claude")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(message.role == .user ? Color.blue : Color.primary)
                if message.isError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10)).foregroundStyle(.red)
                }
                Spacer()
                Text(message.timestamp, style: .time)
                    .font(.system(size: 10)).foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if let model = message.model {
                Divider().padding(.horizontal, 14)
                HStack {
                    Text("MODEL")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.8)
                    Spacer()
                    let (badge, color) = modelBadge(from: model)
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(color.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            }

            if !message.text.isEmpty {
                Divider().padding(.horizontal, 14)
                Text("CONTENT")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                Text(message.text)
                    .font(.system(size: 12))
                    .lineSpacing(3)
                    .foregroundStyle(message.isError ? Color.red : Color.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
    }
}

// MARK: - Tool detail

private struct ToolDetailContent: View {
    let tool: SessionMessage.ToolUseBlock
    private let amber = Color(red: 0.95, green: 0.65, blue: 0.15)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: stepToolIcon(tool.name))
                    .font(.system(size: 16))
                    .foregroundStyle(amber)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(tool.name)
                        .font(.system(size: 13, weight: .semibold))
                    Text("Tool call")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)

            Divider().padding(.horizontal, 14)

            Text("ARGUMENTS")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.8)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)

            JSONCodeView(rawJSON: tool.inputJSON, wrapLines: true)
                .frame(minHeight: 80)
        }
    }
}

// MARK: - Shared tool icon helper

func stepToolIcon(_ name: String) -> String {
    switch name {
    case "Bash":      return "terminal"
    case "Read":      return "doc.text"
    case "Write":     return "square.and.pencil"
    case "Edit":      return "pencil"
    case "Glob":      return "folder.badge.magnifyingglass"
    case "Grep":      return "magnifyingglass"
    case "Agent":     return "person.crop.circle"
    case "WebFetch":  return "globe"
    case "WebSearch": return "magnifyingglass.circle"
    default:          return "wrench"
    }
}
