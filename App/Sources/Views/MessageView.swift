import AgentCore
import SwiftUI

struct MessageView: View {
    let message: ChatMessage
    var isLast = false
    var retry: (() -> Void)?
    /// Tool results by call id, so each call's card can show its output.
    var toolResults: [String: ChatMessage] = [:]
    /// Tool calls running now, with when each started.
    var running: [String: Date] = [:]
    var liveOutput: [String: String] = [:]
    var awaitingApprovalID: String?
    /// Offered on user messages in a project: undo from here.
    var rewind: (() -> Void)?
    /// A new conversation from here: before a request (to send it differently), or after a final reply.
    var fork: (() -> Void)?
    /// On a main run's final reply: the user's thumbs (nil: none yet), and how to give them.
    var thumbs: Bool?
    var rate: ((Bool) -> Void)?

    var body: some View {
        #if DEBUG
        let _ = BodyTrace.on ? Self._printChanges() : ()
        #endif
        switch message.role {
        case .user:
            if let command = message.userCommand {
                UserCommandView(info: command)
            } else if let run = message.subagentReport {
                SubagentReportView(text: message.content, run: run)
            } else if message.contextNote == true {
                Label(FrozenSystemPrompt.noteLabel(message.content), systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
                    .help(message.content)
            } else {
                UserBubble(text: message.content, images: message.images ?? [], rewind: rewind, fork: fork)
            }
        case .assistant:
            AssistantMessage(message: message, retry: isLast ? retry : nil, toolResults: toolResults,
                             running: running, liveOutput: liveOutput, awaitingApprovalID: awaitingApprovalID,
                             thumbs: thumbs, rate: rate, fork: fork)
        case .system, .tool: EmptyView()     // tool results render inside their call's card
        }
    }
}

struct UserBubble: View {
    let text: String
    var images: [ImageAttachment] = []
    var rewind: (() -> Void)?
    var fork: (() -> Void)?
    @State private var hovering = false

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    var body: some View {
        #if DEBUG
        let _ = BodyTrace.on ? Self._printChanges() : ()
        #endif
        HStack(alignment: .top) {
            Spacer(minLength: 80)
            if hovering {
                HStack(spacing: 8) {
                    Button(action: copy) { Label("Copy", systemImage: "doc.on.doc") }
                        .help("Copy this message")
                    if let fork {
                        Button(action: fork) { Label("Fork", systemImage: "arrow.triangle.branch") }
                            .help("Try this request differently in a new conversation; this one and the files stay as they are")
                    }
                    if let rewind {
                        Button(action: rewind) { Label("Rewind", systemImage: "arrow.uturn.backward") }
                            .help("Undo from here: restore files the agent changed and edit this message")
                    }
                }
                .buttonStyle(.borderless).font(.caption).labelStyle(.iconOnly)
                .padding(.top, 10)
            }
            VStack(alignment: .trailing, spacing: 6) {
                if !images.isEmpty {
                    HStack(spacing: 6) { ForEach(images) { ImageThumbnail(image: $0, size: 120) } }
                }
                if !text.isEmpty {
                    Text(text)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Copy", action: copy)
            if let fork { Button("Fork from Here", action: fork) }
            if let rewind { Button("Edit and Resend (Rewind)…", action: rewind) }
        }
    }
}

/// A command the user ran with `!`, shown like a terminal: the command, then its output.
struct UserCommandView: View {
    let info: UserCommandInfo

    var body: some View {
        HStack(alignment: .top) {
            Spacer(minLength: 80)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("$").foregroundStyle(.secondary)
                    Text(info.command).fontWeight(.medium)
                    Spacer(minLength: 8)
                    if let code = info.exitCode, code != 0 {
                        Text("exit \(code)").font(.caption).foregroundStyle(.red)
                    }
                }
                if !info.output.isEmpty {
                    CodeScroll(maxHeight: 220) { Text(info.output).foregroundStyle(.secondary) }
                }
            }
            .font(.callout.monospaced())
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .help("You ran this command; the agent sees its output")
        }
    }
}

struct AssistantMessage: View {
    @Environment(AppModel.self) private var app
    let message: ChatMessage
    var retry: (() -> Void)?
    var toolResults: [String: ChatMessage] = [:]
    var running: [String: Date] = [:]
    var liveOutput: [String: String] = [:]
    var awaitingApprovalID: String?
    var thumbs: Bool?
    var rate: ((Bool) -> Void)?
    var fork: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        #if DEBUG
        let _ = BodyTrace.on ? Self._printChanges() : ()
        #endif
        // Rows of the transcript's lazy stack, like a streaming reply's (see MarkdownPieces).
        Group {
            if let reasoning = message.reasoning {
                ThinkingSection(text: reasoning, tokens: message.meta?.usage?.reasoningTokens, live: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !message.content.isEmpty {
                MarkdownPieces(markdown: message.content)
            }
            if !message.toolCalls.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(message.toolCalls) { call in
                        ToolCallCard(call: call, result: toolResults[call.id], running: running[call.id] != nil,
                                     since: running[call.id], liveOutput: liveOutput[call.id],
                                     awaitingApproval: call.id == awaitingApprovalID)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let meta = message.meta {
                StopNotice(meta: meta, retry: retry, lost: AgentLoop.droppedCall(message))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Turns that only call tools skip the footer; the final answer carries it.
            if let meta = message.meta, message.toolCalls.isEmpty {
                HStack(spacing: 10) {
                    Text(footer(meta)).font(.caption).foregroundStyle(.secondary)
                    if hovering {
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.content, forType: .string)
                        }
                        .buttonStyle(.link).font(.caption)
                        if let retry { Button("Retry", action: retry).buttonStyle(.link).font(.caption) }
                        if let fork {
                            Button("Fork", action: fork).buttonStyle(.link).font(.caption)
                                .help("A new conversation from here; this one and the files stay as they are")
                        }
                    }
                    if let rate, hovering || thumbs != nil {
                        ThumbButton(up: true, chosen: thumbs == true) { rate(true) }
                        ThumbButton(up: false, chosen: thumbs == false) { rate(false) }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
            }
        }
    }

    private func footer(_ meta: TurnMeta) -> String {
        var parts = [meta.reportedModel ?? meta.requestedModel]
        if let id = meta.endpointID, id != Endpoint.localLMStudio.id, let e = app.endpoint(id) { parts[0] += " @ \(e.name)" }
        if let provider = meta.provider { parts[0] += " via \(provider)" }
        if let u = meta.usage {
            parts.append("\(u.completionTokens) tokens")
            if meta.duration > 0, let ttft = meta.timeToFirstToken, meta.duration - ttft > 0.2 {
                parts.append(String(format: "%.0f tok/s", Double(u.completionTokens) / (meta.duration - ttft)))
            }
        }
        parts.append(String(format: "%.1f s", meta.duration))
        return parts.joined(separator: " · ")
    }
}

/// Says why a turn ended, when it wasn't a normal finish.
struct StopNotice: View {
    let meta: TurnMeta
    var retry: (() -> Void)?
    /// An empty reply with output tokens: the server dropped the model's tool call.
    var lost = false

    var body: some View {
        if let (icon, text, color) = notice {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: icon)
                Text(text)
                if let retry { Button("Retry", action: retry).buttonStyle(.link) }
            }
            .font(.callout)
            .foregroundStyle(color)
        }
    }

    private var notice: (String, String, Color)? {
        if meta.modelMismatch, let got = meta.reportedModel {
            return ("exclamationmark.triangle", "Asked for \(meta.requestedModel) but \(got) answered.", .orange)
        }
        switch meta.stopReason {
        case .completed:
            if meta.finishReason == .length {
                return ("scissors", "Stopped at the output limit (\(meta.usage?.completionTokens ?? 0) tokens).", .orange)
            }
            if lost {
                return ("tray", "\(meta.provider ?? "The server") lost this reply: \(meta.usage?.completionTokens ?? 0) tokens were "
                        + "generated and nothing arrived (usually a tool call it couldn't read).", .orange)
            }
            return nil
        case .cancelled: return ("stop.circle", "Stopped.", .secondary)
        case .timedOut: return ("clock.badge.exclamationmark", meta.error ?? "Stopped after \(Int(meta.duration)) seconds.", .orange)
        case .repetition: return ("repeat", "Stopped: the model was repeating itself.", .orange)
        case .failed: return ("xmark.octagon", meta.error ?? "The request failed.", .red)
        }
    }
}

struct ThinkingSection: View {
    let text: String
    var tokens: Int?
    var live: Bool
    var elapsed: TimeInterval?
    @State private var expanded = false

