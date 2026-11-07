import AgentCore
import SwiftUI

struct SettingsView: View {
    #if DEBUG
    @State private var tab = ProcessInfo.processInfo.environment["KURTKODE_SETTINGS_TAB"] ?? "generation"
    #else
    @State private var tab = "generation"
    #endif

    var body: some View {
        TabView(selection: $tab) {
            GenerationSettings().tabItem { Label("Generation", systemImage: "slider.horizontal.3") }.tag("generation")
            PromptSettings().tabItem { Label("Prompts", systemImage: "text.quote") }.tag("prompts")
            SandboxSettings().tabItem { Label("Sandbox", systemImage: "lock.shield") }.tag("sandbox")
            EndpointSettings().tabItem { Label("Endpoints", systemImage: "server.rack") }.tag("endpoints")
            PoolSettings().tabItem { Label("Pool", systemImage: "square.stack.3d.up") }.tag("pool")
            MCPSettings().tabItem { Label("MCP", systemImage: "puzzlepiece.extension") }.tag("mcp")
        }
        .frame(width: 660, height: 500)
    }
}

struct GenerationSettings: View {
    @AppStorage(Pref.maxTokens) private var maxTokens = 8192
    @AppStorage(Pref.wallClockSeconds) private var wallClock = 600.0
    @AppStorage(Pref.nativeMaxTokens) private var nativeMaxTokens = 32768
    @AppStorage(Pref.nativeWallClockSeconds) private var nativeWallClock = 1800.0
    @AppStorage(Pref.detectRepetition) private var detectRepetition = true
    @AppStorage(Pref.maxSteps) private var maxSteps = 100
    @AppStorage(Pref.builtinSkills) private var builtinSkills = true
    @AppStorage(Pref.skillRouting) private var skillRouting = SkillRouting.auto.rawValue
    @AppStorage(Pref.defaultContextLength) private var contextLength = 32768
    @AppStorage(Pref.systemPrompt) private var systemPrompt = ""
    @AppStorage(Pref.promptStyle) private var promptStyle = ""
    /// The prompt styles on offer (Settings → Prompts can add some), read when the tab appears.
    @State private var styles = [PromptStyle.detailed.rawValue, PromptStyle.lean.rawValue]

