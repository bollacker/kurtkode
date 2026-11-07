import AgentCore
import AppKit
import Foundation
import Observation

/// App-wide state shared by all windows: endpoints, model catalogs, memory, and sessions.
@MainActor @Observable
final class AppModel {
    let sessionStore: SessionStore
    let endpointStore: EndpointStore
    let profileStore: ProfileStore
    let keychain = KeychainStore()
    let lms = LMSCLI()
    let mcpApprovals: MCPApprovals
    let hookApprovals: HookApprovals
    let permissionApprovals: PermissionApprovals
    /// MCP servers per project (keyed by workspace path), started when a chat in the project opens.
    private var hubs: [String: MCPHub] = [:]
    /// Each hub's first load (reading the config and starting trusted servers).
    private var hubLoads: [String: Task<Void, Never>] = [:]
    /// What each project's MCP servers are doing, for the UI.
    var mcpStatus: [String: [MCPHub.Status]] = [:]
    var mcpConfigProblems: [String: String] = [:]

    var endpoints: [Endpoint]
    /// What `endpoints` was when last read from or saved to the file: the base `EndpointStore.merge` compares against.
    @ObservationIgnored private var endpointsOnDisk: [Endpoint]
    /// Why endpoints.json (or some of its entries) couldn't be read or saved, if so; shown in Settings → Endpoints.
    var endpointsProblem: String?
    /// endpoints.json isn't a JSON list, so it isn't saved over until the user replaces it.
    var endpointsUnreadable = false
    /// The same for profiles.json.
    var profilesProblem: String?
    var catalogs: [UUID: ModelCatalog] = [:]
    /// The configurations kurtkode may pick on its own (subagents, retries, judging): `pool.json`, else the shipped pool.
    let poolURL: URL
    var pool: ModelPool
    /// Why pool.json couldn't be read, if it couldn't (then nothing is routed automatically).
    var poolProblem: String?
    /// Per-model settings the user saved; everything else comes from `ModelProfile.defaults`.
    var profiles: [String: ModelProfile]
    /// Models used most recently first (endpoint + id), for the model menu.
    var recentModels: [ModelRef] = []
    /// The endpoint KURTKODE_EXTRA_ENDPOINT added for this launch only (Debug builds).
    @ObservationIgnored private var launchOnlyEndpointID: UUID?
    var memory = MemoryStatus.current()
    var sessions: [SessionSummary] = []
    /// A model load in progress, for the UI.
    var loading: (endpointID: UUID, model: String)?
    var lastLoadReport: String?

    /// Live controllers, kept here so a session keeps generating when its window shows another one.
    private var controllers: [UUID: ChatController] = [:]
    /// The session most recently selected in a main window (the Debug window follows it).
    var lastSelectedSession: UUID?
    /// A subagent run to show in the Debug window (a task card's "Open in Debug"); the window clears it.
    var debugFocus: DebugFocus?

    /// What the last change to the pool reported: where an unreadable pool.json was copied, or why saving failed.
    var poolNotice: String?

    /// Changes the pool and saves it. An unreadable pool.json is copied aside first, so the hand edits that broke it
    /// aren't lost.
    func updatePool(_ change: (inout ModelPool) -> Void) {
        change(&pool)
        poolNotice = nil
        do {
            if poolProblem != nil, let copy = try ModelPool.backUpUnreadable(poolURL) {
                poolNotice = "The unreadable pool.json was copied to \(copy.lastPathComponent) before it was replaced."
            }
            try pool.save(poolURL)
            poolProblem = nil
        } catch {
            poolNotice = "The pool couldn't be saved: \(error.localizedDescription)"
        }
    }

    /// Reads pool.json again (after it was changed outside the app).
    func reloadPool() {
        (pool, poolProblem) = ModelPool.loadChecked(poolURL)
        poolNotice = nil
    }

    /// A model's list price: what its server lists (OpenRouter), else kurtkode's table (Claude, Gemini); nil: unpriced.
    func price(_ endpointID: UUID, _ model: String) -> PriceList.Price? {
        if let p = catalogs[endpointID]?.entry(model)?.price { return p }
        guard let e = endpoints.first(where: { $0.id == endpointID }), e.kind != .lmstudio else { return nil }
        return PriceList.price(api: e.kind.api, model: model)
    }

