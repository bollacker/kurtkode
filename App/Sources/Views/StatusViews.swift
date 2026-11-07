import AgentCore
import SwiftUI

/// Chooses the model for the next turn: recent models from any endpoint, this Mac's LM Studio models,
/// and a searchable browser for everything else (OpenRouter alone lists hundreds).
struct ModelPicker: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    let controller: ChatController
    @State private var browsing = false
    @State private var editingProfile = false
    #if DEBUG
    nonisolated(unsafe) static var debugSheetShown = false
    #endif

    var body: some View {
        #if DEBUG
        let _ = BodyTrace.on ? Self._printChanges() : ()
        #endif
        Menu {
            let current = ModelRef(endpointID: controller.session.endpointID, model: controller.session.model)
            let recent = app.recentModels.filter { app.endpoint($0.endpointID) != nil }.prefix(8)
            if !recent.isEmpty {
                Section("Recent") {
                    ForEach(Array(recent)) { ref in modelButton(ref, current: current) }
                }
            }
            ForEach(app.endpoints.filter { $0.kind == .lmstudio && $0.isLocal }) { e in
                Section(e.name) {
                    ForEach(app.catalogs[e.id]?.entries ?? []) { m in
                        modelButton(ModelRef(endpointID: e.id, model: m.id), current: current)
                    }
                }
            }
            Divider()
            Button("Browse All Models…") { browsing = true }
            Button("Settings for \(shortName(controller.session.model))…") { editingProfile = true }
            if let e = controller.endpoint, e.kind == .lmstudio, e.isLocal, controller.modelEntry?.isLoaded == true {
                Button("Reload \(shortName(controller.session.model)) (frees cached memory)") {
                    Task {
                        do { try await app.loadModel(controller.session.model, on: e.id, contextLength: controller.contextLimit ?? 32768) }
                        catch { controller.notice = error.localizedDescription }
                    }
                }
                // Reloading unloads it first, which would end a reply being generated on it (here or in another chat).
                .disabled(app.modelsInUse(on: e.id).contains(controller.session.model))
            }
            Button("Refresh Models") { Task { for e in app.endpoints { await app.refreshModels(e.id) } } }
            Button("Manage Models…") { openWindow(id: "models") }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(controller.modelEntry?.isLoaded == true ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 7, height: 7)
                Text(shortName(controller.session.model))
                if let e = controller.endpoint, !(e.kind == .lmstudio && e.isLocal) {
                    Text(e.name).font(.caption).foregroundStyle(.secondary)
                }
                if controller.endpoint?.isThirdParty == true {
                    Image(systemName: "cloud").font(.caption).foregroundStyle(.secondary)
                        .accessibilityLabel("Remote model")
                }
            }
        }
        .help((controller.modelEntry.map(detail) ?? controller.session.model)
              + (controller.endpoint.map { e in e.isThirdParty
                  ? "\nRemote: what the agent reads goes to \(e.baseURL.host() ?? e.name). Files on the Privacy list (Settings → "
                    + "Generation) aren't sent." : "" } ?? ""))
        .fixedSize()
        .sheet(isPresented: $browsing) { ModelBrowser(controller: controller) }
        #if DEBUG
        // KURTKODE_OPEN_SHEET=browser|profile: open that sheet once, a few seconds after launch (catalogs load first).
        .task {
            guard !Self.debugSheetShown, let which = ProcessInfo.processInfo.environment["KURTKODE_OPEN_SHEET"] else { return }
            Self.debugSheetShown = true
            try? await Task.sleep(for: .seconds(3))
            if which == "browser" { browsing = true } else if which == "profile" { editingProfile = true }
        }
        #endif
        .sheet(isPresented: $editingProfile) {
            ProfileEditor(profile: app.profile(controller.session.endpointID, controller.session.model),
                          endpointName: controller.endpoint?.name ?? "")
        }
    }

    @ViewBuilder private func modelButton(_ ref: ModelRef, current: ModelRef) -> some View {
        Button {
            controller.setModel(ref.model, endpointID: ref.endpointID)
        } label: {
            Text(label(ref))
            if ref == current { Image(systemName: "checkmark") }
        }
    }

    private func label(_ ref: ModelRef) -> String {
        let e = app.endpoint(ref.endpointID)
        var s = shortName(ref.model)
        if let m = app.catalogs[ref.endpointID]?.entry(ref.model), e?.kind == .lmstudio {
            if m.isLoaded { s += m.loadedContext.map { " — loaded, \($0 / 1024)k" } ?? " — loaded" }
            if let b = m.sizeBytes { s += String(format: " · %.1f GB", Double(b) / 1e9) }
        }
        if let e, !(e.kind == .lmstudio && e.isLocal) { s += "  (\(e.name))" }
        if let p = app.price(ref.endpointID, ref.model) { s += " · ≈" + TypicalTask.money(TypicalTask.cost(p)) + " a task" }
        if let cost = controller.switchCostLabel(ref) { s += " · " + cost }
        return s
    }

    private func detail(_ m: ModelEntry) -> String {
        var parts = [m.id]
        if let c = m.loadedContext { parts.append("context \(c)") }
        if m.supportsTools { parts.append("tools") }
        if m.supportsVision { parts.append("vision") }
        return parts.joined(separator: " · ")
    }
}

