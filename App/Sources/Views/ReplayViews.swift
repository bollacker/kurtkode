import AgentCore
import AppKit
import SwiftUI

/// Sends a turn's recorded request again, on the same or another endpoint and model, with a few changes, and compares
/// the reply with the original. Tools in the reply aren't run.
struct ReplaySheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let record: WireRecord
    let original: ChatMessage
    let wire: URL
    let onSaved: (ReplayRecord) -> Void

    @State private var endpointID: UUID?
    @State private var model = ""
    @State private var setTemperature = false
    @State private var temperature = 0.7
    /// "": as recorded; "default": remove it; else the value to send.
    @State private var reasoning = ""
    @State private var editSystem = false
    @State private var system = ""
    @State private var keepProvider = true
    @State private var price: (prompt: Double, completion: Double)?
    @State private var priceChecked = false
    @State private var running: Task<Void, Never>?
    @State private var live: TurnSnapshot?
    @State private var result: ReplayRecord?
    /// Compare effort levels: one replay per checked level, then a table.
    @State private var sweep = false
    @State private var sweepLevels: Set<String> = []
    @State private var sweepAt: (index: Int, level: String)?
    @State private var sweepResults: [ReplayRecord]?

    /// The levels this model takes, weakest first.
    private var levels: [String] { Replay.effortLevels(api: endpoint?.kind.api ?? record.api, model: model) }

    private var endpoint: Endpoint? { endpointID.flatMap { app.endpoint($0) } }
    private var recordedProvider: Bool { if case .object(let o) = record.request { o["provider"] != nil } else { false } }
    private var sameEndpoint: Bool { endpointID == original.meta?.endpointID }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let sweepResults {
                EffortTableView(rows: Replay.effortRows(original: original, replays: sweepResults))
                    .padding(14).frame(minHeight: 220, alignment: .top)
                Text("Each replay is saved: the Replays tab compares any of them with the original in full.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14)
                Divider()
                HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }.padding(12)
            } else if let result {
                ReplayComparisonView(original: original, replay: result).frame(minHeight: 420)
                Divider()
                HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }.padding(12)
            } else {
                form
                Divider()
                if let live { liveView(live) }
                HStack {
                    Text(estimate).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Cancel") { running?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                    Button(running == nil ? (sweep ? "Replay at \(sweepLevels.count) Levels" : "Replay") : "Replaying…") { start() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(running != nil || endpoint == nil || model.isEmpty || (sweep && sweepLevels.isEmpty))
                }
                .padding(12)
            }
        }
        .frame(width: 720)
        .task {
            endpointID = original.meta?.endpointID ?? app.endpoints.first?.id
            model = original.meta?.requestedModel ?? ""
            #if DEBUG
            // KURTKODE_DEBUG_REPLAY_SHEET="Endpoint name|model": open the sheet set to that model (nothing is sent).
            if let spec = ProcessInfo.processInfo.environment["KURTKODE_DEBUG_REPLAY_SHEET"], let bar = spec.firstIndex(of: "|"),
               let e = app.endpoints.first(where: { $0.name == String(spec[..<bar]) }) {
                endpointID = e.id
                model = String(spec[spec.index(after: bar)...])
            }
            #endif
            if case .object(let first)? = record.messages.first, first["role"] == "system", case .string(let s)? = first["content"] {
                system = s
            }
        }
        .task(id: "\(endpointID?.uuidString ?? "")|\(model)") {
            price = nil
            priceChecked = false
            guard let e = endpoint, !model.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(300))            // the model field may still be changing
            // No key: the model list is public where prices are listed (OpenRouter), and reading the key would ask for
            // Keychain access just to show an estimate.
            price = await ChatClient(endpoint: e).listPrice(of: model)
            priceChecked = true
        }
    }

    private var form: some View {
        Form {
            Section("Replay turn on") {
                Picker("Endpoint", selection: $endpointID) {
                    ForEach(app.endpoints) { e in Text(e.name).tag(UUID?.some(e.id)) }
                }
                HStack {
                    TextField("Model", text: $model)
                    Menu("Models") {
                        ForEach((endpointID.flatMap { app.catalogs[$0]?.entries } ?? []).prefix(60)) { m in
                            Button(m.id) { model = m.id }
                        }
                    }
                    .fixedSize()
                }
            }
            Section("Reasoning effort") {
                Toggle("Compare effort levels (one replay each)", isOn: $sweep)
                if sweep {
                    HStack(spacing: 14) {
                        ForEach(levels, id: \.self) { level in
                            Toggle(level, isOn: Binding(get: { sweepLevels.contains(level) },
                                                        set: { if $0 { sweepLevels.insert(level) } else { sweepLevels.remove(level) } }))
                                .toggleStyle(.checkbox)
                        }
                    }
                    Text("Each level is a full request (a different effort can't reuse Claude's cached history). Only the model "
                         + "and the effort change; the settings below don't apply.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker("Effort", selection: $reasoning) {
                        Text("As recorded").tag("")
                        Text("Model's default (leave it out)").tag("default")
                        ForEach(levels, id: \.self) { Text($0).tag($0) }
                    }
                }
            }
            Section("Change") {
                Toggle("Temperature", isOn: $setTemperature)
                if setTemperature { Slider(value: $temperature, in: 0...2, step: 0.1) { Text(String(format: "%.1f", temperature)) } }
                Toggle("Edit the system prompt", isOn: $editSystem)
                if editSystem {
                    TextEditor(text: $system).font(.callout.monospaced()).frame(height: 140)
                }
                if recordedProvider, sameEndpoint {
                    Toggle("Keep the recorded provider preferences", isOn: $keepProvider)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func liveView(_ s: TurnSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text((sweepAt.map { "Level \($0.index + 1) of \(sweepLevels.count): \($0.level) · " } ?? "")
                     + String(format: "%.1f s · ~%d tokens", s.elapsed, s.estimatedTokens)).font(.caption).foregroundStyle(.secondary)
                if !s.reasoning.isEmpty { Text(s.reasoning.suffix(600)).font(.caption).foregroundStyle(.secondary) }
                Text(s.content).font(.callout)
                ForEach(s.toolCalls, id: \.id) { c in Text("→ \(c.name) \(c.arguments)").font(.caption.monospaced()) }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 160)
    }

    /// The prompt size as recorded and what that costs at the model's list price, before anything is sent.
    private var estimate: String {
        let tokens = original.meta?.usage?.promptTokens
        let size = tokens.map { "Prompt: \($0) tokens (as recorded)." } ?? "Prompt size not recorded."
        guard priceChecked || price != nil else { return size + " Checking the price…" }
        guard let p = price else { return size + " No list price from this server (local models cost nothing)." }
        let perM = String(format: "$%.2f in / $%.2f out per million tokens", p.prompt * 1e6, p.completion * 1e6)
        let promptCost = tokens.map { String(format: "; about $%.4f for the prompt, plus the reply", Double($0) * p.prompt) } ?? ""
        return size + " " + perM + promptCost + "."
    }

    private func start() {
        guard let e = endpoint else { return }
        if sweep { return startSweep(e) }
        let options = ReplayOptions(model: model, temperature: setTemperature ? temperature : nil,
                                    reasoningEffort: reasoning.isEmpty ? nil : (reasoning == "default" ? "" : reasoning),
                                    systemPrompt: editSystem ? system : nil, keepProvider: sameEndpoint && keepProvider)
        let record = record, wire = wire
        running = Task {
            let client = ChatClient(endpoint: e, apiKey: await app.apiKey(for: e))
            let r = await Replay.run(record, client: client, endpointName: e.name, endpointID: e.id, options: options) { snap in
                await MainActor.run { live = snap }
            }
            guard !Task.isCancelled else { return }
            try? Replay.save(r, wire: wire)
            result = r
            running = nil
            onSaved(r)
        }
    }
}

extension ReplaySheet {
    /// One replay per checked level, weakest first, then the table.
    private func startSweep(_ e: Endpoint) {
        let chosen = levels.filter { sweepLevels.contains($0) }
        let record = record, wire = wire, model = model, keep = sameEndpoint && keepProvider
        running = Task {
            let client = ChatClient(endpoint: e, apiKey: await app.apiKey(for: e))
            let rs = await Replay.sweep(record, client: client, endpointName: e.name, endpointID: e.id, model: model,
                                        levels: chosen, keepProvider: keep, wire: wire) { i, snap in
                await MainActor.run { sweepAt = (i, chosen[i]); live = snap }
            }
            guard !Task.isCancelled else { return }
            sweepResults = rs
            running = nil
            rs.forEach(onSaved)
        }
    }
}

/// Replies at several effort levels as a table: what each thought, showed, did, and cost.
struct EffortTableView: View {
    let rows: [Replay.EffortRow]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
            GridRow {
                ForEach(["Effort", "Reasoning", "Shown", "Output", "Time", "Cost", "Did"], id: \.self) { Text($0).bold() }
            }
            Divider()
            ForEach(rows) { r in
                GridRow {
                    Text(r.level)
                    Text(r.reasoningTokens.map { $0.formatted() } ?? "—").monospacedDigit()
                    Text(r.shownShare.map { String(format: "%.0f%%", $0 * 100) } ?? "—").monospacedDigit()
                    Text(r.outputTokens.map { $0.formatted() } ?? "—").monospacedDigit()
                    Text(r.duration.map { String(format: "%.1f s", $0) } ?? "—").monospacedDigit()
                    Text(r.cost.map { (r.costIsEstimate ? "≈" : "") + String(format: "$%.4f", $0) } ?? "—").monospacedDigit()
                    if let e = r.error {
                        Text("failed: " + e).foregroundStyle(.red).lineLimit(2)
                    } else {
                        Label(r.actions, systemImage: r.sameCallsAsOriginal ? "equal.circle" : "arrow.triangle.branch")
                            .foregroundStyle(r.sameCallsAsOriginal ? Color.primary : Color.orange).lineLimit(2)
                            .help(r.sameCallsAsOriginal ? "The same tool calls as the original" : "Different tool calls from the original")
                    }
                }
            }
        }
        .font(.callout)
        .textSelection(.enabled)
    }
}

