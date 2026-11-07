import AgentCore
import SwiftUI

/// A reply as its steps, in the order the server sent them (thinking, text, calls), with how much of its reasoning
/// the server showed against what it billed.
struct ReplyStepsView: View {
    let reply: ChatMessage

    var body: some View {
        let (steps, ordered) = ReplySteps.steps(of: reply)
        let shown = ReasoningShown(reply)
        if steps.isEmpty {
            ContentUnavailableView("No steps", systemImage: "list.number",
                                   description: Text("This reply had no reasoning, text, or tool calls."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    header(shown, ordered: ordered)
                    ForEach(steps) { StepRow(step: $0, number: $0.id + 1, summary: shown.isSummary) }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder private func header(_ shown: ReasoningShown, ordered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let s = shown.summary {
                Text(s).font(.callout)
                if let share = shown.shownShare { ShownBar(share: share).frame(maxWidth: 360) }
            }
            Text(ordered ? "In the order the server sent them."
                 : "This server's replies are kept as reasoning, text, then calls: their order within the reply isn't known.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
    }
}

/// The billed reasoning as a bar, the shown part filled.
private struct ShownBar: View {
    let share: Double

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.purple.opacity(0.15))
                Capsule().fill(Color.purple.opacity(0.7)).frame(width: max(3, g.size.width * share))
            }
        }
        .frame(height: 6)
        .accessibilityLabel(String(format: "%.0f%% of the reasoning shown", share * 100))
    }
}

private struct StepRow: View {
    let step: ReplyStep
    let number: Int
    let summary: Bool
    /// Longer step text is cut here (a `Text` this long lays out slowly); the Overview and Response tabs have it all.
    static let maxCharacters = 6000

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary).frame(minWidth: 18, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                Label(title, systemImage: icon).font(.callout.weight(.medium)).foregroundStyle(tint)
                if let body = bodyText {
                    Text(body.count > Self.maxCharacters ? body.prefix(Self.maxCharacters) + "…" : body)
                        .font(isCall ? .caption.monospaced() : .callout)
                        .foregroundStyle(isThinking ? .secondary : .primary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var isCall: Bool { if case .call = step.kind { true } else { false } }
    private var isThinking: Bool { if case .thinking = step.kind { true } else { false } }

    private var title: String {
        switch step.kind {
        case .thinking: summary ? "Thinking (the server's summary)" : "Thinking"
        case .hiddenThinking(let bytes): "Thinking, not shown" + (bytes > 0 ? " (\(bytes / 1024) KB kept by the server, encrypted)" : "")
        case .text: "Text"
        case .call(let c): "Call " + c.name
        case .server: "Server"
        case .webSearch: "Searched the web"
        case .webResults(let r): "Found \(r.count) result\(r.count == 1 ? "" : "s")"
        }
    }

    private var icon: String {
        switch step.kind {
        case .thinking: "brain"
        case .hiddenThinking: "lock"
        case .text: "text.bubble"
        case .call: "wrench.and.screwdriver"
        case .server: "exclamationmark.arrow.triangle.2.circlepath"
        case .webSearch: "magnifyingglass"
        case .webResults: "globe"
        }
    }

    private var tint: Color {
        switch step.kind {
        case .thinking, .hiddenThinking: .purple
        case .text: .primary
        case .call: .blue
        case .server: .orange
        case .webSearch, .webResults: .teal
        }
    }

    private var bodyText: String? {
        switch step.kind {
        case .thinking(let t), .text(let t), .server(let t), .webSearch(let t): t
        case .webResults(let r): r.joined(separator: "\n")
        case .hiddenThinking: nil
        case .call(let c): Self.pretty(c.arguments)
        }
    }

    static func pretty(_ s: String) -> String {
        guard let o = try? JSONSerialization.jsonObject(with: Data(s.utf8)),
              let d = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return s }
        return String(decoding: d, as: UTF8.self)
    }
}
