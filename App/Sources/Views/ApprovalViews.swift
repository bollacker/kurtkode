import AgentCore
import SwiftUI

/// Asks the user about one tool call, showing exactly what it will do.
struct ApprovalCard: View {
    let pending: ChatController.PendingApproval
    let answer: (ApprovalDecision) -> Void
    @State private var feedback = ""
    @FocusState private var feedbackFocused: Bool
    /// Where the window's typing goes, and when this card appeared: its keys keep out of other fields, and a press
    /// right after it appeared (the end of the last card's answer, in the same spot) doesn't answer it (`CardKeys`).
    @Environment(\.textFocus) private var focus
    @State private var appearedAt = Date()

    private var request: ApprovalRequest { pending.request }
    private var isToolCall: Bool { if case .call? = request.preview { true } else { false } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: isToolCall ? "puzzlepiece.extension" : request.risk == .execute ? "terminal" : "pencil.and.outline")
                    .foregroundStyle(.orange)
                Text(isToolCall ? "Call this tool?" : request.risk == .execute ? "Run this command?" : "Make this change?").font(.headline)
                Spacer()
                Text(request.summary).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            // Why it asks when the mode wouldn't: a dangerous command, a permission rule, a repeated call.
            if let reason = request.reason {
                Label("Asking because " + reason + ".", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
            }

            switch request.preview {
            case .diff(let path, let unified, let isNew):
                Text(isNew ? "New file \(path)" : path).font(.caption.monospaced()).foregroundStyle(.secondary)
                DiffView(diff: unified, maxHeight: 320)
            case .command(let command, let cwd):
                VStack(alignment: .leading, spacing: 4) {
                    Text(cwd == "." ? "in the project root" : "in \(cwd)").font(.caption.monospaced()).foregroundStyle(.secondary)
                    CodeScroll(maxHeight: 200) {
                        Text(command).font(.callout.monospaced()).textSelection(.enabled).padding(10)
                    }
                    .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }
            case .call(let title, let arguments):
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    CodeScroll(maxHeight: 220) {
                        Text(arguments).font(.callout.monospaced()).textSelection(.enabled).padding(10)
                    }
                    .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }
            case nil:
                Text(request.call.arguments).font(.caption.monospaced()).lineLimit(8)
            }

            TextField("Tell the agent what to do instead (optional)", text: $feedback, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .focused($feedbackFocused)

            HStack(spacing: 10) {
                Button("Allow") { if CardKeys.pressCounts(since: appearedAt) { answer(.allow) } }
                    .keyboardShortcut(CardKeys.shortcut(.confirm, KeyboardShortcut(.return, modifiers: .command),
                                                        focus: focus, inCard: feedbackFocused))
                    .buttonStyle(.borderedProminent)
                    .help("⌘↩ (not while typing a message)")
                if let rule = request.suggestedRule {
                    Button("Always allow \(rule.displayName)") {
                        if CardKeys.pressCounts(since: appearedAt) { answer(.allowAlways(rule)) }
                    }
                    .keyboardShortcut(CardKeys.shortcut(.confirm, KeyboardShortcut("a", modifiers: [.command, .option]),
                                                        focus: focus, inCard: feedbackFocused))
                    .help("For the rest of this session (⌥⌘A)")
                }
                Spacer()
                Button(feedback.isEmpty ? "Deny" : "Deny with feedback") {
                    answer(.deny(feedback: feedback.isEmpty ? nil : feedback))
                }
                .keyboardShortcut(CardKeys.shortcut(.dismiss, KeyboardShortcut(.escape, modifiers: []),
                                                    focus: focus, inCard: feedbackFocused))
                .help(feedback.isEmpty ? "Stops the agent so you can give instructions (Esc)"
                                       : "The agent sees your feedback and continues (Esc)")
            }
        }
        .padding(14)
        .background(.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.orange.opacity(0.5)))
    }
}

/// A unified diff with added and removed lines colored.
struct DiffView: View {
    let diff: String
    var maxHeight: CGFloat = 260
    static let maxLines = 600

    var body: some View {
        let lines = diff.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("--- ") && !$0.hasPrefix("+++ ") }
        CodeScroll(maxHeight: maxHeight) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.prefix(Self.maxLines).enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : String(line))
                        .font(.caption.monospaced())
                        .foregroundStyle(color(line))
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(background(line))
                }
                if lines.count > Self.maxLines {
                    Text("… \(lines.count - Self.maxLines) more lines").font(.caption).foregroundStyle(.secondary).padding(8)
                }
            }
            .textSelection(.enabled)
            .padding(.vertical, 6)
        }
        .background(.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }

    private func color(_ line: Substring) -> Color {
        if line.hasPrefix("@@") { return .blue }
        return .primary
    }

    private func background(_ line: Substring) -> Color {
        if line.hasPrefix("+") { return .green.opacity(0.15) }
        if line.hasPrefix("-") { return .red.opacity(0.13) }
        return .clear
    }
}

