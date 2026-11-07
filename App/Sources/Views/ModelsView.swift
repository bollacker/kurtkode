import AgentCore
import SwiftUI

/// The Models window: this Mac's LM Studio (server, memory, loaded and installed models) and the other
/// endpoints. Loading goes through `AppModel.loadModel`, which keeps other models only when they fit.
struct ModelsView: View {
    @Environment(AppModel.self) private var app
    @State private var error: String?

    private var local: [Endpoint] { app.endpoints.filter { $0.kind == .lmstudio && $0.isLocal } }
    private var remote: [Endpoint] { app.endpoints.filter { !($0.kind == .lmstudio && $0.isLocal) } }

    var body: some View {
        Form {
            ForEach(local) { e in LocalEndpointSection(endpoint: e, error: $error) }
            if !remote.isEmpty {
                Section("Other endpoints") {
                    ForEach(remote) { e in RemoteEndpointRow(endpoint: e) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 640, minHeight: 480)
        .alert("Couldn't do that", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
        } message: { Text(error ?? "") }
        .task { for e in app.endpoints { await app.refreshModels(e.id) } }
    }
}

private struct LocalEndpointSection: View {
    @Environment(AppModel.self) private var app
    let endpoint: Endpoint
    @Binding var error: String?
    @State private var confirmingUnloadAll = false

    private var catalog: ModelCatalog? { app.catalogs[endpoint.id] }
    private var loaded: [ModelEntry] { catalog?.entries.filter(\.isLoaded) ?? [] }
    private var installed: [ModelEntry] { catalog?.entries.filter { !$0.isLoaded } ?? [] }

    var body: some View {
        Section {
            serverRow
            MemoryBar(memory: app.memory)
            if case .reachable = catalog?.reachability {
                if loaded.isEmpty {
                    Text("No model is loaded.").foregroundStyle(.secondary)
                } else {
                    ForEach(loaded) { m in LoadedModelRow(endpoint: endpoint, model: m, error: $error) }
                    let busy = !app.modelsInUse(on: endpoint.id).isDisjoint(with: loaded.map(\.id))
                    Button("Unload All…", role: .destructive) { confirmingUnloadAll = true }
                        .disabled(app.loading != nil || busy)
                        .help(busy ? "A chat is generating on one of these models" : "Unloads every model in LM Studio")
                }
            }
        } header: {
            Text(endpoint.name)
        }
        .confirmationDialog("Unload every model in LM Studio?", isPresented: $confirmingUnloadAll) {
            Button("Unload All", role: .destructive) { run { try await app.unloadAll(on: endpoint.id) } }
        } message: {
            Text("This unloads all \(loaded.count) loaded model\(loaded.count == 1 ? "" : "s"), including ones kurtkode "
                 + "didn't load: other apps or the lms command line using them lose them too.")
        }
        if case .reachable = catalog?.reachability, !installed.isEmpty {
            Section("Installed on this Mac") {
                ForEach(installed) { m in InstalledModelRow(endpoint: endpoint, model: m, error: $error) }
            }
        }
    }

    @ViewBuilder private var serverRow: some View {
        HStack {
            switch catalog?.reachability {
            case .reachable:
                Label("Server running", systemImage: "circle.fill").foregroundStyle(.green)
            case .unreachable(let why):
                Label("Server not running", systemImage: "circle").foregroundStyle(.secondary)
                    .help(why)
                Spacer()
                if app.lms.isInstalled {
                    Button("Start Server") { run { try await app.startLocalServer() } }
                } else {
                    Text("lms isn't installed").foregroundStyle(.secondary)
                }
            default:
                Label("Checking…", systemImage: "circle.dotted").foregroundStyle(.secondary)
            }
            Spacer()
            if let report = app.lastLoadReport {
                Text(report).font(.caption).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.trailing)
            }
            Button {
                Task { await app.refreshModels(endpoint.id) }
            } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Refresh")
        }
    }

    private func run(_ op: @escaping @MainActor () async throws -> Void) {
        Task { do { try await op() } catch { self.error = error.localizedDescription } }
    }
}

/// Free memory as a bar, with swap. Orange under 30% free, red under 20% (the thresholds kurtkode loads by).
private struct MemoryBar: View {
    let memory: MemoryStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Memory")
                Spacer()
                Text(String(format: "%d%% free of %.0f GB · swap %.1f GB used", memory.freePercent,
                            Double(memory.totalBytes) / 1e9, Double(memory.swapUsedBytes) / 1e9))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressView(value: Double(100 - memory.freePercent), total: 100)
                .tint(memory.freePercent < 20 ? .red : memory.freePercent < 30 ? .orange : .accentColor)
        }
    }
}

private struct LoadedModelRow: View {
    @Environment(AppModel.self) private var app
    let endpoint: Endpoint
    let model: ModelEntry
    @Binding var error: String?

