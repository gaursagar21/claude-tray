import SwiftUI

struct ConversationView: View {
    let req: RequestLog
    let bodies: RequestBodies?

    @State private var messages: [ChatMessage] = []

    var body: some View {
        ZStack {
            DotGridBackground()
            if bodies == nil {
                VStack(spacing: 8) {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if messages.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 24))
                        .foregroundStyle(.quaternary)
                    Text("No messages parsed")
                        .font(.system(size: 12))
                        .foregroundStyle(.quaternary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { msg in
                            MessageCard(message: msg, model: req.model)
                        }
                    }
                    .padding(16)
                }
            }
        }
        // Parse chat messages on a background thread when bodies arrive.
        .task(id: bodies?.requestBody) {
            guard let b = bodies else { return }
            let reqBody = b.requestBody
            let resBody = b.responseBody
            let streaming = req.isStreaming
            let parsed = await Task.detached(priority: .userInitiated) {
                parseChatMessages(requestBody: reqBody, responseBody: resBody, isStreaming: streaming)
            }.value
            messages = parsed
        }
    }
}

// MARK: - Dot grid background

struct DotGridBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let spacing: CGFloat = 22
            let r: CGFloat = 0.9
            var y: CGFloat = 0
            while y < size.height + spacing {
                var x: CGFloat = 0
                while x < size.width + spacing {
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r*2, height: r*2)),
                        with: .color(Color.primary.opacity(0.06))
                    )
                    x += spacing
                }
                y += spacing
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
    }
}

// MARK: - Message card

// Approximate line height for the preview clamp (13pt font + 3pt spacing)
private let collapsedHeight: CGFloat = 44  // ~2 lines

private struct MessageCard: View {
    let message: ChatMessage
    let model: String

    @State private var expanded = false
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            // Left accent stripe
            RoundedRectangle(cornerRadius: 2)
                .fill(accentColor)
                .frame(width: 3)
                .padding(.vertical, 1)

            VStack(alignment: .leading, spacing: 0) {
                // Header — tap anywhere to toggle
                HStack(spacing: 8) {
                    roleLabel
                    Spacer()
                    // Copy button — always in layout, opacity-only to avoid jitter
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.text, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovering ? 1 : 0)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                }

                Divider().opacity(0.12)

                // Body — clipped when collapsed, full when expanded
                ZStack(alignment: .bottom) {
                    Text(message.text)
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .foregroundStyle(textColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(maxHeight: expanded ? .infinity : collapsedHeight, alignment: .top)
                        .clipped()

                    // Fade-out gradient when collapsed
                    if !expanded {
                        LinearGradient(
                            colors: [cardBg.opacity(0), cardBg],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 28)
                        .allowsHitTesting(false)
                    }
                }
            }
            .background(cardBg)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(borderColor, lineWidth: 0.5)
        )
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var roleLabel: some View {
        switch message.role {
        case .user:
            Text("USER")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(1.5)

        case .assistant:
            let (badge, color) = modelBadge(from: model)
            HStack(spacing: 6) {
                Text("CLAUDE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.5)
                Text("·")
                    .foregroundStyle(.quaternary)
                Text(badge)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

        case .system:
            HStack(spacing: 4) {
                Image(systemName: "gearshape")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text("SYSTEM")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.5)
            }
        }
    }

    private var cardBg: Color {
        switch message.role {
        case .user:      return Color(nsColor: .controlBackgroundColor)
        case .assistant: return Color(nsColor: .controlBackgroundColor).opacity(0.7)
        case .system:    return Color.orange.opacity(0.05)
        }
    }

    private var borderColor: Color {
        switch message.role {
        case .user:      return Color.primary.opacity(0.07)
        case .assistant: return Color.accentColor.opacity(0.18)
        case .system:    return Color.orange.opacity(0.15)
        }
    }

    private var textColor: Color {
        message.role == .system ? Color.primary.opacity(0.6) : Color.primary
    }

    private var accentColor: Color {
        switch message.role {
        case .user:      return Color.blue.opacity(0.7)
        case .assistant:
            let (_, color) = modelBadge(from: model)
            return color.opacity(0.8)
        case .system:    return Color.orange.opacity(0.7)
        }
    }
}