/// Chooses how much the agent may do without asking.
struct PermissionModePicker: View {
    let controller: ChatController

    var body: some View {
        Menu {
            ForEach(PermissionMode.allCases, id: \.self) { mode in
                Button {
                    controller.setPermissionMode(mode)
                } label: {
                    Text(mode.displayName)
                    Text(Self.explanation(mode))
                    if mode == controller.permissionMode { Image(systemName: "checkmark") }
                }
            }
            if !controller.sessionRules.isEmpty {
                Section("Always allowed this session") {
                    ForEach(controller.sessionRules, id: \.self) { rule in
                        Button("Remove: \(rule.displayName)") { controller.sessionRules.removeAll { $0 == rule } }
                    }
                }
            }
        } label: {
            Label(controller.permissionMode.displayName, systemImage: Self.icon(controller.permissionMode))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(controller.permissionMode == .fullAuto ? .orange : .primary)
        }
        .fixedSize()
        .help("Permission mode: \(Self.explanation(controller.permissionMode))")
    }

    static func icon(_ mode: PermissionMode) -> String {
        switch mode {
        case .ask: "hand.raised"
        case .acceptEdits: "pencil"
        case .plan: "eye"
        case .fullAuto: Pref.sandbox(for: .fullAuto) == nil ? "bolt" : "bolt.shield"
        }
    }

    static func explanation(_ mode: PermissionMode) -> String {
        switch mode {
        case .ask: "Reads run freely; edits and commands ask first."
        case .acceptEdits: "Edits run freely; commands ask first."
        case .plan: "Read-only. The agent can't edit or run anything."
        case .fullAuto: Pref.sandbox(for: .fullAuto) == nil
            ? "Everything runs without asking, with no sandbox."
            : "Everything runs without asking; commands run in the sandbox."
        }
    }
}

/// Shown after the user denied an action without feedback.
struct DeniedBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
            Text("Stopped after you denied an action. Tell the agent what to do next.")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

/// The model's questions to the user (`ask_user`), together on one card: each with its options as buttons (or checkboxes
/// when several may be picked) and a box for an answer in the user's own words. One question with one pick is answered
/// by clicking; otherwise a click marks the option and Answer sends the card.
struct QuestionCard: View {
    let pending: ChatController.PendingQuestion
    let answer: ([String?]?) -> Void
    @State private var typed: [Int: String] = [:]
    @State private var picked: [Int: Set<Int>] = [:]
    /// The question whose answer box is being typed in.
    @FocusState private var typing: Int?
    /// Where the window's typing goes, and when this card appeared: its keys keep out of other fields, and a press
    /// right after it appeared (the end of the last card's answer, in the same spot) doesn't answer it (`CardKeys`).
    @Environment(\.textFocus) private var focus
    @State private var appearedAt = Date()