    static let inUseHelp = "A chat is generating on this model: stop it or wait for it to finish"
    private var inUse: Bool { app.modelsInUse(on: endpoint.id).contains(model.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                ModelTitle(model: model)
                Spacer()
                Button("Reload") { reload() }
                    .help(inUse ? Self.inUseHelp : "Load it again with the same context; frees memory its cache has taken")
                    .accessibilityLabel("Reload \(shortName(model.id))")
                Button("Unload") { run { try await app.unloadModel(model.id, on: endpoint.id) } }
                    .help(inUse ? Self.inUseHelp : "")
                    .accessibilityLabel("Unload \(shortName(model.id))")
            }
            .disabled(app.loading != nil || inUse)
            HStack(spacing: 12) {
                if let c = model.loadedContext { Text("context \(c / 1024)k") }
                if let p = model.parallel {
                    Text(p == 1 ? "1 slot" : "\(p) slots")
                        .help("Requests LM Studio serves at once; each slot reserves its own cache")
                }
                if let used = app.currentUse(model.id, on: endpoint.id) {
                    Text(String(format: "using %.1f GB now", Double(used) / 1e9))
                }
                if let peak = app.profile(endpoint.id, model.id).measuredPeakMemoryBytes {
                    Text(String(format: "peak %.1f GB", Double(peak) / 1e9))
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            if app.shouldOfferReload(model.id, on: endpoint.id) {
                Label("Its memory has grown well past the model's size (cached buffers). Reload to give it back.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func reload() {
        let context = model.loadedContext ?? Pref.d.integer(forKey: Pref.defaultContextLength)
        run { try await app.loadModel(model.id, on: endpoint.id, contextLength: context) }
    }

    private func run(_ op: @escaping @MainActor () async throws -> Void) {
        Task { do { try await op() } catch { self.error = error.localizedDescription } }
    }
}

private struct InstalledModelRow: View {
    @Environment(AppModel.self) private var app
    let endpoint: Endpoint
    let model: ModelEntry
    @Binding var error: String?
    @State private var context = Pref.d.integer(forKey: Pref.defaultContextLength)

    private var choices: [Int] {
        [8192, 16384, 32768, 65536, 131072].filter { $0 <= (model.maxContext ?? 131072) }
    }

    var body: some View {
        let after = app.freePercentAfterLoading(model.id, on: endpoint.id)
        let isLoading = app.loading?.model == model.id
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                ModelTitle(model: model)
                Spacer()
                Picker("Context", selection: $context) {
                    ForEach(choices, id: \.self) { Text("\($0 / 1024)k").tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Context length for \(shortName(model.id))")
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Load") {
                        Task {
                            do { try await app.loadModel(model.id, on: endpoint.id, contextLength: context) }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                    .disabled(app.loading != nil)
                    .accessibilityLabel("Load \(shortName(model.id))")
                }
            }
            Text(estimate(after))
                .font(.caption)
                .foregroundStyle(after < 25 ? .orange : .secondary)
        }
        .onAppear { if !choices.contains(context) { context = choices.last ?? 8192 } }
    }

    private func estimate(_ after: Int) -> String {
        let expected = Double(app.expectedFootprint(model.id, on: endpoint.id)) / 1e9
        let measured = app.profile(endpoint.id, model.id).measuredPeakMemoryBytes != nil
        var s = String(format: "Needs about %.1f GB (%@). ", expected, measured ? "measured" : "estimated from its size")
        if after >= 25 {
            s += "About \(after)% of memory would stay free."
        } else {
            s += "That would leave about \(max(after, 0))% free, so other models get unloaded first; below 30% free it won't load."
        }
        return s
    }
}

private struct ModelTitle: View {
    let model: ModelEntry

    var body: some View {
        HStack(spacing: 6) {
            Text(shortName(model.id)).fontWeight(.medium)
            if let b = model.sizeBytes {
                Text(String(format: "%.1f GB", Double(b) / 1e9)).foregroundStyle(.secondary)
            }
            if model.supportsTools { Badge("tools") }
            if model.supportsVision { Badge("vision") }
        }
        .help(model.id)
    }
}

private struct Badge: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.caption2)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
    }
}

private struct RemoteEndpointRow: View {
    @Environment(AppModel.self) private var app
    let endpoint: Endpoint

    var body: some View {
        HStack {
            Text(endpoint.name).fontWeight(.medium)
            Text(endpoint.baseURL.host() ?? endpoint.baseURL.absoluteString).foregroundStyle(.secondary)
            Spacer()
            switch app.catalogs[endpoint.id]?.reachability {
            case .reachable:
                Text("\(app.catalogs[endpoint.id]?.entries.count ?? 0) models").foregroundStyle(.secondary)
            case .unreachable(let why):
                Text("not responding").foregroundStyle(.orange).help(why)
            default:
                Text("checking…").foregroundStyle(.secondary)
            }
            Button {
                Task { await app.refreshModels(endpoint.id) }
            } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Refresh")
        }
    }
}