    var body: some View {
        Form {
            Section("Limits for each reply") {
                Picker("Maximum output tokens", selection: $maxTokens) {
                    ForEach([2048, 4096, 8192, 16384, 32768], id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("Time limit", selection: $wallClock) {
                    ForEach([120.0, 300, 600, 1200, 1800], id: \.self) { Text("\(Int($0) / 60) min").tag($0) }
                }
                Toggle("Stop when the model repeats itself", isOn: $detectRepetition)
            }
            Section("Limits for Claude and Gemini replies") {
                Picker("Maximum output tokens", selection: $nativeMaxTokens) {
                    ForEach([16384, 32768, 65536], id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("Time limit", selection: $nativeWallClock) {
                    ForEach([600.0, 1200, 1800, 3600], id: \.self) { Text("\(Int($0) / 60) min").tag($0) }
                }
                Text("Their thinking counts against the output limit, and a hard turn at high effort can run long. A model's "
                     + "profile can set its own output limit.").font(.caption).foregroundStyle(.secondary)
            }
            SummarizerPicker()
            PromptCacheSettings()
            SpendingSettings()
            SafetySettings()
            NotificationSettings()
            PrivacySettings()
            WebSearchSettings()
            SubagentModelPicker()
            FallbackModelPicker()
            ChatToolsSettings()
            WireLogSettings()
            Section("Agent") {
                Picker("Pause after this many steps", selection: $maxSteps) {
                    ForEach([30, 60, 100, 200, 500], id: \.self) { Text("\($0)").tag($0) }
                }
                Toggle("Built-in skills", isOn: $builtinSkills)
                Text("Instructions for kinds of task (debugging, tests, code review, refactoring, git, releases, migrations, "
                     + "docs, …) that the agent loads when a task matches, and a line in the system prompt telling it to "
                     + "check them first. A project's or your own skill of the same name replaces a built-in one; /skills "
                     + "lists them all.").font(.caption).foregroundStyle(.secondary)
                Picker("Skill router", selection: $skillRouting) {
                    Text("Automatic").tag(SkillRouting.auto.rawValue)
                    Text("On").tag(SkillRouting.on.rawValue)
                    Text("Off").tag(SkillRouting.off.rawValue)
                }
                Text("Before each new request, the model is asked in a short side question which skill fits, and the "
                     + "agent is told to load it. Small and local models seldom load skills by themselves; asked "
                     + "directly they pick well. Automatic: on for LM Studio and other OpenAI-compatible servers, off for "
                     + "Claude and Gemini.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Models") {
                DefaultModelPicker()
                Picker("Context length when loading", selection: $contextLength) {
                    ForEach([8192, 16384, 32768, 65536, 131072], id: \.self) { Text("\($0 / 1024)k").tag($0) }
                }
            }
            Section("System prompt") {
                Picker("Working rules", selection: $promptStyle) {
                    Text("Automatic (lean for Claude and Gemini)").tag("")
                    ForEach(styles, id: \.self) { Text($0.prefix(1).uppercased() + $0.dropFirst()).tag($0) }
                }
                Text("Detailed spells out how to work (grep first, one file at a time, don't repeat calls): small local models "
                     + "need it. Frontier models do as well or better with less. A change applies to new sessions and to a "
                     + "session's next prompt (one uncached request). The Prompts tab edits the styles' text and adds "
                     + "styles.").font(.caption).foregroundStyle(.secondary)
                Text("Extra instructions, added at the end:").font(.callout)
                TextEditor(text: $systemPrompt)
                    .font(.body.monospaced())
                    .frame(minHeight: 70)
            }
        }
        .formStyle(.grouped)
        .onAppear { styles = PromptTemplates(overrides: [PromptTemplates.userFolder]).styles }
    }
}

/// When commands run in the sandbox (D9), and what it lets them do.
struct SandboxSettings: View {
    @AppStorage(Pref.sandboxUse) private var use = SandboxUse.fullAuto.rawValue
    @AppStorage(Pref.sandboxNetwork) private var network = false
    @AppStorage(Pref.sandboxWritable) private var writable = ""

    var body: some View {
        Form {
            Section {
                Picker("Run commands in the sandbox", selection: $use) {
                    ForEach(SandboxUse.allCases, id: \.self) { Text($0.displayName).tag($0.rawValue) }
                }
                Toggle("Allow network access", isOn: $network)
            } footer: {
                Text(SandboxPolicy.isAvailable
                     ? "Sandboxed commands can read everything, but write only inside the project, the temp directories, "
                       + "and the directories below. The project's .git/hooks and .git/config stay read-only. Without "
                       + "network, package installs and downloads fail. Changes apply to the next reply."
                     : "sandbox-exec isn't available on this Mac, so commands run without a sandbox.")
                    .foregroundStyle(.secondary)
            }
            Section("Also writable (one directory per line)") {
                TextEditor(text: $writable)
                    .font(.body.monospaced())
                    .frame(minHeight: 60)
            }
        }
        .formStyle(.grouped)
    }
}

struct EndpointSettings: View {
    @Environment(AppModel.self) private var app
    @State private var selection: UUID? = Endpoint.localLMStudio.id

    var body: some View {
        VStack(spacing: 0) {
            problems
            list
        }
        .onAppear { app.reloadEndpoints() }
    }

    /// Why endpoints.json or profiles.json couldn't be read or saved: changes aren't lost silently.
    @ViewBuilder private var problems: some View {
        if app.endpointsProblem != nil || app.profilesProblem != nil {
            VStack(alignment: .leading, spacing: 6) {
                ForEach([app.endpointsProblem, app.profilesProblem].compactMap { $0 }, id: \.self) { problem in
                    Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                HStack {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.endpointStore.fileURL]) }
                    Button("Reload") {
                        app.reloadEndpoints()
                        app.profilesProblem = app.profileStore.loadChecked().problem
                    }
                    if app.endpointsUnreadable {
                        Button("Replace endpoints.json with This List") { app.saveEndpoints(replacingUnreadable: true) }
                            .help("The file is copied aside first, as endpoints.json.bad-<date>.")
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
        }
    }

    private var list: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(app.endpoints) { e in
                        HStack(spacing: 8) {
                            Circle().fill(statusColor(e)).frame(width: 7, height: 7)
                            VStack(alignment: .leading) {
                                Text(e.name)
                                Text(statusText(e)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tag(e.id)
                    }
                }
                HStack {
                    Menu {
                        Section("Services") {
                            ForEach(EndpointPreset.remote) { p in Button(p.name) { add(p) } }
                        }
                        Section("Servers on this Mac or network") {
                            ForEach(EndpointPreset.local) { p in Button(p.name) { add(p) } }
                        }
                        Divider()
                        Button("Other OpenAI-compatible Server") { add(nil) }
                    } label: { Image(systemName: "plus") }
                        .menuIndicator(.hidden)
                        .fixedSize()
                    Button { confirmingRemove = true } label: { Image(systemName: "minus") }
                        .disabled(selection == nil || selection == Endpoint.localLMStudio.id)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(width: 190)
            Divider()
            if let id = selection, let current = app.endpoints.first(where: { $0.id == id }) {
                // By id, not a captured index: a save can merge in or drop endpoints another process changed.
                EndpointEditor(endpoint: Binding(get: { app.endpoints.first { $0.id == id } ?? current },
                                                 set: { e in
                                                     if let i = app.endpoints.firstIndex(where: { $0.id == id }) { app.endpoints[i] = e }
                                                 }),
                               note: notes[id])
                    .id(id)
            } else {
                Text("Select an endpoint").foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
        .confirmationDialog(removeTitle, isPresented: $confirmingRemove) {
            Button("Remove", role: .destructive) { remove() }
        } message: {
            Text(removeMessage)
        }
    }

    @State private var confirmingRemove = false
    /// Preset notes for endpoints added in this window.
    @State private var notes: [UUID: String] = [:]

    private var removeTitle: String {
        "Remove \(app.endpoints.first { $0.id == selection }?.name ?? "this endpoint")?"
    }

    private var removeMessage: String {
        let n = app.sessions.filter { $0.endpointID == selection }.count
        return (n == 0 ? "No chats use it." : "\(n) chat\(n == 1 ? "" : "s") use it; they won't be able to send until you pick another model.")
            + " Its API key is deleted from the Keychain."
    }

    private func statusColor(_ e: Endpoint) -> Color {
        switch app.catalogs[e.id]?.reachability {
        case .reachable: .green
        case .unreachable: .orange
        default: .secondary.opacity(0.4)
        }
    }

    private func statusText(_ e: Endpoint) -> String {
        switch app.catalogs[e.id]?.reachability {
        case .reachable: "\(e.kind.displayName) · \(app.catalogs[e.id]?.entries.count ?? 0) models"
        case .unreachable: "\(e.kind.displayName) · not responding"
        default: e.kind.displayName
        }
    }

    private func add(_ preset: EndpointPreset?) {
        let e = preset?.makeEndpoint()
            ?? Endpoint(name: "New endpoint", kind: .openai, baseURL: URL(string: "http://127.0.0.1:8080/v1")!)
        // Two endpoints with one name would make eval specs (name:model) ambiguous.
        var endpoint = e
        var n = 2
        while app.endpoints.contains(where: { $0.name.lowercased() == endpoint.name.lowercased() }) {
            endpoint.name = "\(e.name) \(n)"
            n += 1
        }
        app.endpoints.append(endpoint)
        app.saveEndpoints()
        var note = preset?.note ?? ""
        if preset?.needsKey == true { note = (note.isEmpty ? "" : note + " ") + "Paste your API key below, then Save & Test." }
        if !note.isEmpty { notes[endpoint.id] = note }
        selection = endpoint.id
    }

    private func remove() {
        guard let id = selection, id != Endpoint.localLMStudio.id else { return }
        app.endpoints.removeAll { $0.id == id }
        app.keychain.removeAPIKey(for: id)
        app.saveEndpoints()
        selection = Endpoint.localLMStudio.id
    }
}

struct EndpointEditor: View {
    @Environment(AppModel.self) private var app
    @Binding var endpoint: Endpoint
    var note: String?
    @State private var testModel = ""
    @AppStorage(Pref.defaultEndpointID) private var defaultEndpointID = ""
    @State private var url = ""
    @State private var apiKey = ""
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        Form {
            if let note { Text(note).font(.callout).foregroundStyle(.secondary) }
            TextField("Name", text: $endpoint.name)
            Picker("Type", selection: $endpoint.kind) {
                ForEach(Endpoint.Kind.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            TextField("Base URL", text: $url, prompt: Text("http://127.0.0.1:1234/v1"))
                .onSubmit(commitURL)
            HStack {
                SecureField("API key", text: $apiKey, prompt: Text(endpoint.usesAPIKey ? "Stored in Keychain" : "None"))
                    .onSubmit(commitKey)
                if endpoint.usesAPIKey {
                    Button("Remove Key") {
                        app.keychain.removeAPIKey(for: endpoint.id)
                        endpoint.usesAPIKey = false
                    }
                }
            }
            if endpoint.kind != .lmstudio {
                TextField("Context length", value: $endpoint.manualContextLength, format: .number,
                          prompt: Text(endpoint.kind == .openai ? "tokens, e.g. 131072"
                                       : "the model's, up to \(Endpoint.nativeContextCap.formatted())"))
            }
            Toggle("Default for new chats", isOn: Binding(
                get: { defaultEndpointID == endpoint.id.uuidString || (defaultEndpointID.isEmpty && endpoint.id == Endpoint.localLMStudio.id) },
                set: { if $0 { defaultEndpointID = endpoint.id.uuidString } }))
            HStack {
                Button("Save & Test") { commitURL(); commitKey(); test() }
                if testing { ProgressView().controlSize(.small) }
                if let testResult { Text(testResult).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
            }
            Section {
                HStack {
                    TextField("Model", text: $testModel, prompt: Text("model id, e.g. \(suggestedModel)"))
                    Button("Send a Test Message") { chatTest() }
                        .disabled(testing || testModel.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("Sends \"Reply with OK\" and allows 16 output tokens (256 for Anthropic and Gemini, whose thinking counts as output), to check the key and the model. On a paid service this costs a tiny amount.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { url = endpoint.baseURL.absoluteString }
        .onChange(of: endpoint) { app.saveEndpoints() }
    }

    private func commitURL() {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        if let u = URL(string: trimmed), u.scheme?.hasPrefix("http") == true {
            endpoint.baseURL = Endpoint.normalizedBaseURL(u)
            url = endpoint.baseURL.absoluteString          // show what will be used
        } else {
            url = endpoint.baseURL.absoluteString
        }
    }

    private func commitKey() {
        guard !apiKey.isEmpty else { return }
        do {
            try app.keychain.setAPIKey(apiKey, for: endpoint.id)
            endpoint.usesAPIKey = true
            apiKey = ""
        } catch { testResult = "Couldn't save key: \(error)" }
    }

    private var suggestedModel: String {
        app.catalogs[endpoint.id]?.entries.first(where: \.isLoaded)?.id ?? app.catalogs[endpoint.id]?.entries.first?.id
            ?? (endpoint.kind == .anthropic ? "claude-opus-5-5" : endpoint.kind == .gemini ? "gemini-3-flash-preview" : "gpt-4o-mini")
    }

    /// A real completion: reachability alone doesn't show that the key works for chat or that the model exists.
    private func chatTest() {
        commitURL(); commitKey()
        testing = true
        testResult = nil
        let model = testModel.trimmingCharacters(in: .whitespaces)
        let endpoint = endpoint
        Task {
            let client = ChatClient(endpoint: endpoint, apiKey: await app.apiKey(for: endpoint))
            // Claude and Gemini think within the output allowance: give them room and ask for as little as there is.
            let native = endpoint.kind == .anthropic || endpoint.kind == .gemini
            var request = ChatRequest(model: model, messages: [.user("Reply with OK.")], maxTokens: native ? 256 : 16)
            if native { request.reasoningEffort = "none" }
            let reply = await TurnRunner.run(client: client, request: request,
                                             limits: TurnLimits(maxTokens: request.maxTokens, wallClock: 60)) { _ in }
            testing = false
            let meta = reply.meta
            if let error = meta?.error {
                testResult = "Failed: \(error)"
            } else {
                let text = (reply.content.isEmpty ? (reply.reasoning ?? "") : reply.content).prefix(60)
                var r = String(format: "Replied in %.1f s: \"%@\"", meta?.duration ?? 0, String(text))
                if let reported = meta?.reportedModel, reported != model { r += " (answered by \(reported))" }
                if let cost = meta?.usage?.costText(digits: 5) { r += " · " + cost }
                testResult = r
            }
        }
    }

    private func test() {
        testing = true
        testResult = nil
        Task {
            await app.refreshModels(endpoint.id)
            testing = false
            switch app.catalogs[endpoint.id]?.reachability {
            case .reachable: testResult = "OK — \(app.catalogs[endpoint.id]?.entries.count ?? 0) models"
            case .unreachable(let why): testResult = "\(why) (tried \(endpoint.baseURL.appending(path: "models").absoluteString))"
            default: testResult = nil
            }
        }
    }
}

/// The server and model new chats start on. The model is picked from that server's list, since the same model can be
/// on several servers under different names; one typed in is used only when the server can't be listed.
struct DefaultModelPicker: View {
    @Environment(AppModel.self) private var app
    @AppStorage(Pref.defaultModel) private var model = "qwen/qwen3-coder-30b"
    @AppStorage(Pref.defaultEndpointID) private var endpointID = ""
    @State private var refreshing = false

    var body: some View {
        let endpoint = app.defaultEndpoint
        let catalog = app.catalogs[endpoint.id]
        let entries = catalog?.entries ?? []
        Picker("Server for new chats", selection: Binding(get: { endpoint.id }, set: { pickServer($0) })) {
            ForEach(app.endpoints) { Text($0.name).tag($0.id) }
        }
        if entries.isEmpty {
            TextField("Default model", text: $model)
            HStack {
                Text(listNote(endpoint, catalog)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if refreshing { ProgressView().controlSize(.small) }
                Button("Refresh") { refresh(endpoint.id) }.disabled(refreshing)
            }
        } else {
            Picker("Default model", selection: $model) {
                if catalog?.entry(model) == nil {
                    Text("\(model) (not on \(endpoint.name))").tag(model)
                    Divider()
                }
                ForEach(entries) { Text(label($0, endpoint)).tag($0.id) }
            }
            if catalog?.entry(model) == nil {
                Text("\(endpoint.name) doesn't list \(model). New chats there start on a model it has loaded, if any; "
                     + "otherwise their first message fails. Pick one from its list.").font(.caption).foregroundStyle(.orange)
            }
        }
        Text("A chat's own model menu changes only that chat.").font(.caption).foregroundStyle(.secondary)
    }

    /// Changes the server, and the model to one it has when the current one isn't on its list: the latest one used
    /// there, else one LM Studio has loaded. With neither, the model stays and is marked as missing.
    private func pickServer(_ id: UUID) {
        endpointID = id.uuidString
        guard let catalog = app.catalogs[id] else {
            refresh(id)
            return
        }
        fitModel(id, catalog)
    }

    private func fitModel(_ id: UUID, _ catalog: ModelCatalog) {
        guard catalog.entry(model) == nil else { return }
        let recent = app.recentModels.first { $0.endpointID == id && catalog.entry($0.model) != nil }?.model
        let loaded = app.endpoint(id)?.kind == .lmstudio ? catalog.entries.first(where: \.isLoaded)?.id : nil
        if let replacement = recent ?? loaded { model = replacement }
    }

    private func refresh(_ id: UUID) {
        refreshing = true
        Task {
            await app.refreshModels(id)
            refreshing = false
            if id == app.defaultEndpoint.id, let catalog = app.catalogs[id] { fitModel(id, catalog) }
        }
    }

    private func listNote(_ endpoint: Endpoint, _ catalog: ModelCatalog?) -> String {
        switch catalog?.reachability {
        case .unreachable: "\(endpoint.name) didn't answer, so type the model's id as that server names it."
        case .reachable: "\(endpoint.name) lists no chat models. Type the model's id as that server names it."
        default: "\(endpoint.name)'s models aren't listed yet."
        }
    }

    private func label(_ m: ModelEntry, _ endpoint: Endpoint) -> String {
        guard endpoint.kind == .lmstudio else { return m.id }
        var s = m.id
        if m.isLoaded { s += m.loadedContext.map { " — loaded, \($0 / 1024)k" } ?? " — loaded" }
        if let b = m.sizeBytes { s += String(format: " · %.1f GB", Double(b) / 1e9) }
        return s
    }
}

/// Which model subagents run on, unless their definition names one.
struct SubagentModelPicker: View {
    @Environment(AppModel.self) private var app
    @AppStorage(Pref.subagentModel) private var model = "auto"
    @AppStorage(Pref.subagentParallel) private var parallel = 4
    @AppStorage(Pref.graderModel) private var grader = "auto"
    @AppStorage(Pref.delegationAdvice) private var advice = true
    @AppStorage(Pref.delegationForce) private var force = true

    var body: some View {
        Section("Subagents") {
            Picker("Run subagents on", selection: $model) {
                Text("Automatic (the model pool)").tag("auto")
                Text("The session's own model").tag("")
                ForEach(app.recentModels) { ref in
                    Text(shortName(ref.model) + (app.endpoint(ref.endpointID).map { " (\($0.name))" } ?? "")).tag(ref.key)
                }
            }
            Text("The agent can hand a self-contained job (a search, a small task) to a subagent with a fresh context; "
                 + "only its report comes back. A fast local model here keeps an expensive one's context and cost down. "
                 + "Automatic: when the session's model is remote, the pool's cheapest subagent model (Settings → Pool), or a "
                 + "stronger one when the agent marks the task as needing it; a local session's subagents stay on its model. "
                 + "Custom agents: Markdown files in .kurtkode/agents/ or .claude/agents/.").font(.caption).foregroundStyle(.secondary)
            Picker("At once on other servers", selection: $parallel) {
                ForEach([1, 2, 3, 4, 6, 8], id: \.self) { Text("\($0)").tag($0) }
            }
            Text("Several task calls in one reply run at the same time, up to this many per model on a server other than "
                 + "this Mac's LM Studio. On LM Studio the loaded model's parallel slots decide (one slot: one at a time). "
                 + "Subagents that can edit files or run commands always go one at a time.").font(.caption).foregroundStyle(.secondary)
            Toggle("Suggest delegating broad reading", isOn: $advice)
            Text("After six or more reads in a row that fill a fifth of the context, the agent is told once that the "
                 + "explore subagent could do that reading and report back.").font(.caption).foregroundStyle(.secondary)
            Toggle("…and have it delegate then", isOn: $force).disabled(!advice)
            Text("Its next step is then a task call: on OpenRouter, OpenAI and Gemini the model must write one; elsewhere (LM "
                 + "Studio, Claude with thinking, which can't be made to call a tool) kurtkode writes it from the request and "
                 + "what has been read.").font(.caption).foregroundStyle(.secondary)
            Picker("Grade important tasks on", selection: $grader) {
                Text("Automatic (the pool's judge)").tag("auto")
                Text("No grader").tag("")
                ForEach(app.recentModels) { ref in
                    Text(shortName(ref.model) + (app.endpoint(ref.endpointID).map { " (\($0.name))" } ?? "")).tag(ref.key)
                }
            }
            Text("Every subagent run is checked automatically (does its report cite real files and lines, did its check "
                 + "pass) and rated by the agent that used it. A task marked important also goes to this model for a second "
                 + "opinion, never the run's own model. Every judgment is kept with the session.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Whether sessions keep their requests and raw responses (the Debug window's wire log).
struct WireLogSettings: View {
    @AppStorage(Pref.recordWire) private var record = true

    var body: some View {
        Section("Debugging") {
            Toggle("Record requests and responses", isOn: $record)
            Text("Each model request is kept with its session exactly as sent (images left out), with the raw reply "
                 + "stream: the Debug window (Window → Debug, ⌥⌘D) shows them. Up to 100 MB per session; API keys are never "
                 + "recorded.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Whether plain chats can use files and commands, and where.
struct ChatToolsSettings: View {
    @AppStorage(Pref.chatTools) private var enabled = true
    @AppStorage(Pref.chatFolderPath) private var folder = Pref.defaultChatFolder
    @AppStorage(Pref.autoTitles) private var autoTitles = true

    var body: some View {
        Section("Chats") {
            Toggle("Have the model title chats", isOn: $autoTitles)
            Text("After the first reply, when the first line of the request wouldn't make a title. One short request to the "
                 + "chat's own model, counted in its spending.").font(.caption).foregroundStyle(.secondary)
            Toggle("Chats can use files and run commands", isOn: $enabled)
            if enabled {
                HStack {
                    TextField("Working folder", text: $folder)
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.canCreateDirectories = true
                        if panel.runModal() == .OK, let url = panel.url { folder = url.path }
                    }
                }
            }
            Text("A chat without a project works in this folder (made when first needed), with the same tools, permission "
                 + "modes, and approvals as a project. Add other folders to a chat or a project from its folder button "
                 + "in the toolbar.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Which model takes over a turn whose tool call the server lost.
struct FallbackModelPicker: View {
    @Environment(AppModel.self) private var app
    @AppStorage(Pref.fallbackModel) private var model = ""

    var body: some View {
        Section("Lost replies") {
            Picker("When a reply is lost, retry the turn on", selection: $model) {
                Text("No other model").tag("")
                ForEach(app.recentModels) { ref in
                    Text(shortName(ref.model) + (app.endpoint(ref.endpointID).map { " (\($0.name))" } ?? "")).tag(ref.key)
                }
            }
            Text("Remote servers sometimes can't read a model's tool call and drop it: the reply arrives empty. Asking the "
                 + "model again doesn't help (it sends the same call). On OpenRouter the turn first goes to two other "
                 + "providers of the same model; then to this model, for that one turn. A local model must be loaded.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// The closed models' own web search.
struct WebSearchSettings: View {
    @AppStorage(Pref.webSearch) private var webSearch = false

    var body: some View {
        Section("Web search") {
            Toggle("Let Claude and Gemini search the web", isOn: $webSearch)
            Text("Their servers run the searches (Anthropic's web search tool, Google Search grounding) and the replies cite "
                 + "what they found; the Steps tab shows each search. Billed per search on top of tokens: Claude $10 per "
                 + "1,000 searches (in the cost estimate, up to 5 per reply); Google bills grounding separately. Local "
                 + "models have no web search.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Telling the user when a run needs them.
struct NotificationSettings: View {
    @AppStorage(Pref.notify) private var notify = true
    @AppStorage(Pref.editor) private var editor = Editor.system.rawValue

    var body: some View {
        Section("Editor") {
            Picker("Open changed files in", selection: $editor) {
                ForEach(Editor.allCases) { Text($0.displayName).tag($0.rawValue) }
            }
            Text("From the Changes tab, at the line. An editor that isn't installed falls back to the file's default app.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Notifications") {
            Toggle("Notify me when a run finishes or needs approval", isOn: $notify)
            Text("Only while kurtkode is in the background; clicking one opens the session. macOS asks for permission the "
                 + "first time. The command line rings the terminal's bell instead (approvals, and runs over 30 seconds).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Commands that are always asked about, and where standing rules live.
struct SafetySettings: View {
    @AppStorage(Pref.guardDangerous) private var guardDangerous = true
    @AppStorage(Pref.snapshots) private var snapshots = true

    var body: some View {
        Section("Undo") {
            Toggle("Snapshot the project's files when each run starts and ends", isOn: $snapshots)
            Text("The Changes tab then shows everything a run changed, commands' changes included, and can revert a file or "
                 + "part of one. Snapshots go to a separate git repository beside the sessions (the project's own .git isn't "
                 + "touched); untracked folders over 200 files or 20 MB and files over 5 MB are left out, and a folder that "
                 + "isn't a git repository gets none past 10,000 files. A session's snapshots go when it's moved to the Trash; those of "
                 + "sessions untouched for 30 days go the next time the project is snapshotted.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Safety") {
            Toggle("Always ask before destructive commands", isOn: $guardDangerous)
            Text("git reset --hard, git clean -f, force pushes, deleting branches or stashes, deleting the project or anything "
                 + "outside it, sudo, piping a download into a shell: asked about in every mode, Full Auto included, and never "
                 + "covered by \"always allow\". The same call made three times in a row is asked about too.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Standing rules go in settings files, in Claude Code's format: \"permissions\": {\"allow\": [...], \"ask\": "
                 + "[...], \"deny\": [...]} with rules like Bash(git status), Bash(npm run test:*), Edit(src/**), Read(./.env). "
                 + "Yours: ~/.kurtkode/settings.json or ~/.claude/settings.json. A project's: .kurtkode/ or .claude/ "
                 + "settings(.local).json; its allow rules need your approval once. Deny wins over ask over allow, in every mode.")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}

/// Files the agent doesn't read or change when its model is on a third-party server.
struct PrivacySettings: View {
    @AppStorage(Pref.withheldFromRemote) private var patterns = WithheldFiles.defaults.joined(separator: "\n")

    var body: some View {
        Section("Privacy") {
            Text("Never send these files to remote models (one pattern per line)").font(.callout)
            TextEditor(text: $patterns).font(.callout.monospaced()).frame(height: 110)
            Text("With a model on Anthropic, Google, OpenRouter or another server outside this Mac and your network, "
                 + "everything the agent reads goes to that provider. Files matching these patterns (a name like *.pem, or a "
                 + "path when the pattern has a slash) aren't read, searched, or changed then; templates such as .env.example "
                 + "are allowed. Commands the agent runs aren't filtered: in Ask mode you see each one first. Files you "
                 + "attach with @ are sent. Clear the list to send everything.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Restore the Default List") { patterns = WithheldFiles.defaults.joined(separator: "\n") }
        }
    }
}

/// Limits on what runs and sessions spend on paid models.
struct SpendingSettings: View {
    @AppStorage(Pref.runCostLimit) private var runLimit = 2.0
    @AppStorage(Pref.sessionCostLimit) private var sessionLimit = 0.0
    @AppStorage(RunSettings.Key.dailyCostLimit) private var dailyLimit = 0.0
    @AppStorage(RunSettings.Key.projectCostLimit) private var projectLimit = 0.0
    @AppStorage(Pref.hourlyRate) private var hourly = 30.0

    var body: some View {
        Section("Spending") {
            TextField("Pause a run after spending ($)", value: $runLimit, format: .number.precision(.fractionLength(2)))
            TextField("Stop a session after spending ($)", value: $sessionLimit, format: .number.precision(.fractionLength(2)))
            TextField("Stop all sessions after spending, a day ($)", value: $dailyLimit, format: .number.precision(.fractionLength(2)))
            TextField("Stop a project's sessions after spending, a day ($)", value: $projectLimit, format: .number.precision(.fractionLength(2)))
            Text("0 means no limit. Costs are what OpenRouter reports, or Claude and Gemini at list price; subagents and "
                 + "summaries count. A run that reaches its limit pauses before its next request (Continue allows another "
                 + "run's worth); a session that reaches its limit stops until the limit is raised; the daily limits count every "
                 + "session (or the project's) since midnight on this Mac, and reset the next day. Local models cost nothing; "
                 + "a remote model with no known price counts toward the limits at $3/$15 per million tokens.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Your time is worth ($ an hour)", value: $hourly, format: .number.precision(.fractionLength(0)))
            Text("Shown only: the Spending window and kurtkode cost report add what waiting for the runs cost at this rate, "
                 + "so a slow local model's real cost is visible beside a hosted one's charge. 0 hides it.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// How long Anthropic keeps a session's prompt cache.
struct PromptCacheSettings: View {
    @AppStorage(Pref.promptCacheTTL) private var ttl = PromptCacheTTL.auto.rawValue

    var body: some View {
        Section("Prompt cache") {
            Picker("Keep Claude's prompt cache", selection: $ttl) {
                Text("An hour for your sessions, five minutes for the rest").tag(PromptCacheTTL.auto.rawValue)
                Text("Five minutes").tag(PromptCacheTTL.fiveMinutes.rawValue)
                Text("An hour, for everything").tag(PromptCacheTTL.hour.rawValue)
            }
            Text("Each request resends the whole session; the server reads the part it has seen from its cache at a "
                 + "tenth of the input price or less. Claude's cache lasts five minutes from the last request by default: "
                 + "a pause longer than that (thinking, an approval) pays full price again for the whole session. An hour "
                 + "costs more to write (2× the input price instead of 1.25×) and pays off over pauses of 5 to 60 minutes, "
                 + "which is why the first choice gives it to the sessions you're in and not to subagents, kurtkode -p or "
                 + "the eval, whose requests follow each other within seconds (Claude Code does the same). "
                 + "Gemini caches by itself, for a short time it doesn't state.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Which model writes compaction summaries.
struct SummarizerPicker: View {
    @Environment(AppModel.self) private var app
    @AppStorage(Pref.summarizerModel) private var summarizer = ""
    @AppStorage(Pref.summaryThinking) private var thinking = true

    var body: some View {
        Section("Summaries") {
            Picker("Summarize long sessions with", selection: $summarizer) {
                Text("The session's own model").tag("")
                ForEach(app.recentModels) { ref in
                    Text(shortName(ref.model) + (app.endpoint(ref.endpointID).map { " (\($0.name))" } ?? "")).tag(ref.key)
                }
            }
            Text("The session's own model can reuse its prompt cache, so it's usually fastest. Pick another to save "
                 + "cost or to keep a slow model free.").font(.caption).foregroundStyle(.secondary)
            Toggle("Let the model think before summarizing", isOn: $thinking)
            Text("Off, summary requests ask for no reasoning (reasoning_effort: none). Each summary is steadier (about "
                 + "26 s against 11–55 s with Gemma 4), but LM Studio then can't reuse its prompt cache. Claude ignores "
                 + "this: changing its effort would discard its prompt cache.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// MCP servers: the user's own (~/.kurtkode/mcp.json) and each open project's (.mcp.json), with their state.
struct MCPSettings: View {
    @Environment(AppModel.self) private var app
    @State private var project: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    Button("Edit My Servers…") { open(MCPConfigFile.userFile()) }
                    if let project {
                        Button("Edit Project Servers…") { open(MCPConfigFile.projectFile(URL(fileURLWithPath: project))) }
                        Button("Reload") { Task { await app.reloadMCP(project) } }
                    }
                }
                HStack {
                    Button("Edit My Hooks…") { open(HookConfig.userFile(), template: Self.hooksTemplate) }
                    if let project {
                        Button("Edit Project Hooks…") { open(HookConfig.projectFile(URL(fileURLWithPath: project)), template: Self.hooksTemplate) }
                    }
                }
            } footer: {
                Text("Same format as Claude Code: {\"mcpServers\": {\"name\": {\"command\": \"npx\", \"args\": [...], \"env\": {...}}}}, "
                     + "or {\"type\": \"http\", \"url\": \"https://…/mcp\"} for a remote server (Set Token… for its token). "
                     + "Your servers run in every project; a project's .mcp.json servers ask once before they start. "
                     + "Their tools ask before each call unless the mode is Full Auto, and servers run outside the sandbox. "
                     + "Hooks (settings.json, Claude Code's format: PreToolUse, PostToolUse, UserPromptSubmit, Stop) run your "
                     + "commands as the agent works; a project's hooks ask once before they run.")
                    .foregroundStyle(.secondary)
            }
            if app.mcpProjects.isEmpty {
                Text("Open a chat in a project to start its servers.").foregroundStyle(.secondary)
            } else {
                Picker("Project", selection: Binding(get: { project ?? app.mcpProjects.first }, set: { project = $0 })) {
                    ForEach(app.mcpProjects, id: \.self) { Text(URL(fileURLWithPath: $0).lastPathComponent).tag(Optional($0)) }
                }
                if let p = project ?? app.mcpProjects.first {
                    if let problem = app.mcpConfigProblems[p] {
                        Text(problem).foregroundStyle(.red).font(.callout)
                    }
                    let servers = app.mcpStatus[p] ?? []
                    if servers.isEmpty {
                        Text("No MCP servers are configured for this project or for you.").foregroundStyle(.secondary)
                    }
                    ForEach(servers) { s in MCPServerRow(status: s, workspace: p) }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { if project == nil { project = app.mcpProjects.first } }
    }

    static let hooksTemplate = "{\n  \"hooks\": {\n  }\n}\n"

    /// Opens a config file in the default editor, creating an empty one first.
    private func open(_ url: URL, template: String = "{\n  \"mcpServers\": {\n  }\n}\n") {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(template.utf8).write(to: url)
        }
        NSWorkspace.shared.open(url)
    }
}

private struct MCPServerRow: View {
    @Environment(AppModel.self) private var app
    let status: MCPHub.Status
    let workspace: String
    @State private var showTools = false
    @State private var settingToken = false
    @State private var token = ""
    @State private var tokenError: String?

    private var account: String? {
        status.entry.config.url.map { KeychainStore.mcpAccount(server: status.entry.name, url: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(status.entry.name).fontWeight(.medium)
                Text(status.entry.scope == .user ? "yours" : "project").font(.caption2)
                    .padding(.horizontal, 5).padding(.vertical, 1).background(.quaternary, in: Capsule())
                Spacer()
                if status.entry.config.isHTTP, let account {
                    Button("Set Token…") { token = ""; settingToken = true }
                        .help("Saved in the Keychain for \(account), and sent as \"Authorization: Bearer …\"")
                    Button("Remove Token") {
                        KeychainStore.mcp.removeSecret(account: account)
                        Task { await app.restartMCP(workspace, status.entry.name) }
                    }
                }
                switch status.state {
                case .needsApproval:
                    Button("Start") { Task { try? await app.approveMCP(workspace, status.entry.name) } }
                case .ready, .failed:
                    Button("Restart") { Task { await app.restartMCP(workspace, status.entry.name) } }
                default:
                    EmptyView()
                }
            }
            // All of what Start approves for a project's server: the whole command, its environment and headers.
            Text(status.entry.config.displayCommand).font(.caption.monospaced()).foregroundStyle(.secondary)
                .lineLimit(status.state == .needsApproval ? nil : 2).textSelection(.enabled)
            ForEach(status.entry.config.approvalDetails, id: \.self) {
                Text($0).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Text(stateText).font(.caption).foregroundStyle(stateColor).textSelection(.enabled)
                .sheet(isPresented: $settingToken) { tokenSheet }
            if let tokenError { Text(tokenError).font(.caption).foregroundStyle(.red) }
            if !status.toolNames.isEmpty {
                DisclosureGroup("\(status.toolNames.count) tools", isExpanded: $showTools) {
                    Text(status.toolNames.joined(separator: ", ")).font(.caption.monospaced()).textSelection(.enabled)
                }
                .font(.caption)
            }
        }
    }

    /// Asks for the token and keeps it in the Keychain (never in a config file), then reconnects.
    private var tokenSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Token for \(status.entry.name)").font(.headline)
            Text("Sent only to \(URL(string: status.entry.config.url ?? "")?.host() ?? "this server"), as \"Authorization: Bearer …\". "
                 + "It's stored in your Keychain, not in the config file.").font(.callout).foregroundStyle(.secondary)
            SecureField("Token", text: $token).textFieldStyle(.roundedBorder).frame(width: 380)
            HStack {
                Spacer()
                Button("Cancel") { settingToken = false }
                Button("Save") {
                    guard let account else { return }
                    do {
                        try KeychainStore.mcp.setSecret(token.trimmingCharacters(in: .whitespacesAndNewlines), account: account)
                        tokenError = nil
                        Task { await app.restartMCP(workspace, status.entry.name) }
                    } catch { tokenError = "Couldn't save the token: \(error)" }
                    token = ""
                    settingToken = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
    }

    private var stateText: String {
        switch status.state {
        case .disabled: "Disabled in its config."
        case .needsApproval: "Waiting for your OK: it's in the project's .mcp.json."
        case .starting: "Starting…"
        case .ready: "Running" + (status.serverInfo.map { " (\($0))" } ?? "") + "."
        case .failed(let why): why
        }
    }

    private var stateColor: Color { if case .failed = status.state { .red } else { .secondary } }

    private var color: Color {
        switch status.state {
        case .ready: .green
        case .starting: .yellow
        case .needsApproval: .orange
        case .failed: .red
        case .disabled: .secondary.opacity(0.4)
        }
    }
}