    private var questions: [UserQuestion] { pending.questions }
    private var oneClick: Bool { questions.count == 1 && !questions[0].multiple }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.bubble").foregroundStyle(.blue)
                Text(questions.count == 1 ? "The agent asks" : "The agent asks \(questions.count) questions").font(.headline)
            }
            ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                if index > 0 { Divider() }
                block(index, question)
            }

            HStack(spacing: 10) {
                Button(oneClick ? "Send" : "Answer") { if CardKeys.pressCounts(since: appearedAt) { send() } }
                    .keyboardShortcut(CardKeys.shortcut(.confirm, KeyboardShortcut(.return, modifiers: .command),
                                                        focus: focus, inCard: typing != nil))
                    .buttonStyle(.borderedProminent)
                    .disabled(!questions.indices.contains { reply($0) != nil })
                    .help("⌘↩ (not while typing a message)")
                Spacer()
                Button("Skip") { answer(nil) }
                    .keyboardShortcut(CardKeys.shortcut(.dismiss, KeyboardShortcut(.escape, modifiers: []),
                                                        focus: focus, inCard: typing != nil))
                    .help("Don't answer: the agent decides for itself (Esc)")
            }
        }
        .padding(14)
        .background(.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.blue.opacity(0.5)))
    }

    private func block(_ index: Int, _ question: UserQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !question.header.isEmpty {
                Text(question.header)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.12), in: Capsule())
            }
            Text(question.question).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)

            if !question.options.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(question.options.enumerated()), id: \.offset) { i, option in
                        row(index, question, i, option)
                    }
                }
            }

            TextField(question.options.isEmpty ? "Your answer" : "Or answer in your own words",
                      text: Binding(get: { typed[index] ?? "" }, set: { typed[index] = $0 }), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...6)
                .focused($typing, equals: index)
                // Return in one box of several isn't the whole card's answer.
                .onSubmit { if questions.indices.allSatisfy({ reply($0) != nil }) { send() } }
        }
    }

    @ViewBuilder
    private func row(_ index: Int, _ question: UserQuestion, _ i: Int, _ option: UserQuestion.Option) -> some View {
        let isPicked = picked[index]?.contains(i) == true
        let recommended = i == question.recommended
        if question.multiple {
            Toggle(isOn: Binding(get: { isPicked }, set: { on in
                if on { picked[index, default: []].insert(i) } else { picked[index]?.remove(i) }
            })) { label(option, recommended: recommended) }
                .toggleStyle(.checkbox)
        } else if oneClick {
            Button { if CardKeys.pressCounts(since: appearedAt) { answer([option.label]) } } label: {
                label(option, recommended: recommended).frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(i < 9 ? CardKeys.shortcut(.confirm, KeyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: .command),
                                                        focus: focus, inCard: typing != nil) : nil)
            .help(i < 9 ? "⌘\(i + 1)" : "")
        } else {
            Button { picked[index] = isPicked ? [] : [i] } label: {
                HStack(spacing: 8) {
                    Image(systemName: isPicked ? "largecircle.fill.circle" : "circle").foregroundStyle(isPicked ? .blue : .secondary)
                    label(option, recommended: recommended)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
        }
    }

    private func label(_ option: UserQuestion.Option, recommended: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(option.label)
                if recommended { Text("Recommended").font(.caption2.weight(.semibold)).foregroundStyle(.blue) }
            }
            if !option.description.isEmpty {
                Text(option.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// What's been given for a question, picks and words together; nil for nothing.
    private func reply(_ index: Int) -> String? {
        let words = (typed[index] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let choices = (picked[index] ?? []).sorted().map { questions[index].options[$0].label }
        let parts = choices + (words.isEmpty ? [] : [words])
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    private func send() {
        let replies = questions.indices.map(reply)
        guard replies.contains(where: { $0 != nil }) else { return }
        answer(replies)
    }
}

/// The model's plan (`present_plan`, B1): the plan, then approve it (switching to Accept Edits or Full Auto, and the
/// run carries on), send it back with what to change, or reject it.
struct PlanCard: View {
    let pending: ChatController.PendingPlan
    let decide: (PlanDecision) -> Void
    @State private var feedback = ""
    @FocusState private var feedbackFocused: Bool
    /// Where the window's typing goes, and when this card appeared: its keys keep out of other fields, and a press
    /// right after it appeared (the end of the last card's answer, in the same spot) doesn't answer it (`CardKeys`).
    @Environment(\.textFocus) private var focus
    @State private var appearedAt = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.clipboard").foregroundStyle(.purple)
                Text("The agent's plan").font(.headline)
                Spacer()
                if let file = pending.proposal.file {
                    Text(file.lastPathComponent).font(.caption).foregroundStyle(.secondary).help(file.path)
                }
            }
            ScrollView {
                MarkdownView(markdown: pending.proposal.plan)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 360)

            HStack(spacing: 10) {
                Button("Approve, Accept Edits") {
                    if CardKeys.pressCounts(since: appearedAt) { decide(.approve(.acceptEdits)) }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(CardKeys.shortcut(.confirm, KeyboardShortcut(.return, modifiers: .command),
                                                    focus: focus, inCard: feedbackFocused))
                .help("Edits run without asking, commands are asked about (⌘↩, not while typing a message)")
                Button("Approve, Full Auto") { if CardKeys.pressCounts(since: appearedAt) { decide(.approve(.fullAuto)) } }
                    .help("Everything runs without asking")
                Spacer()
                Button("Reject") { decide(.reject(feedback.isEmpty ? nil : feedback)) }
                    .keyboardShortcut(CardKeys.shortcut(.dismiss, KeyboardShortcut(.escape, modifiers: []),
                                                        focus: focus, inCard: feedbackFocused))
                    .help("Don't carry it out; the run stops (Esc)")
            }
            HStack(spacing: 10) {
                TextField("What should change?", text: $feedback, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .focused($feedbackFocused)
                    .onSubmit(revise)
                Button("Revise", action: revise)
                    .disabled(feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Send the plan back with your feedback; the agent stays in Plan mode")
            }
        }
        .padding(14)
        .background(.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.purple.opacity(0.5)))
    }

    private func revise() {
        let t = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        decide(.revise(t))
    }
}
