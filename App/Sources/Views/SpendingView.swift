import AgentCore
import SwiftUI

/// What runs cost (GAP_ANALYSIS.md A5): every recorded run, main and subagent, grouped by model, kind, project or day,
/// with how often the labeled ones passed, the share of prompt tokens read from cache, and what the same tokens would
/// have cost on another model. The same figures as `kurtkode cost report` and `cost whatif`.
struct SpendingView: View {
    @Environment(AppModel.self) private var app
    @State private var group = Spending.Group.model
    @State private var days = 30
    @State private var runs: [Spending.Run] = []
    @State private var loading = true
    @State private var whatIfKey = ""
    @AppStorage(Pref.hourlyRate) private var hourly = 30.0

    private var shown: [Spending.Run] {
        guard days > 0 else { return runs }
        // Today: since midnight on this Mac, as the daily limits count.
        let cutoff = days == 1 ? Calendar.current.startOfDay(for: Date()) : Date().addingTimeInterval(-Double(days) * 86_400)
        return runs.filter { $0.record.started >= cutoff }
    }

    private var rows: [Spending.Row] { Spending.rows(shown, by: group) }

    /// Models to reprice at: the pool's, then recent ones, that have a list price.
    private var whatIfModels: [(key: String, label: String, price: PriceList.Price)] {
        var out: [(String, String, PriceList.Price)] = []
        var seen = Set<String>()
        let pooled = app.pool.entries.compactMap { ModelPool.resolve($0, endpoints: app.endpoints) }
            .map { ModelRef(endpointID: $0.endpoint.id, model: $0.model) }
        for ref in pooled + app.recentModels where seen.insert(ref.key).inserted {
            if let p = app.price(ref.endpointID, ref.model) { out.append((ref.key, shortName(ref.model), p)) }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Group by", selection: $group) {
                    ForEach(Spending.Group.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                Picker("Period", selection: $days) {
                    Text("Today").tag(1); Text("7 days").tag(7); Text("30 days").tag(30); Text("All").tag(0)
                }
                .frame(maxWidth: 180)
                Spacer()
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Read the runs again")
            }
            if loading {
                ProgressView("Reading runs…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shown.isEmpty {
                Text("No runs recorded in this period.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(rows) {
                    TableColumn(group.rawValue.capitalized) { r in Text(r.key).fontWeight(r.isTotal ? .semibold : .regular) }
                        .width(min: 160, ideal: 260)
                    TableColumn("Runs") { r in Text("\(r.runs)").monospacedDigit() }.width(50)
                    TableColumn("Spent") { r in Text(r.pricedRuns > 0 || r.spent > 0 ? money(r.spent) : "–").monospacedDigit() }.width(80)
                    TableColumn("A run") { r in Text(r.perRun.map(money) ?? "–").monospacedDigit() }.width(80)
                    TableColumn("A success") { r in Text(r.perSuccess.map(money) ?? "–").monospacedDigit() }.width(80)
                    TableColumn("Passed") { r in Text(r.labeled > 0 ? "\(r.passed)/\(r.labeled)" : "–").monospacedDigit() }.width(60)
                    TableColumn("Cache") { r in Text(r.cacheShare.map { String(format: "%.0f%%", $0 * 100) } ?? "–").monospacedDigit() }.width(50)
                    TableColumn("Wait a run") { r in Text(r.secondsPerRun.map { String(format: "%.0f s", $0) } ?? "–").monospacedDigit() }.width(70)
                    TableColumn("Time cost") { r in Text(hourly > 0 ? money(r.timeCost(perHour: hourly)) : "–").monospacedDigit() }.width(70)
                    TableColumn("Tokens in / out") { r in Text("\(r.promptTokens.formatted()) / \(r.completionTokens.formatted())").monospacedDigit() }
                }
                whatIf
            }
            Text("Spent is what the server charged where it said (OpenRouter), else list price; local models cost nothing. "
                 + "Passed counts runs with a label: your thumbs and /good, /bad; a retry or rewind counts as a fail; the "
                 + "judges' ratings of subagent runs. Cache is the share of prompt tokens read from the provider's cache. "
                 + (hourly > 0 ? "Time cost is the runs' wall time at $\(Int(hourly)) an hour of your waiting (Settings → Spending)." : ""))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .task { await load() }
    }

    @ViewBuilder private var whatIf: some View {
        let models = whatIfModels
        if !models.isEmpty {
            HStack {
                Picker("What if they had run on", selection: $whatIfKey) {
                    Text("—").tag("")
                    ForEach(models, id: \.key) { m in Text(m.label).tag(m.key) }
                }
                .frame(maxWidth: 380)
                if let m = models.first(where: { $0.key == whatIfKey }) {
                    let priced = shown.filter { $0.outside == nil && $0.listSpent != nil }
                    let actual = priced.compactMap(\.listSpent).reduce(0, +)
                    Text("\(money(Spending.whatIf(priced, at: m.price))) instead of \(money(actual)) at list price")
                        .monospacedDigit()
                        .help("The same recorded tokens at that model's list price. A first approximation: another model would "
                              + "use more or fewer tokens, and pass more or less often.")
                }
            }
        }
    }

    private func money(_ v: Double) -> String {
        v == 0 ? "$0" : v < 0.01 ? String(format: "$%.5f", v) : v < 10 ? String(format: "$%.3f", v) : String(format: "$%.0f", v)
    }

    private func load() async {
        loading = true
        let store = app.sessionStore
        runs = (try? await Spending.sessionRuns(store)) ?? []
        loading = false
    }
}

extension Spending.Row: @retroactive Identifiable {
    public var id: String { isTotal ? "\u{0}total" : key }
}