    var body: some View {
        #if DEBUG
        let _ = BodyTrace.on ? Self._printChanges() : ()
        #endif
        DisclosureGroup(isExpanded: $expanded) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
        } label: {
            HStack(spacing: 6) {
                if live { ProgressView().controlSize(.mini) }
                Text(label).foregroundStyle(.secondary)
            }
        }
    }

    private var label: String {
        if live { return "Thinking… \(Int(elapsed ?? 0)) s" }
        return tokens.map { "Thought for \($0) tokens" } ?? "Thoughts"
    }
}

/// The turn in progress.
struct StreamingMessageView: View {
    let snapshot: TurnSnapshot
    let startedAt: Date
    /// When the whole run started, for runs of more than one turn.
    var runStartedAt: Date?
    let model: String
    let stop: () -> Void

    var body: some View {
        #if DEBUG
        let _ = BodyTrace.on ? Self._printChanges() : ()
        #endif
        // Rows of the transcript's lazy stack, not one view: the reply's pieces each a row (see MarkdownPieces).
        // The clock ticks on its own: during prompt processing or a stalled server no events arrive.
        Group {
            if !snapshot.reasoning.isEmpty {
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    ThinkingSection(text: snapshot.reasoning, live: snapshot.isThinking,
                                    elapsed: context.date.timeIntervalSince(startedAt))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !snapshot.content.isEmpty {
                MarkdownPieces(markdown: snapshot.content, live: true)
            }
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(status(context.date.timeIntervalSince(startedAt))).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    Button("Stop", action: stop).buttonStyle(.link).font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Always visible, so a runaway generation is obvious.
    private func status(_ elapsed: TimeInterval) -> String {
        let run = runStartedAt.map { start -> String in
            let total = Date().timeIntervalSince(start)
            return total - elapsed >= 5 ? " · run " + RunClock.text(total) : ""
        } ?? ""
        if snapshot.timeToFirstToken == nil {
            return "Waiting for \(model)… \(Int(elapsed)) s" + run
        }
        return "Generating: ~\(snapshot.estimatedTokens) tokens · \(Int(elapsed)) s" + run
    }
}

/// 👍 or 👎 on a reply: kept with the session to choose models later (GAP_ANALYSIS.md A3). Filled when chosen; clicking
/// the chosen one again takes it back.
private struct ThumbButton: View {
    let up: Bool
    let chosen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: up ? (chosen ? "hand.thumbsup.fill" : "hand.thumbsup") : (chosen ? "hand.thumbsdown.fill" : "hand.thumbsdown"))
                .font(.caption)
                .foregroundStyle(chosen ? Color.accentColor : .secondary)
        }
        .buttonStyle(.borderless)
        .help(up ? "This reply was right" : "This reply was wrong")
        .accessibilityLabel(up ? "Good reply" : "Bad reply")
    }
}