    /// The session's controller if it's open, without opening it (which would start its project's MCP servers).
    func existingController(_ id: UUID) -> ChatController? { controllers[id] }

    init() {
        Pref.register()
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "kurtkode")
        sessionStore = SessionStore(root: support.appending(path: "sessions"))
        endpointStore = EndpointStore(fileURL: support.appending(path: "endpoints.json"))
        let loadedEndpoints = endpointStore.loadChecked()
        endpoints = loadedEndpoints.value
        endpointsOnDisk = loadedEndpoints.value
        endpointsProblem = loadedEndpoints.problem
        endpointsUnreadable = loadedEndpoints.unreadable
        HangMonitor.shared.start()
        // Load the code highlighter's JavaScript off the main thread now, before the first code block needs it.
        Task.detached(priority: .utility) { await CodeHighlighter.shared.warmUp() }
        profileStore = ProfileStore(fileURL: support.appending(path: "profiles.json"))
        poolURL = support.appending(path: "pool.json")
        (pool, poolProblem) = ModelPool.loadChecked(poolURL)
        mcpApprovals = MCPApprovals(fileURL: support.appending(path: "mcp-approvals.json"))
        hookApprovals = HookApprovals(fileURL: support.appending(path: "hook-approvals.json"))
        permissionApprovals = PermissionApprovals(fileURL: support.appending(path: "permission-approvals.json"))
        // Server processes and running commands (the agent's, and !commands) shouldn't outlive the app.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in
            RunningCommands.stopAll()
            StdioTransport.terminateAll()
        }
        let loadedProfiles = profileStore.loadChecked()
        profiles = loadedProfiles.value
        profilesProblem = loadedProfiles.problem
        // OpenRouter's records of earlier replies (they lag by minutes), checked once the app has settled, then every
        // ten minutes for the last two days' (runs no longer wait for them at their end).
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            var since = Date().addingTimeInterval(-30 * 86_400)
            while !Task.isCancelled {
                guard let self else { return }
                let store = sessionStore
                await CostReconciler.run(store: store, since: since, client: { [weak self] id in
                    guard let self, let e = await self.endpoint(id), let key = await self.apiKey(for: e) else { return nil }
                    return ChatClient(endpoint: e, apiKey: key)
                })
                since = Date().addingTimeInterval(-2 * 86_400)
                try? await Task.sleep(for: .seconds(600))
            }
        }
        recentModels = (Pref.d.array(forKey: "recentModels") as? [String] ?? []).compactMap(ModelRef.init(key:))
        #if DEBUG
        // KURTKODE_EXTRA_ENDPOINT=Name=http://host:port/v1 adds an OpenAI-style endpoint for this launch only
        // (never saved), e.g. a mock server for performance tests.
        if let spec = ProcessInfo.processInfo.environment["KURTKODE_EXTRA_ENDPOINT"],
           let eq = spec.firstIndex(of: "="), let url = URL(string: String(spec[spec.index(after: eq)...])) {
            let extra = Endpoint.launchOnly(name: String(spec[..<eq]), url: url, manualContextLength: 32768)
            endpoints.append(extra)
            launchOnlyEndpointID = extra.id
        }
        #endif

        Task { [weak self] in
            while let self {
                self.memory = MemoryStatus.current()
                self.measureLoadedModel()
                try? await Task.sleep(for: .seconds(3))
            }
        }
        Task {
            await refreshSessions()
            for e in endpoints { await refreshModels(e.id) }
        }
        // Back from the terminal: sessions the command line added to are reloaded (idle ones only).
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.reloadEndpoints()
                for c in self?.controllers.values.map({ $0 }) ?? [] { await c.reloadIfChangedElsewhere() }
            }
        }
    }

    // MARK: Endpoints

    func endpoint(_ id: UUID) -> Endpoint? { endpoints.first { $0.id == id } }

    var defaultEndpoint: Endpoint {
        let id = Pref.d.string(forKey: Pref.defaultEndpointID).flatMap(UUID.init(uuidString:))
        return id.flatMap(endpoint) ?? endpoints[0]
    }

    /// Reads an endpoint's API key off the main thread. A Keychain read can block on a macOS permission
    /// dialog (after every rebuild of an ad-hoc-signed app), and on the main thread that froze the UI.
    func apiKey(for endpoint: Endpoint) async -> String? {
        guard endpoint.usesAPIKey else { return nil }
        #if DEBUG
        // Test instances: a fresh build reading a key puts a Keychain prompt on the user's screen.
        if ProcessInfo.processInfo.environment["KURTKODE_NO_KEYCHAIN"] == "1" { return nil }
        #endif
        let keychain = keychain, id = endpoint.id
        return await Task.detached(priority: .userInitiated) { keychain.apiKey(for: id) }.value
    }

    /// Saves the list merged with the file as it is now, so an endpoint `kurtkode endpoint add` wrote while the app ran
    /// isn't erased. A file that can't be read isn't written over: the change stays in memory and Settings says why.
    func saveEndpoints(replacingUnreadable: Bool = false) {
        let current = endpointStore.loadChecked()
        endpointsUnreadable = current.unreadable
        if current.unreadable, !replacingUnreadable {
            endpointsProblem = current.problem
            return
        }
        let merged = current.unreadable ? endpoints
            : EndpointStore.merge(base: endpointsOnDisk, mine: endpoints, theirs: current.value)
        // A launch-only endpoint from KURTKODE_EXTRA_ENDPOINT isn't saved.
        let saved = merged.filter { $0.id != launchOnlyEndpointID }
        do {
            try endpointStore.save(saved, replacingUnreadable: replacingUnreadable)
            endpointsOnDisk = saved
            endpointsProblem = current.unreadable ? nil : current.problem
            endpointsUnreadable = false
        } catch {
            endpointsProblem = "Endpoints weren't saved: \(error.localizedDescription)"
        }
        if merged != endpoints { endpoints = merged }
    }

    /// Picks up changes another process (the command line) made to endpoints.json since it was last read or saved.
    func reloadEndpoints() {
        let current = endpointStore.loadChecked()
        endpointsProblem = current.problem
        endpointsUnreadable = current.unreadable
        guard !current.unreadable, current.value != endpointsOnDisk else { return }
        let merged = EndpointStore.merge(base: endpointsOnDisk, mine: endpoints, theirs: current.value)
        endpointsOnDisk = current.value
        guard merged != endpoints else { return }
        let added = merged.filter { e in !endpoints.contains { $0.id == e.id } }
        endpoints = merged
        Task { for e in added { await refreshModels(e.id) } }
    }

    // MARK: Models

    /// The profile for a model: the user's saved one, else the defaults for its family, with what the
    /// server reports filled in.
    func profile(_ endpointID: UUID, _ model: String) -> ModelProfile {
        var p = profiles[ModelProfile.key(endpointID, model)] ?? ModelProfile.defaults(endpointID: endpointID, model: model)
        if p.supportsTools == nil { p.supportsTools = catalogs[endpointID]?.entry(model)?.supportsTools }
        return p
    }

    /// Saves one profile into profiles.json as it is now (profiles saved elsewhere meanwhile are kept). When the file
    /// can't be read the profile applies for this launch only, and Settings → Endpoints says why.
    func saveProfile(_ p: ModelProfile) {
        profiles[p.key] = p
        do {
            var all = try profileStore.save(p)
            for (key, mine) in profiles where all[key] == nil { all[key] = mine }
            profiles = all
            profilesProblem = profileStore.loadChecked().problem
        } catch {
            profilesProblem = "Model settings weren't saved: \(error.localizedDescription)"
            Log.app.error("saving profiles failed: \(error)")
        }
    }

    func noteUsed(_ ref: ModelRef) {
        // A launch-only server (a test's mock) isn't one to offer again later.
        guard ref.endpointID != launchOnlyEndpointID else { return }
        recentModels.removeAll { $0 == ref }
        recentModels.insert(ref, at: 0)
        recentModels = Array(recentModels.prefix(12))
        Pref.d.set(recentModels.map(\.key), forKey: "recentModels")
    }

    func refreshModels(_ endpointID: UUID) async {
        guard let e = endpoint(endpointID) else { return }
        let start = Date()
        // Model lists usually need no key; ask for it (and maybe a Keychain prompt) only if the server insists.
        let catalog = await ModelCatalog.fetch(endpoint: e) { [weak self] in
            await self?.apiKey(for: e)
        }
        catalogs[endpointID] = catalog
        Log.app.notice("models for \(e.name, privacy: .public): \(catalog.entries.count) in \(Date().timeIntervalSince(start), format: .fixed(precision: 1))s, \(String(describing: catalog.reachability), privacy: .public)")
    }

    /// Loads a model on a local LM Studio: other models first, then this one with an explicit context and
    /// one parallel slot. Reports the measured change in free memory, since file size is a poor estimate.
    /// Loads a model on this Mac's LM Studio with an explicit context and one parallel slot, keeping
    /// other loaded models when they all fit: the new model's expected footprint (measured peak, or file
    /// size × 1.3 until measured) must leave 25% of memory free. Otherwise the least recently used models
    /// are unloaded first. Refuses when even alone it would start below 30% free.
    func loadModel(_ model: String, on endpointID: UUID, contextLength: Int) async throws {
        guard let e = endpoint(endpointID), e.kind == .lmstudio, e.isLocal else { return }
        loading = (endpointID, model)
        defer { loading = nil }
        let busy = modelsInUse(on: endpointID)
        if catalogs[endpointID]?.entry(model)?.isLoaded == true {   // a reload
            guard !busy.contains(model) else { throw LoadError(message: Self.inUseMessage(model, verb: "reloading")) }
            try? await lms.unload(model)
        }

        let total = Double(memory.totalBytes)
        let expected = Double(expectedFootprint(model, on: endpointID))
        var unloaded: [String] = []
        func fits() -> Bool { Double(MemoryStatus.current().freeBytes) - expected >= total * 0.25 }
        // Least recently used first; models never used this session go before any that were.
        let recency = recentModels.filter { $0.endpointID == endpointID }.map(\.model)
        // A model a chat is generating on isn't unloaded: its reply would die mid-stream.
        let loaded = (catalogs[endpointID]?.entries ?? []).filter { $0.isLoaded && $0.id != model }.map(\.id)
        var loadedOthers = loaded.filter { !busy.contains($0) }
        loadedOthers.sort { (recency.firstIndex(of: $0) ?? Int.max) > (recency.firstIndex(of: $1) ?? Int.max) }
        while !fits(), let victim = loadedOthers.first {
            try? await lms.unload(victim)
            unloaded.append(victim)
            loadedOthers.removeFirst()
            try? await Task.sleep(for: .seconds(2))
        }
        let kept = loaded.filter { busy.contains($0) }
        if !fits(), !kept.isEmpty {
            throw LoadError(message: "Not enough memory for \(model) without unloading \(kept.map(shortName).joined(separator: ", ")), "
                            + "which a chat is generating on. Load it once that run ends.")
        }
        let before = MemoryStatus.current()
        guard before.freePercent >= 30 else {
            throw LoadError(message: "Only \(before.freePercent)% of memory is free; not loading \(model).")
        }
        try await lms.load(model, contextLength: contextLength, parallel: 1)
        try? await Task.sleep(for: .seconds(2))
        let after = MemoryStatus.current()
        memory = after
        // Baseline for measuring what the model really uses once it generates (MLX allocates then).
        loadBaselines[ModelProfile.key(endpointID, model)] = before.freeBytes
        lastLoadReport = "Loaded \(model) with \(contextLength / 1024)k context"
            + (unloaded.isEmpty ? "" : " (unloaded \(unloaded.map(shortName).joined(separator: ", ")) to make room)")
            + ". Free memory \(before.freePercent)% → \(after.freePercent)%."
        Log.app.notice("\(self.lastLoadReport ?? "", privacy: .public)")
        await refreshModels(endpointID)
    }

    /// What a model is expected to take once it runs: its measured peak, or its file size × 1.3 until measured.
    func expectedFootprint(_ model: String, on endpointID: UUID) -> Int64 {
        profile(endpointID, model).measuredPeakMemoryBytes
            ?? Int64(Double(catalogs[endpointID]?.entry(model)?.sizeBytes ?? 0) * 1.3)
    }

    /// Free memory after loading `model` if nothing else were unloaded, in percent (can be negative).
    func freePercentAfterLoading(_ model: String, on endpointID: UUID) -> Int {
        let free = Double(memory.freeBytes) - Double(expectedFootprint(model, on: endpointID))
        return Int((free / Double(max(1, memory.totalBytes)) * 100).rounded())
    }

    /// Models on this endpoint that a chat (or one of its subagents) is generating on now: unloading one would end
    /// that reply mid-stream.
    func modelsInUse(on endpointID: UUID) -> Set<String> {
        var out: Set<String> = []
        for c in controllers.values where c.isGenerating {
            if c.session.endpointID == endpointID { out.insert(c.session.model) }
            // A subagent row names only its model, so one of that name on any endpoint counts.
            for r in c.subagents where r.isRunning { out.insert(r.model) }
        }
        return out
    }

    static func inUseMessage(_ model: String, verb: String) -> String {
        "A chat is generating on \(shortName(model)); stop it or wait for it to finish before \(verb) it."
    }

    func unloadModel(_ model: String, on endpointID: UUID) async throws {
        guard !modelsInUse(on: endpointID).contains(model) else {
            throw LoadError(message: Self.inUseMessage(model, verb: "unloading"))
        }
        try await lms.unload(model)
        loadBaselines[ModelProfile.key(endpointID, model)] = nil
        try? await Task.sleep(for: .seconds(1))
        memory = MemoryStatus.current()
        await refreshModels(endpointID)
    }

    func unloadAll(on endpointID: UUID) async throws {
        let loaded = Set((catalogs[endpointID]?.entries ?? []).filter(\.isLoaded).map(\.id))
        if let model = modelsInUse(on: endpointID).intersection(loaded).sorted().first {
            throw LoadError(message: Self.inUseMessage(model, verb: "unloading"))
        }
        try await lms.unloadAll()
        loadBaselines = loadBaselines.filter { !$0.key.hasPrefix(endpointID.uuidString) }
        try? await Task.sleep(for: .seconds(1))
        memory = MemoryStatus.current()
        await refreshModels(endpointID)
    }

    /// What a loaded model uses now, when that can be measured: it's the only local model loaded, and
    /// kurtkode loaded it (so free memory from just before is known).
    func currentUse(_ model: String, on endpointID: UUID) -> Int64? {
        let local = endpoints.filter { $0.kind == .lmstudio && $0.isLocal }
        let loaded = local.flatMap { e in (catalogs[e.id]?.entries ?? []).filter(\.isLoaded).map { ModelRef(endpointID: e.id, model: $0.id) } }
        guard loaded == [ModelRef(endpointID: endpointID, model: model)],
              let baseline = loadBaselines[ModelProfile.key(endpointID, model)] else { return nil }
        return Int64(baseline) - Int64(memory.freeBytes)
    }

    /// True when a loaded model uses far more than its file: MLX's buffer cache grows during long runs
    /// (36 GB for a 17 GB model), and reloading gives it back.
    func shouldOfferReload(_ model: String, on endpointID: UUID) -> Bool {
        guard let used = currentUse(model, on: endpointID),
              let size = catalogs[endpointID]?.entry(model)?.sizeBytes, size > 0 else { return false }
        return Double(used) > Double(size) * 1.8 && used - size > 4_000_000_000
    }

    struct LoadError: LocalizedError { let message: String; var errorDescription: String? { message } }

    /// Free memory just before each local model was loaded, by profile key.
    private var loadBaselines: [String: UInt64] = [:]

    /// While exactly one local model is loaded, what it uses is (free before it loaded) − (free now).
    /// The peak is saved to its profile, so later loads can predict its footprint.
    private func measureLoadedModel() {
        let local = endpoints.filter { $0.kind == .lmstudio && $0.isLocal }
        let loaded = local.flatMap { e in (catalogs[e.id]?.entries ?? []).filter(\.isLoaded).map { ModelRef(endpointID: e.id, model: $0.id) } }
        guard loaded.count == 1, let ref = loaded.first, let baseline = loadBaselines[ref.key] else { return }
        let used = Int64(baseline) - Int64(memory.freeBytes)
        var p = profile(ref.endpointID, ref.model)
        // Save only meaningful increases (at least 0.5 GB), to avoid rewriting the file constantly.
        if used > (p.measuredPeakMemoryBytes ?? 0) + 500_000_000 {
            p.measuredPeakMemoryBytes = used
            saveProfile(p)
        }
    }

    func startLocalServer() async throws {
        try await lms.startServer()
        for e in endpoints where e.isLocal { await refreshModels(e.id) }
    }

    // MARK: MCP servers

    /// One spelling per project folder for the MCP tables (/tmp and /private/tmp are one folder): a hub found under
    /// another spelling than its session's missed an approval made through the other (seen with the test hook).
    static func mcpKey(_ workspace: String) -> String { Workspace(path: workspace).root.path }

    /// The project's MCP hub, created (and its trusted servers started) on first use.
    @discardableResult
    func mcpHub(for workspace: String) -> MCPHub {
        let workspace = Self.mcpKey(workspace)
        if let hub = hubs[workspace] { return hub }
        let hub = MCPHub(workspace: URL(fileURLWithPath: workspace), approvals: mcpApprovals)
        hubs[workspace] = hub
        hubLoads[workspace] = Task {
            await hub.onChange { [weak self] in Task { @MainActor in await self?.refreshMCPStatus(workspace) } }
            await hub.reload()
        }
        return hub
    }

    func refreshMCPStatus(_ workspace: String) async {
        guard let hub = hubs[workspace] else { return }
        mcpStatus[workspace] = await hub.statusList
        mcpConfigProblems[workspace] = await hub.configProblem
    }

    /// The project's MCP tools, once its first load and any starting servers are done (at most 20 s:
    /// a first `npx` run can take longer, and its tools then join the next reply).
    func mcpTools(for workspace: String) async -> [any Tool] {
        let workspace = Self.mcpKey(workspace)
        let hub = mcpHub(for: workspace)
        if let load = hubLoads[workspace] {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await load.value }
                group.addTask { try? await Task.sleep(for: .seconds(20)) }
                await group.next()
                group.cancelAll()
            }
        }
        await hub.waitForStartup(timeout: 5)
        return await hub.allTools
    }

    var mcpProjects: [String] { hubs.keys.sorted() }

    func reloadMCP(_ workspace: String) async { await hubs[Self.mcpKey(workspace)]?.reload() }
    func restartMCP(_ workspace: String, _ name: String) async { await hubs[Self.mcpKey(workspace)]?.restart(name) }
    func approveMCP(_ workspace: String, _ name: String) async throws { try await hubs[Self.mcpKey(workspace)]?.approve(name) }

    // MARK: Sessions

    func refreshSessions() async {
        sessions = (try? await sessionStore.list()) ?? []
    }

    /// Starts a chat. With a workspace it's an agent session that can use tools on that folder.
    /// Set by `newSession(select: true)`; windows showing the session it replaced switch to it.
    var requestedSelection: UUID?

    func newSession(endpointID: UUID? = nil, model: String? = nil, workspace: String? = nil, select: Bool = false) async throws -> UUID {
        // Store the resolved path (/tmp and /private/tmp are one folder), as the command-line tool does.
        let workspace = workspace.map { Workspace(path: $0).root.path }
        let e = endpointID.flatMap(endpoint) ?? defaultEndpoint
        let catalog = catalogs[e.id]
        let preferred = model ?? Pref.d.string(forKey: Pref.defaultModel) ?? ""
        let chosen = catalog?.entry(preferred) != nil ? preferred
            : (catalog?.entries.first(where: \.isLoaded)?.id ?? preferred)
        // The file is created with the first message, so abandoned empty chats leave nothing behind.
        let header = SessionHeader(endpointID: e.id, model: chosen, workspace: workspace)
        controllers[header.id] = ChatController(app: self, session: Session(header: header, messages: [], model: chosen),
                                                isPersisted: false)
        sessions.insert(SessionSummary(id: header.id, title: "New chat", model: chosen, workspace: workspace,
                                       updatedAt: Date(), messageCount: 0), at: 0)
        if select { requestedSelection = header.id }
        return header.id
    }

    /// A new session from `session` before or after the turn whose reply is `reply`, shown in a main window.
    @discardableResult
    func forkSession(_ session: Session, atReply reply: UUID, turn: Int, after: Bool) async throws -> UUID {
        let title = "\(session.displayTitle) (fork \(after ? "after" : "before") turn \(turn))"
        let fork = try await sessionStore.fork(session, atReply: reply, after: after, title: title)
        await refreshSessions()
        requestedSelection = fork.header.id
        return fork.header.id
    }

    /// A new session with everything before `message` (nil: the whole conversation), shown in a main window. Forking at
    /// a request puts that request in the new session's composer, to send it differently.
    @discardableResult
    func forkSession(_ session: Session, before message: UUID?) async throws -> UUID {
        let fork = try await sessionStore.fork(session, before: message, title: "\(session.displayTitle) (fork)")
        await refreshSessions()
        if let c = await controller(for: fork.header.id) {
            if let m = session.messages.first(where: { $0.id == message }) {
                c.draft = m.content
                c.pendingImages = m.images ?? []
            }
            c.notice = "Forked: a new conversation from here. Files on disk are as they are now, not as they were then."
        }
        requestedSelection = fork.header.id
        return fork.header.id
    }

    /// A chat in a new worktree of the project, on a branch of its own, shown in a main window.
    @discardableResult
    func newWorktreeSession(project: String, name: String) async throws -> UUID {
        let worktree = try await GitRepo(root: URL(fileURLWithPath: project, isDirectory: true)).addWorktree(name: name)
        // On the model you're working with, as /clear does.
        let current = lastSelectedSession.flatMap { controllers[$0]?.session }
        return try await newSession(endpointID: current?.endpointID, model: current?.model, workspace: worktree.path, select: true)
    }

    /// Opens a file at its line, in the editor Settings names, or its default app.
    func openInEditor(_ url: URL, line: Int? = nil) {
        let editor = Editor(rawValue: Pref.d.string(forKey: Pref.editor) ?? "") ?? .system
        guard let (tool, arguments) = editor.command(path: url.path, line: line) else {
            NSWorkspace.shared.open(url)
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = arguments
        if (try? p.run()) == nil { NSWorkspace.shared.open(url) }
    }

    /// Workspace of a session, from its summary.
    func workspace(of id: UUID?) -> String? {
        guard let id else { return nil }
        return sessions.first { $0.id == id }?.workspace
    }

    func controller(for id: UUID) async -> ChatController? {
        if let c = controllers[id] {
            // Shown again: pick up what the command line may have added meanwhile.
            await c.reloadIfChangedElsewhere()
            return c
        }
        guard let session = try? await sessionStore.load(id) else { return nil }
        if let c = controllers[id] { return c }      // created while loading
        let c = ChatController(app: self, session: session)
        controllers[id] = c
        return c
    }

    func rename(_ id: UUID, to title: String) async {
        if let c = controllers[id] {
            c.rename(title)
        } else {
            try? await sessionStore.append(.title(title), to: id)
            await refreshSessions()
        }
    }

    /// Sessions moved to the Trash since launch: every window drops a selection that points at one.
    var trashedSessions: Set<UUID> = []

    func trash(_ id: UUID) async {
        controllers[id]?.stop()
        let persisted = controllers[id]?.isPersisted ?? true
        // A window still showing it can't send into it, and the stopping run's last writes don't make the file again.
        controllers[id]?.sessionFileGone = true
        controllers[id] = nil
        trashedSessions.insert(id)
        if persisted { try? await sessionStore.trash(id) }
        sessions.removeAll { $0.id == id }
    }

    func updateSummary(for session: Session) {
        guard let i = sessions.firstIndex(where: { $0.id == session.header.id }) else { return }
        sessions[i].title = session.displayTitle
        sessions[i].model = session.model
        sessions[i].messageCount = session.messages.count
        sessions[i].updatedAt = Date()
        let s = sessions.remove(at: i)
        sessions.insert(s, at: 0)
    }
}