func shortName(_ model: String) -> String { model.split(separator: "/").last.map(String.init) ?? model }

/// Every model on every endpoint, searchable.
struct ModelBrowser: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let controller: ChatController
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    // A plain field, not .searchable: in this sheet, .searchable's field kept taking and giving up focus on every
    // update (each time activating the input method over XPC), and the main thread stalled for 10 s (Debug) to
    // 61 s (seen in use) before the sheet settled.
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Choose a Model").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding([.horizontal, .top], 14)
            TextField("Search models", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .padding(14)
            List {
                ForEach(app.endpoints) { e in
                    let entries = (app.catalogs[e.id]?.entries ?? []).filter { query.isEmpty || $0.id.localizedCaseInsensitiveContains(query) }
                    if !entries.isEmpty {
                        Section("\(e.name) (\(entries.count))") {
                            ForEach(entries.prefix(200)) { m in
                                Button {
                                    controller.setModel(m.id, endpointID: e.id)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Text(m.id)
                                        if !m.supportsTools { Text("no tools").font(.caption).foregroundStyle(.orange) }
                                        Spacer()
                                        if m.isLoaded, e.kind == .lmstudio { Text("loaded").font(.caption).foregroundStyle(.green) }
                                        if e.kind != .lmstudio, let c = m.maxContext {
                                            Text("\(c / 1000)k").font(.caption).foregroundStyle(.secondary)
                                        }
                                        if let p = app.price(e.id, m.id) {
                                            Text(TypicalTask.label(p)).font(.caption).foregroundStyle(.secondary)
                                                .help("List price per million input / output tokens, and a typical small task: "
                                                      + "20k tokens in (13k from cache), 900 out, as the cost-floor bank averaged")
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 480)
        .onAppear { searchFocused = true }
    }
}

/// Edits one model's profile: context, output, sampling, prompt note, and history shaping.
struct ProfileEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State var profile: ModelProfile
    let endpointName: String
    /// Provider names as typed, comma-separated; parsed on Save.
    @State private var providerOrder = ""
    @State private var providerIgnore = ""
    @State private var providerFallbacks = true

    init(profile: ModelProfile, endpointName: String) {
        _profile = State(initialValue: profile)
        self.endpointName = endpointName
        _providerOrder = State(initialValue: profile.providers?.order.joined(separator: ", ") ?? "")
        _providerIgnore = State(initialValue: profile.providers?.ignore.joined(separator: ", ") ?? "")
        _providerFallbacks = State(initialValue: profile.providers?.allowFallbacks ?? true)
    }

    /// The levels the model's API takes; a saved level from elsewhere stays listed.
    private var reasoningLevels: [String] {
        let api = app.endpoint(profile.endpointID)?.kind.api ?? .openai
        var levels = Replay.effortLevels(api: api, model: profile.model)
        if let r = profile.reasoning, !levels.contains(r) { levels.append(r) }
        return levels
    }

    /// OpenRouter serves each model from several providers, and they differ (one dropped tool calls).
    /// A hosted model, where a change of reasoning effort costs the prompt cache (`CacheMiss.Cause.effort`).
    private var routesCacheBreak: Bool { app.endpoint(profile.endpointID).map { $0.kind != .lmstudio && Endpoint.isThirdParty($0.baseURL) } ?? false }
    private var routesProviders: Bool { app.endpoint(profile.endpointID)?.baseURL.host()?.contains("openrouter") ?? false }

    private func save() {
        func names(_ s: String) -> [String] { s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        let routing = ProviderRouting(order: names(providerOrder), ignore: names(providerIgnore), allowFallbacks: providerFallbacks)
        profile.providers = routing.isEmpty ? nil : routing
        app.saveProfile(profile)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Model", value: profile.model)
                LabeledContent("Endpoint", value: endpointName)
                if let bytes = profile.measuredPeakMemoryBytes {
                    LabeledContent("Measured peak memory", value: String(format: "%.1f GB", Double(bytes) / 1e9))
                }
            }
            Section("Generation") {
                TextField("Context length (tokens)", value: $profile.contextLength, format: .number, prompt: Text("server default"))
                TextField("Maximum output tokens", value: $profile.maxOutputTokens, format: .number, prompt: Text("app setting"))
                TextField("Temperature", value: $profile.temperature, format: .number, prompt: Text("server default"))
                Picker("Tools", selection: Binding(get: { profile.supportsTools.map { $0 ? 1 : 0 } ?? -1 },
                                                   set: { profile.supportsTools = $0 < 0 ? nil : $0 == 1 })) {
                    Text("Detect").tag(-1); Text("On").tag(1); Text("Off").tag(0)
                }
                Picker("Images", selection: Binding(get: { profile.supportsImages.map { $0 ? 1 : 0 } ?? -1 },
                                                    set: { profile.supportsImages = $0 < 0 ? nil : $0 == 1 })) {
                    Text("Detect").tag(-1); Text("On").tag(1); Text("Off").tag(0)
                }
                .help("Detect: what the server lists (LM Studio, OpenRouter, Ollama); other servers are assumed to take images")
                Picker("Reasoning", selection: Binding(get: { profile.reasoning ?? "" },
                                                       set: { profile.reasoning = $0.isEmpty ? nil : $0 })) {
                    Text("Model's default").tag("")
                    ForEach(reasoningLevels, id: \.self) { level in
                        Text(level == "none" ? "Off" : level.capitalized).tag(level)
                    }
                }
                .help("Sent with every request. Off was cheaper per success for most models in the cost-floor study, "
                      + "but cut some models' pass rates sharply: set it per model.")
                if routesCacheBreak {
                    Text("Changing it mid-session discards the session's prompt cache on most hosted models: the next "
                         + "request reads the whole session at full price, as after a model switch.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Chat template") {
                Picker("Tool-call ids", selection: $profile.history.toolCallIDs) {
                    Text("As sent").tag(HistoryShape.ToolCallIDs.asIs)
                    Text("9 letters/digits (Mistral)").tag(HistoryShape.ToolCallIDs.alphanumeric9)
                }
                Toggle("Strict user/assistant alternation (Gemma, Mistral)", isOn: $profile.history.mergeConsecutive)
                Toggle("Recover tool calls written as text (Mistral, Qwen)", isOn: $profile.history.parseTextToolCalls)
                Toggle("Send reasoning back with each turn (gpt-oss)", isOn: $profile.history.sendReasoning)
            }
            if routesProviders {
                Section {
                    TextField("Try these providers first", text: $providerOrder, prompt: Text("OpenRouter's choice"))
                    TextField("Never use", text: $providerIgnore, prompt: Text("none"))
                    Toggle("Allow other providers too", isOn: $providerFallbacks)
                } header: {
                    Text("Providers")
                } footer: {
                    Text("Names as openrouter.ai lists them, separated by commas (DeepInfra, Novita). Each reply records the "
                         + "provider that served it. A provider that loses a reply is avoided for the rest of that run.")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Added to the system prompt for this model") {
                TextEditor(text: $profile.promptAddendum).font(.body.monospaced()).frame(minHeight: 60)
            }
            HStack {
                Button("Reset to Defaults") {
                    profile = ModelProfile.defaults(endpointID: profile.endpointID, model: profile.model)
                    providerOrder = ""
                    providerIgnore = ""
                    providerFallbacks = true
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save(); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding(.bottom, 8)
    }
}

/// System-wide free memory; watched because LM Studio's use grows (spike: 0.1 GB free, swap nearly full).
struct MemoryGauge: View {
    let memory: MemoryStatus

    var body: some View {
        #if DEBUG
        let _ = BodyTrace.on ? Self._printChanges() : ()
        #endif
        HStack(spacing: 4) {
            Image(systemName: "memorychip")
            Text("\(memory.freePercent)% free").monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(color)
        .help(String(format: "%.0f GB total · swap %.1f of %.1f GB used", Double(memory.totalBytes) / 1e9,
                     Double(memory.swapUsedBytes) / 1e9, Double(memory.swapTotalBytes) / 1e9))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Free memory")
        .accessibilityValue("\(memory.freePercent) percent")
    }

    private var color: Color {
        switch memory.level {
        case .ok: .secondary
        case .low: .orange
        case .critical: .red
        }
    }
}

/// How much of the model's context the conversation fills.
struct ContextMeter: View {
    let used: Int?
    let limit: Int?

    var body: some View {
        #if DEBUG
        let _ = BodyTrace.on ? Self._printChanges() : ()
        #endif
        if let used, let limit, limit > 0 {
            let fraction = min(1, Double(used) / Double(limit))
            let tint: Color = fraction > 0.85 ? .red : fraction > 0.6 ? .orange : .accentColor
            HStack(spacing: 5) {
                ZStack {
                    Circle().stroke(.quaternary, lineWidth: 2.5)
                    Circle().trim(from: 0, to: max(0.02, fraction))
                        .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 13, height: 13)
                Text("\(Self.tokens(used)) / \(Self.tokens(limit))").font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            .help("Context used: \(used) of \(limit) tokens")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Context used")
            .accessibilityValue("\(Self.tokens(used)) of \(Self.tokens(limit)) tokens, \(Int(fraction * 100)) percent")
        }
    }

    static func tokens(_ n: Int) -> String {
        switch n {
        case ..<1000: "\(n)"
        case ..<10_000: String(format: "%.1fk", Double(n) / 1000)
        default: "\(n / 1024)k"
        }
    }
}