/// The original reply and a replay's, side by side: figures, differences in tool calls, then each reply in full.
struct ReplayComparisonView: View {
    let original: ChatMessage
    let replay: ReplayRecord

    var body: some View {
        let c = Replay.compare(original: original, replay: replay.reply)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Replay on \(replay.endpointName) · \(replay.options.model)").font(.headline)
                Text(changes).font(.caption).foregroundStyle(.secondary)
                ForEach(replay.warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                Label(c.sameToolCalls ? "Same tool calls" : "Different tool calls",
                      systemImage: c.sameToolCalls ? "checkmark.circle" : "arrow.triangle.branch")
                    .foregroundStyle(c.sameToolCalls ? .green : .orange)
                ForEach(c.toolCallDifferences, id: \.self) { Text($0).font(.caption.monospaced()).textSelection(.enabled) }
                if !c.sameText { Text("The text differs.").font(.caption).foregroundStyle(.secondary) }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 3) {
                    GridRow { Text(""); Text("Original").bold(); Text("Replay").bold() }
                    figureRow("Ended", c.original.stop, c.replay.stop)
                    figureRow("Prompt tokens", c.original.promptTokens.map(String.init), c.replay.promptTokens.map(String.init))
                    figureRow("Output tokens", c.original.completionTokens.map(String.init), c.replay.completionTokens.map(String.init))
                    figureRow("Reasoning tokens", c.original.reasoningTokens.map(String.init), c.replay.reasoningTokens.map(String.init))
                    figureRow("First token", c.original.timeToFirstToken.map { String(format: "%.2f s", $0) },
                              c.replay.timeToFirstToken.map { String(format: "%.2f s", $0) })
                    figureRow("Duration", c.original.duration.map { String(format: "%.1f s", $0) },
                              c.replay.duration.map { String(format: "%.1f s", $0) })
                }
                .font(.callout)
                HStack(alignment: .top, spacing: 12) {
                    reply("Original", original)
                    reply("Replay", replay.reply)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var changes: String {
        let o = replay.options
        var parts: [String] = []
        if let t = o.temperature { parts.append(String(format: "temperature %.1f", t)) }
        if let r = o.reasoningEffort { parts.append(r.isEmpty ? "effort: the model's default" : "effort \(r)") }
        if o.systemPrompt != nil { parts.append("edited system prompt") }
        return "Changed: " + (parts.isEmpty ? "nothing but the model and endpoint" : parts.joined(separator: ", "))
            + " · " + replay.startedAt.formatted(date: .omitted, time: .standard)
    }

    private func figureRow(_ label: String, _ a: String?, _ b: String?) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(a ?? "—").monospacedDigit()
            Text(b ?? "—").monospacedDigit().foregroundStyle(a == b ? .primary : Color.orange)
        }
    }

