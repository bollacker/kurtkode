import AgentCore
import AppKit
import SwiftUI

/// The model pool: the configurations kurtkode picks on its own (subagents, retries, judging, summaries), with their
/// tier, roles, where each runs here, and what a typical task costs on it. Entries are added, changed, reordered and
/// removed here; pool.json is only read again when it was changed outside the app.
struct PoolSettings: View {
    @Environment(AppModel.self) private var app
    @AppStorage(Pref.escalationOffers) private var offers = true
    @AppStorage(Pref.escalationReview) private var review = false
    @AppStorage(Pref.subagentRetry) private var retry = false
    @State private var editing: PoolEditTarget?
    @State private var deleting: Int?
    @State private var resetting = false
    @MainActor private static var editHookRan = false

    var body: some View {
        Form {
            if let problem = app.poolProblem {
                Label(problem + ". Saving a change here replaces it, after copying it aside.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            if let notice = app.poolNotice {
                Label(notice, systemImage: "info.circle").foregroundStyle(.secondary)
            }
            Section {
                if app.pool.entries.isEmpty {
                    Text("The pool is empty, so nothing is picked automatically.").foregroundStyle(.secondary)
                }
                ForEach(Array(app.pool.entries.enumerated()), id: \.element.id) { i, e in
                    row(e, at: i)
                }
            } header: {
                HStack {
                    Text("Model pool")
                    Spacer()
                    Button("Add Entry…") { editing = PoolEditTarget(entry: .blank, index: nil) }
                }
            } footer: {
                Text("Subagents with no model chosen run on the first enabled subagent entry when the session's model is "
                     + "remote; a task that changes code, or that the agent marks as important or needing a stronger model, "
                     + "goes up a tier. Judges, reviewers and summarizers are tried in pool order. The shipped entries are "
                     + "the cost-floor study's finalists; a typical task is 20k tokens in (13k from cache) and 900 out.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Retry a subagent run that fails outright on the next retry rung", isOn: $retry)
                Text("Off by default: on the eval data a retry added one pass in 479 runs for 1% more cost, and most retries "
                     + "were of runs that had passed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Escalation") {
                Toggle("Offer a stronger model when a run on a cheaper one looks wrong", isOn: $offers)
                Toggle("Have another vendor's model review cheaper models' changes first", isOn: $review)
                    .disabled(!offers)
                Text("A card over the composer offers the next tier's main model (local → cheap → standard → frontier) when a run "
                     + "stopped early, its last test or build failed, it left todos unfinished, or you gave its reply a 👎; with "
                     + "the review on (hosted sessions only, about $0.0001 a change with deepseek), also when the reviewer finds "
                     + "problems. One click switches the model and sends it the reasons and the run's changes; nothing happens "
                     + "on its own. /escalate does it at any time.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Show pool.json in Finder") {
                    if !FileManager.default.fileExists(atPath: app.poolURL.path) { app.updatePool { _ in } }
                    NSWorkspace.shared.activateFileViewerSelecting([app.poolURL])
                }
                Button("Reload") { app.reloadPool() }
                    .help("Read pool.json again, after changing it outside kurtkode (`kurtkode pool init`, or by hand)")
                Spacer()
                Button("Reset to Shipped…") { resetting = true }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            app.reloadPool()
            // KURTKODE_POOL_EDIT=new|N (with KURTKODE_SETTINGS_TAB=pool): open the editor on a new entry or entry N,
            // once per launch, for screenshots.
            if !Self.editHookRan, let spec = ProcessInfo.processInfo.environment["KURTKODE_POOL_EDIT"] {
                Self.editHookRan = true
                if spec == "new" { editing = PoolEditTarget(entry: .blank, index: nil) }
                else if let n = Int(spec), app.pool.entries.indices.contains(n - 1) {
                    editing = PoolEditTarget(entry: app.pool.entries[n - 1], index: n - 1)
                }
            }
        }
        .sheet(item: $editing) { target in PoolEntryEditor(target: target) }
        .confirmationDialog(deleting.flatMap { app.pool.entries.indices.contains($0) ? "Remove \(app.pool.entries[$0].label) from the pool?" : nil } ?? "",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Remove", role: .destructive) {
                if let i = deleting { app.updatePool { $0.remove(at: i) } }
                deleting = nil
            }
        }
        .confirmationDialog("Replace the pool with the shipped one?", isPresented: $resetting) {
            Button("Reset to Shipped", role: .destructive) { app.updatePool { $0 = .shipped } }
        } message: {
            Text("Entries you added or changed are lost.")
        }
    }

    @ViewBuilder
    private func row(_ e: PoolEntry, at i: Int) -> some View {
        let resolved = ModelPool.resolve(e, endpoints: app.endpoints)
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Toggle(isOn: Binding(get: { e.enabled }, set: { on in app.updatePool { pool in
                    if let j = pool.entries.firstIndex(where: { $0.id == e.id }) { pool.entries[j].enabled = on }
                } })) {
                    HStack {
                        Text(e.label).fontWeight(.medium)
                        Text(e.tier.rawValue).font(.caption).foregroundStyle(.secondary)
                        if let rung = e.ladder { Text("retry rung \(rung + 1)").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Text(e.roles.map(\.rawValue).sorted().joined(separator: ", ") + " · "
                     + (resolved.map { "\($0.endpoint.name): \($0.model)" } ?? "no \(e.endpoint) endpoint set up"))
                    .font(.caption).foregroundStyle(resolved == nil ? .orange : .secondary)
                if let r = resolved, let p = app.price(r.endpoint.id, r.model) {
                    Text(TypicalTask.label(p)).font(.caption).foregroundStyle(.secondary)
                }
                if let note = e.note { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Button("Edit…") { editing = PoolEditTarget(entry: e, index: i) }
            Menu {
                actions(e, at: i)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("More actions for \(e.label)")
        }
        .contextMenu {
            Button("Edit…") { editing = PoolEditTarget(entry: e, index: i) }
            actions(e, at: i)
        }
    }

    @ViewBuilder
    private func actions(_ e: PoolEntry, at i: Int) -> some View {
        Button("Duplicate…") {
            var copy = e
            copy.ladder = nil
            editing = PoolEditTarget(entry: copy, index: nil)
        }
        Divider()
        Button("Move Up") { app.updatePool { $0.move(i, by: -1) } }.disabled(i == 0)
        Button("Move Down") { app.updatePool { $0.move(i, by: 1) } }.disabled(i == app.pool.entries.count - 1)
        Divider()
        Button("Remove…", role: .destructive) { deleting = i }
    }
}

/// The entry an editor sheet opens on: a copy of one in the pool (`index`), or a new one (nil).
struct PoolEditTarget: Identifiable {
    let id = UUID()
    var entry: PoolEntry
    var index: Int?
}

/// One pool entry's settings. Nothing changes in the pool until Save.
struct PoolEntryEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let target: PoolEditTarget
    @State private var draft: PoolEntry
    @State private var onLadder: Bool
    @State private var rung: Int
    @State private var providerOrder: String
    @State private var providerIgnore: String
    @State private var refreshing = false
    @State private var saveError: String?

    init(target: PoolEditTarget) {
        self.target = target
        _draft = State(initialValue: target.entry)
        _onLadder = State(initialValue: target.entry.ladder != nil)
        _rung = State(initialValue: target.entry.ladder ?? 0)
        _providerOrder = State(initialValue: target.entry.providers?.order.joined(separator: ", ") ?? "")
        _providerIgnore = State(initialValue: target.entry.providers?.ignore.joined(separator: ", ") ?? "")
    }

    var body: some View {
        let entry = assembled
        let problems = app.pool.problems(entry, at: target.index)
        let resolved = ModelPool.resolve(entry, endpoints: app.endpoints)
        let warnings = app.pool.warnings(entry, endpoints: app.endpoints)
        VStack(spacing: 0) {
        Form {
            Section(target.index == nil ? "New pool entry" : "Pool entry \(target.index! + 1)") {
                Picker("Endpoint", selection: $draft.endpoint) {
                    ForEach(PoolEntry.endpointKinds, id: \.id) { Text($0.label).tag($0.id) }
                    if !app.endpoints.isEmpty {
                        Divider()
                        ForEach(app.endpoints) { Text("\($0.name) (this one only)").tag($0.id.uuidString) }
                    }
                    if !knownEndpoint {
                        Divider()
                        Text("\(draft.endpoint) (not set up here)").tag(draft.endpoint)
                    }
                }
                .onChange(of: draft.endpoint) { _, new in
                    if new.lowercased() == "claude", !ModelAlias.isAlias(draft.model) { draft.model = "haiku" }
                }
                modelField
                Picker("Reasoning", selection: Binding(get: { draft.reasoning ?? "" },
                                                       set: { draft.reasoning = $0.isEmpty ? nil : $0 })) {
                    Text("Model's default").tag("")
                    ForEach(reasoningLevels, id: \.self) { Text($0 == "none" ? "Off" : $0.capitalized).tag($0) }
                }
                if !draft.model.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(resolved.map { "Runs here on \($0.endpoint.name) as \($0.model)." + priceText($0) }
                         ?? "No endpoint set up here serves this entry.")
                        .font(.caption).foregroundStyle(resolved == nil ? .orange : .secondary)
                }
            }
            Section("Use") {
                Picker("Tier", selection: $draft.tier) {
                    ForEach(PoolEntry.Tier.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                ForEach(PoolEntry.Role.allCases, id: \.self) { role in
                    Toggle(roleLabel(role), isOn: Binding(get: { draft.roles.contains(role) },
                                                          set: { on in if on { draft.roles.insert(role) } else { draft.roles.remove(role) } }))
                }
                Toggle("Enabled", isOn: $draft.enabled)
            }
            Section {
                Toggle("On the retry ladder", isOn: $onLadder)
                if onLadder {
                    Stepper("Rung \(min(rung, maxRung) + 1) of \(maxRung + 1)", value: $rung, in: 0...maxRung)
                }
            } header: {
                Text("Retry ladder")
            } footer: {
                Text("A failed subagent run that the pool chose is retried on the next rung up, never at a lower tier. "
                     + "Putting this entry at a rung moves the ones at and above it up one.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if routesProviders(resolved) {
                Section {
                    Toggle("Only providers that don't keep prompts", isOn: Binding(
                        get: { draft.providers?.dataCollection == "deny" },
                        set: { on in var p = draft.providers ?? ProviderRouting(); p.dataCollection = on ? "deny" : nil; draft.providers = p }))
                    Toggle("Only providers that take every parameter sent", isOn: Binding(
                        get: { draft.providers?.requireParameters == true },
                        set: { on in var p = draft.providers ?? ProviderRouting(); p.requireParameters = on ? true : nil; draft.providers = p }))
                    TextField("Try these providers first", text: $providerOrder, prompt: Text("OpenRouter's choice"))
                    TextField("Never use", text: $providerIgnore, prompt: Text("none"))
                    Toggle("Allow other providers too", isOn: Binding(
                        get: { draft.providers?.allowFallbacks ?? true },
                        set: { on in var p = draft.providers ?? ProviderRouting(); p.allowFallbacks = on; draft.providers = p }))
                } header: {
                    Text("Providers")
                } footer: {
                    Text("Names as openrouter.ai lists them, separated by commas (DeepInfra, Novita). A list of providers "
                         + "to try first turns off OpenRouter's habit of keeping a session on the provider that holds its "
                         + "prompt cache; \"Never use\" keeps it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Note") {
                TextField("Why it's here", text: Binding(get: { draft.note ?? "" }, set: { draft.note = $0.isEmpty ? nil : $0 }),
                          axis: .vertical)
                    .lineLimit(2...6)
            }
        }
        .formStyle(.grouped)
        Divider()
        // Kept in view below the scrolling form: what stops a save, and the buttons.
        VStack(alignment: .leading, spacing: 6) {
            ForEach(problems, id: \.self) { Label($0, systemImage: "xmark.octagon").foregroundStyle(.red) }
            ForEach(warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            if let saveError { Label(saveError, systemImage: "xmark.octagon").foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(target.index == nil ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!problems.isEmpty)
            }
        }
        .font(.callout)
        .padding(12)
        }
        .frame(width: 540, height: 500)
    }

    // MARK: Model

    @ViewBuilder
    private var modelField: some View {
        if draft.endpoint.lowercased() == "claude" {
            Picker("Model", selection: $draft.model) {
                ForEach(PoolEntry.claudeAliases, id: \.self) { Text($0.capitalized).tag($0) }
                if !draft.model.isEmpty, !ModelAlias.isAlias(draft.model) { Text(draft.model).tag(draft.model) }
            }
        } else {
            TextField("Model", text: $draft.model, prompt: Text("the id the endpoint takes, e.g. deepseek/deepseek-v4-flash"))
            if let endpoint = concreteEndpoint {
                let matches = suggestions(endpoint)
                if !matches.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(matches) { m in
                            Button(m.id) { draft.model = m.id }.buttonStyle(.link).font(.caption)
                        }
                    }
                }
                HStack {
                    Text(listNote(endpoint)).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if refreshing { ProgressView().controlSize(.small) }
                    Button("Refresh List") {
                        refreshing = true
                        Task { await app.refreshModels(endpoint.id); refreshing = false }
                    }
                    .disabled(refreshing)
                }
            }
        }
    }

    /// The endpoint the entry's models come from here (not for "claude", which takes an alias).
    private var concreteEndpoint: Endpoint? {
        guard draft.endpoint.lowercased() != "claude" else { return nil }
        var probe = draft
        probe.model = "x"
        return ModelPool.resolve(probe, endpoints: app.endpoints)?.endpoint
    }

    /// Up to eight models on the endpoint's list whose id contains what's typed, when it isn't one of them already.
    private func suggestions(_ endpoint: Endpoint) -> [ModelEntry] {
        let typed = draft.model.trimmingCharacters(in: .whitespaces).lowercased()
        guard let catalog = app.catalogs[endpoint.id], !typed.isEmpty, catalog.entry(draft.model) == nil else { return [] }
        return Array(catalog.entries.filter { $0.id.lowercased().contains(typed) }.prefix(8))
    }

    private func listNote(_ endpoint: Endpoint) -> String {
        guard let catalog = app.catalogs[endpoint.id] else { return "\(endpoint.name)'s models aren't listed yet." }
        if case .unreachable = catalog.reachability { return "\(endpoint.name) didn't answer." }
        if draft.model.isEmpty { return "\(catalog.entries.count) models on \(endpoint.name); type part of a name." }
        return catalog.entry(draft.model) == nil ? "\(endpoint.name) doesn't list \(draft.model)." : "On \(endpoint.name)'s list."
    }

    private var knownEndpoint: Bool {
        PoolEntry.endpointKinds.contains { $0.id == draft.endpoint }
            || app.endpoints.contains { $0.id.uuidString == draft.endpoint }
    }

    /// The levels the entry's API takes; a saved level from elsewhere stays listed.
    private var reasoningLevels: [String] {
        let resolved = ModelPool.resolve(draft, endpoints: app.endpoints)
        var levels = Replay.effortLevels(api: resolved?.endpoint.kind.api ?? .openai, model: resolved?.model ?? draft.model)
        if let r = draft.reasoning, !levels.contains(r) { levels.append(r) }
        return levels
    }

    private func priceText(_ r: ResolvedPoolEntry) -> String {
        app.price(r.endpoint.id, r.model).map { " " + TypicalTask.label($0) + "." } ?? ""
    }

    private func routesProviders(_ r: ResolvedPoolEntry?) -> Bool {
        r?.endpoint.baseURL.host()?.contains("openrouter") ?? (draft.endpoint.lowercased() == "openrouter")
    }

    private func roleLabel(_ role: PoolEntry.Role) -> String {
        switch role {
        case .main: "Main model (escalation offers)"
        case .subagent: "Subagents"
        case .judge: "Judging runs"
        case .summarizer: "Summaries"
        case .reviewer: "Reviewing changes"
        }
    }

    // MARK: Saving

    /// The draft as it would be saved: provider names from their fields, an empty routing dropped.
    private var assembled: PoolEntry {
        var e = draft
        func names(_ s: String) -> [String] { s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        if routesProviders(ModelPool.resolve(draft, endpoints: app.endpoints)) {
            var p = e.providers ?? ProviderRouting()
            p.order = names(providerOrder)
            p.ignore = names(providerIgnore)
            e.providers = p.isEmpty ? nil : p
        }
        if let note = e.note?.trimmingCharacters(in: .whitespacesAndNewlines) { e.note = note.isEmpty ? nil : note }
        return e
    }

    /// The highest rung this entry can take: the ladder's other entries plus one place after them.
    private var maxRung: Int {
        let others = app.pool.entries.indices.filter { $0 != target.index && app.pool.entries[$0].ladder != nil }.count
        return others
    }

    private func save() {
        var failure: String?
        let entry = assembled
        let place = onLadder ? min(rung, maxRung) : nil
        app.updatePool { pool in
            do { try pool.put(entry, at: target.index, rung: place) } catch { failure = "\(error)" }
        }
        if let failure { saveError = failure } else { dismiss() }
    }
}
