import SwiftUI

struct RequestsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selection: RequestLog?
    @State private var selectedBodies: RequestBodies?
    @State private var search = ""
    @State private var showSidebar   = true
    @State private var showInspector = true
    @State private var activeTab: AppTab = .traces

    enum AppTab { case traces, apiLog }

    // Filter only on metadata — never search raw body strings on main thread.
    private var filtered: [RequestLog] {
        guard !search.isEmpty else { return appState.requests }
        let q = search.lowercased()
        return appState.requests.filter {
            $0.model.lowercased().contains(q) || $0.shortModel.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbarRow
            Divider()
            if activeTab == .traces {
                ConversationsView()
            } else {
                HSplitView {
                    if showSidebar {
                        sidebarColumn
                            .frame(minWidth: 210, idealWidth: 250, maxWidth: 300)
                    }
                    centerColumn
                    if showInspector {
                        inspectorColumn
                            .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
                    }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 540)
        // Load bodies from DB on a background thread when selection changes.
        .onChange(of: selection?.id) { _, newId in
            selectedBodies = nil
            guard let id = newId else { return }
            let storage = appState.storage
            Task {
                let bodies = await Task.detached(priority: .userInitiated) {
                    storage?.fetchBodies(id: id)
                }.value
                selectedBodies = bodies
            }
        }
    }

    // MARK: - Toolbar

    private var toolbarRow: some View {
        HStack(spacing: 0) {
            // Tab buttons
            HStack(spacing: 0) {
                tabButton("Traces", tab: .traces)
                tabButton("API Log", tab: .apiLog)
            }
            .padding(.leading, 12)

            Spacer()

            // Status + metrics
            HStack(spacing: 14) {
                // Recording status
                HStack(spacing: 5) {
                    Circle()
                        .fill(appState.isRunning ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                        .shadow(color: appState.isRunning ? .green.opacity(0.6) : .clear, radius: 3)
                    Text(appState.isRunning ? "Recording" : "Stopped")
                        .font(.system(size: 11, weight: .medium))
                    if !appState.requests.isEmpty {
                        Text("\(appState.requests.count)")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }

                if !appState.requests.isEmpty {
                    let totalTok = appState.requests.reduce(0) { $0 + $1.totalTokens }
                    Divider().frame(height: 14)
                    statPill(value: formatTokens(totalTok), label: "tokens")
                    statPill(value: avgLatency, label: "avg")
                }
            }
            .padding(.trailing, 8)

            Divider().frame(height: 16)

            // Actions
            HStack(spacing: 1) {
                if activeTab == .apiLog {
                    toolbarButton(icon: "sidebar.left")  { withAnimation(.easeInOut(duration: 0.18)) { showSidebar.toggle() } }
                    toolbarButton(icon: "sidebar.right") { withAnimation(.easeInOut(duration: 0.18)) { showInspector.toggle() } }
                    Divider().frame(height: 14).padding(.horizontal, 3)
                }
                toolbarButton(icon: "arrow.clockwise") { appState.refresh() }
                if !appState.requests.isEmpty && activeTab == .apiLog {
                    toolbarButton(icon: "trash") { appState.clearAll() }
                }
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 36)
        .background(.bar)
    }

    @ViewBuilder
    private func tabButton(_ label: String, tab: AppTab) -> some View {
        let active = activeTab == tab
        Button { activeTab = tab } label: {
            Text(label)
                .font(.system(size: 12, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Color.primary : Color.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) {
                    if active {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(height: 2)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var avgLatency: String {
        guard !appState.requests.isEmpty else { return "—" }
        let avg = appState.requests.reduce(0) { $0 + $1.durationMs } / appState.requests.count
        return avg >= 1000 ? String(format: "%.1fs", Double(avg)/1000) : "\(avg)ms"
    }

    private func formatTokens(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n)/1000) : "\(n)"
    }

    @ViewBuilder
    private func statPill(value: String, label: String) -> some View {
        HStack(spacing: 3) {
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func toolbarButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11.5))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    // MARK: - Sidebar

    private var sidebarColumn: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 11))
                TextField("Filter", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if appState.requests.isEmpty {
                setupGuide
            } else if filtered.isEmpty {
                VStack {
                    Spacer()
                    Text("No results").font(.system(size: 12)).foregroundStyle(.tertiary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { req in
                            let isSelected = selection?.id == req.id
                            EquatableView(content: TimelineRow(req: req, isSelected: isSelected))
                                .onTapGesture { selection = req }
                                .contextMenu {
                                    Button("Copy Request JSON") {
                                        let storage = appState.storage
                                        Task.detached {
                                            guard let b = storage?.fetchBodies(id: req.id) else { return }
                                            await MainActor.run {
                                                NSPasteboard.general.clearContents()
                                                NSPasteboard.general.setString(b.requestBody, forType: .string)
                                            }
                                        }
                                    }
                                    Button("Copy Response") {
                                        let storage = appState.storage
                                        let streaming = req.isStreaming
                                        Task.detached {
                                            guard let b = storage?.fetchBodies(id: req.id) else { return }
                                            let text = streaming
                                                ? parseSSE(b.responseBody).text
                                                : b.responseBody
                                            await MainActor.run {
                                                NSPasteboard.general.clearContents()
                                                NSPasteboard.general.setString(text, forType: .string)
                                            }
                                        }
                                    }
                                }
                        }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
            }

            Divider()
            portFooter
        }
    }

    private var portFooter: some View {
        HStack {
            Text("localhost:\(appState.port, format: .number.grouping(.never))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.quaternary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Center

    private var centerColumn: some View {
        Group {
            if let sel = selection {
                ConversationView(req: sel, bodies: selectedBodies).id(sel.id)
            } else if appState.requests.isEmpty {
                emptyCenter
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "arrow.left.square")
                        .font(.system(size: 24)).foregroundStyle(.quaternary)
                    Text("Select a request")
                        .font(.system(size: 12)).foregroundStyle(.quaternary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Inspector

    private var inspectorColumn: some View {
        Group {
            if let sel = selection {
                InspectorView(req: sel, bodies: selectedBodies).id(sel.id)
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "info.circle")
                        .font(.system(size: 24)).foregroundStyle(.quaternary)
                    Text("No request selected")
                        .font(.system(size: 12)).foregroundStyle(.quaternary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Empty / setup

    private var emptyCenter: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 32)).foregroundStyle(.quaternary)
            VStack(spacing: 4) {
                Text("Monitoring idle")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Text("Waiting for Claude Code requests")
                    .font(.system(size: 12)).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var setupGuide: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(appState.isRunning ? Color.green : Color.red)
                            .frame(width: 6, height: 6)
                        Text(appState.isRunning ? "Proxy running" : "Proxy stopped")
                            .font(.system(size: 12, weight: .medium))
                    }
                    Text("No requests captured yet")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("QUICK SETUP")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary).tracking(1.2)
                    setupStep("1", "Add to shell profile") {
                        CopyableCode("export ANTHROPIC_BASE_URL=http://localhost:\(appState.port)")
                    }
                    setupStep("2", "Restart terminal or source profile") {
                        CopyableCode("source ~/.zshrc")
                    }
                    setupStep("3", "Use Claude Code normally") {
                        CopyableCode("claude")
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("INFO")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary).tracking(1.2)
                    bulletNote("Your API key is never stored here")
                    bulletNote("Requests logged to ~/Library/Application Support/ClaudeTray/")
                    bulletNote("Proxy is fully transparent — no modification")
                }
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private func setupStep(_ n: String, _ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(n)
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 15, height: 15)
                    .background(Color.accentColor).clipShape(Circle())
                Text(title).font(.system(size: 11, weight: .medium))
            }
            content().padding(.leading, 21)
        }
    }

    @ViewBuilder
    private func bulletNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Text("·").foregroundStyle(.secondary)
            Text(text).font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Timeline row (requests sidebar)

private struct TimelineRow: View, Equatable {
    nonisolated static func == (lhs: TimelineRow, rhs: TimelineRow) -> Bool {
        lhs.req.id == rhs.req.id && lhs.isSelected == rhs.isSelected
    }

    let req: RequestLog
    let isSelected: Bool

    private var statusColor: Color {
        if req.statusCode == 0  { return .secondary }
        if req.statusCode < 300 { return .green }
        if req.statusCode < 500 { return .orange }
        return .red
    }

    var body: some View {
        HStack(spacing: 0) {
            // Selection accent bar
            Rectangle()
                .fill(isSelected ? Color.accentColor : Color.clear)
                .frame(width: 2)

            HStack(alignment: .top, spacing: 0) {
                // Spine
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.07))
                        .frame(width: 1, height: 8)
                    ZStack {
                        Circle().fill(statusColor.opacity(0.18)).frame(width: 13, height: 13)
                        Circle().fill(statusColor).frame(width: 6, height: 6)
                    }
                    Rectangle()
                        .fill(Color.primary.opacity(0.07))
                        .frame(width: 1).frame(maxHeight: .infinity)
                }
                .frame(width: 22).padding(.top, 2)

                // Content — all strings precomputed, no formatting in body
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(req.displayTime)
                            .font(.system(size: 10)).foregroundStyle(.tertiary).monospacedDigit()
                        Spacer()
                        if req.statusCode >= 400 {
                            Text("ERR \(req.statusCode)")
                                .font(.system(size: 9, weight: .bold)).foregroundStyle(.red)
                        } else if req.statusCode > 0 {
                            Text("\(req.statusCode)")
                                .font(.system(size: 9)).foregroundStyle(.quaternary)
                        }
                    }

                    HStack(spacing: 4) {
                        let (badge, color) = modelBadge(from: req.model)
                        Text(badge)
                            .font(.system(size: 8, weight: .bold)).foregroundStyle(color)
                            .padding(.horizontal, 4).padding(.vertical, 1.5)
                            .background(color.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        Text(req.shortModel)
                            .font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                    }

                    if req.totalTokens > 0 || req.durationMs > 0 {
                        HStack(spacing: 3) {
                            if req.totalTokens > 0 { Text("\(req.totalTokens) tok") }
                            if req.durationMs > 0 {
                                Text("·").foregroundStyle(.quaternary)
                                Text(req.displayDuration)
                            }
                            if req.isStreaming {
                                Text("·").foregroundStyle(.quaternary)
                                Image(systemName: "waveform")
                            }
                        }
                        .font(.system(size: 10)).foregroundStyle(.quaternary).monospacedDigit()
                    }
                }
                .padding(.leading, 7).padding(.trailing, 10)
                .padding(.top, 7).padding(.bottom, 9)
            }
        }
        .background(isSelected
            ? Color.accentColor.opacity(0.09)
            : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Copyable code

private struct CopyableCode: View {
    let text: String
    @State private var copied = false
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(spacing: 0) {
            Text(text)
                .font(.system(size: 10, design: .monospaced))
                .textSelection(.enabled)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                withAnimation { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { copied = false } }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundStyle(copied ? .green : .secondary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
        }
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}