    private func reply(_ title: String, _ m: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            if let e = m.meta?.error { Text(e).foregroundStyle(.red).textSelection(.enabled) }
            Text(m.content.isEmpty ? "(no text)" : m.content).textSelection(.enabled)
                .foregroundStyle(m.content.isEmpty ? .secondary : .primary)
            ForEach(m.toolCalls, id: \.id) { c in
                Text("→ \(c.name) \(c.arguments)").font(.caption.monospaced()).textSelection(.enabled)
            }
            if let r = m.reasoning, !r.isEmpty {
                DisclosureGroup("Reasoning") { Text(r).font(.caption).textSelection(.enabled) }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// A turn's replays, newest first, with the selected one compared with the original.
struct ReplaysList: View {
    let original: ChatMessage
    let replays: [ReplayRecord]
    @State private var selected: UUID?

    var body: some View {
        if replays.isEmpty {
            ContentUnavailableView("No replays", systemImage: "arrow.counterclockwise",
                                   description: Text("Replay… sends this turn's recorded request again, on this or another model."))
        } else {
            VStack(spacing: 0) {
                if replays.count > 1 {
                    EffortTableView(rows: Replay.effortRows(original: original, replays: replays))
                        .padding(12)
                    Divider()
                }
                List(replays.reversed(), selection: $selected) { r in
                    let same = Replay.compare(original: original, replay: r.reply).sameToolCalls
                    HStack {
                        Image(systemName: same ? "checkmark.circle" : "arrow.triangle.branch").foregroundStyle(same ? .green : .orange)
                        Text("\(r.options.model) on \(r.endpointName)"
                             + (r.options.reasoningEffort.map { " · effort " + ($0.isEmpty ? "default" : $0) } ?? ""))
                        Spacer()
                        Text(r.startedAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                    }
                    .tag(r.id)
                }
                .frame(height: min(160, CGFloat(replays.count) * 26 + 12))
                Divider()
                if let r = replays.first(where: { $0.id == selected }) ?? replays.last {
                    ReplayComparisonView(original: original, replay: r)
                }
            }
        }
    }
}
