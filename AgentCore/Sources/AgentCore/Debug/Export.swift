import Foundation

/// A session written out for reading or for scripts: Markdown (a transcript with each turn's reasoning, tool calls,
/// shortened results, subagent runs, and compactions) or JSON (everything, subagent runs included).
public enum SessionExport {
    struct Document: Encodable {
        let format = "kurtkode-session"
        let version = 1
        let header: SessionHeader
        let title: String
        let model: String
        let permissionMode: PermissionMode?
        let folders: [ExtraFolder]
        let messages: [ChatMessage]
        let compactions: [Compaction]
        let subagentRuns: [Run]

        struct Run: Encodable {
            let header: SessionHeader
            let title: String
            let systemPrompt: String?
            let messages: [ChatMessage]
            let compactions: [Compaction]
            let end: SubagentEnd?
        }
    }

    public static func json(_ session: Session, runs: [Session] = []) throws -> Data {
        let doc = Document(header: session.header, title: session.displayTitle, model: session.model,
                           permissionMode: session.permissionMode, folders: session.folders, messages: session.messages,
                           compactions: session.compactions,
                           subagentRuns: runs.map { Document.Run(header: $0.header, title: $0.displayTitle, systemPrompt: $0.systemPrompt,
                                                                 messages: $0.messages, compactions: $0.compactions, end: $0.subagentEnd) })
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(doc)
    }

    /// Readable Markdown. Tool results longer than `maxResultLines` show their start and a count of the rest.
    public static func markdown(_ session: Session, runs: [Session] = [], maxResultLines: Int = 20) -> String {
        let runsByID = Dictionary(runs.map { ($0.header.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [String] = ["# " + session.displayTitle, ""]
        let stats = SessionStats(session)
        var facts = ["Model: `\(session.model)`", "Started: \(session.header.createdAt.formatted(date: .abbreviated, time: .shortened))",
                     "\(stats.turns) turns, \(stats.toolCalls) tool calls", "\(stats.promptTokens) tokens in, \(stats.completionTokens) out"]
        if let ws = session.header.workspace { facts.insert("Project: `\(ws)`", at: 1) }
        if let from = session.header.forkedFrom {
            facts.append("Forked from session \(from.uuidString.prefix(8)) \(session.header.forkedAfter == true ? "after" : "before") a turn")
        }
        out += facts.map { "- " + $0 } + [""]
        for item in SessionTimeline.items(session) {
            switch item {
            case .user(let m):
                if m.subagentReport != nil {
                    out += ["## Background subagent report", "", quote(m.content), ""]
                } else {
                    out += ["## You", "", m.content, ""]
                    if let n = m.images?.count, n > 0 { out += ["*(\(n) image\(n == 1 ? "" : "s") attached)*", ""] }
                }
            case .userCommand(let m):
                out += ["## You ran `!\(m.userCommand?.command ?? "")`", "", fence(m.userCommand?.output ?? m.content, max: maxResultLines), ""]
            case .compaction(let c):
                out += ["## Summary (the conversation was compacted: about \(c.tokensBefore / 1000)k → \(max(1, c.tokensAfter / 1000))k tokens)",
                        "", quote(c.modelText), ""]
            case .turn(let t):
                let meta = t.reply.meta
                var head = t.number > 0 ? "## Turn \(t.number) · `\(meta?.reportedModel ?? meta?.requestedModel ?? "model")`" : "## Attached"
                if let u = meta?.usage {
                    head += " · \(u.promptTokens) in" + (u.cacheSummary.map { " (\($0))" } ?? "") + ", \(u.completionTokens) out"
                }
                if let d = meta?.duration { head += String(format: " · %.1f s", d) }
                if !t.flags.isEmpty { head += " · " + t.flags.joined(separator: ", ") }
                out += [head, ""]
                if let r = t.reply.reasoning, !r.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    out += ["<details><summary>Reasoning</summary>", "", r.trimmingCharacters(in: .whitespacesAndNewlines), "", "</details>", ""]
                }
                if !t.reply.content.isEmpty { out += [t.reply.content, ""] }
                for c in t.calls {
                    let summary = TaskTool.summary(forCallNamed: c.call.name, arguments: c.call.arguments) ?? c.call.name
                    out += ["**\(summary)** `\(c.call.arguments.prefix(300))`", ""]
                    guard let r = c.result else { out += ["*(no result: the run stopped first)*", ""]; continue }
                    if let id = r.toolResult?.subagentRun, let run = runsByID[id] {
                        let s = SubagentRunSummary(run)
                        out += ["*Subagent \(s.agent) on `\(s.model)`: \(s.state), \(s.steps) turns, \(s.toolCalls) calls, "
                                + String(format: "%.1f s", s.seconds) + "*", ""]
                    }
                    let label = r.toolResult?.isError == true ? "Error" : "Result"
                    out += ["\(label):", "", fence(r.content, max: maxResultLines), ""]
                }
            }
        }
        if !runs.isEmpty {
            out += ["---", "", "# Subagent runs", ""]
            for run in runs {
                let s = SubagentRunSummary(run)
                out += ["## \(s.agent): \(s.title)", "", "- Model: `\(s.model)`; \(s.state); \(s.steps) turns, \(s.toolCalls) calls; "
                        + String(format: "%.1f s", s.seconds), ""]
                let body = markdown(run, maxResultLines: maxResultLines).split(separator: "\n", omittingEmptySubsequences: false)
                    .drop { !$0.hasPrefix("## ") }                       // its turns, without its own title block
                    .map { $0.hasPrefix("#") ? "#" + $0 : String($0) }   // one level deeper
                out += body + [""]
            }
        }
        return out.joined(separator: "\n")
    }

    static func quote(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n")
    }

    static func fence(_ text: String, max: Int) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var shown = lines.prefix(max).joined(separator: "\n")
        if lines.count > max { shown += "\n… (\(lines.count - max) more lines)" }
        let ticks = shown.contains("```") ? "````" : "```"
        return ticks + "\n" + shown + "\n" + ticks
    }
}
