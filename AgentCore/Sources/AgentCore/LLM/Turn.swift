import Foundation

/// Limits applied to every assistant turn. Local models can generate without end, so all three are on
/// by default.
public struct TurnLimits: Sendable, Hashable {
    public var maxTokens: Int
    /// Wall-clock limit for the whole turn, prompt processing included.
    public var wallClock: TimeInterval
    public var detectRepetition: Bool

    public init(maxTokens: Int = 8192, wallClock: TimeInterval = 600, detectRepetition: Bool = true) {
        self.maxTokens = maxTokens
        self.wallClock = wallClock
        self.detectRepetition = detectRepetition
    }
}

/// A live view of a turn in progress, for the UI.
public struct TurnSnapshot: Sendable, Equatable {
    public var content: String = ""
    public var reasoning: String = ""
    public var toolCalls: [ToolCall] = []
    public var reportedModel: String?
    public var elapsed: TimeInterval = 0
    public var timeToFirstToken: TimeInterval?

    public init() {}

    /// Rough output size while streaming, before the server reports usage: ~4 characters per token.
    public var estimatedTokens: Int { (content.utf8.count + reasoning.utf8.count + toolCalls.reduce(0) { $0 + $1.arguments.utf8.count }) / 4 }
    public var isThinking: Bool { content.isEmpty && !reasoning.isEmpty && toolCalls.isEmpty }
}

/// Folds stream events into an assistant message. Pure; the runner owns timing and I/O.
public struct TurnAccumulator: Sendable {
    public private(set) var snapshot = TurnSnapshot()
    public private(set) var usage: Usage?
    public private(set) var finishReason: FinishReason?
    public private(set) var provider: String?
    public private(set) var notes: [String] = []
    public private(set) var native: NativeContent?
    public private(set) var declined = false
    public private(set) var paused = false
    public private(set) var requestIDs: [String] = []
    public private(set) var usageRaw: JSONValue?
    /// The calls in the order they opened, each with the stream index it came under.
    private var calls: [(index: Int, call: ToolCall)] = []
    /// The call each stream index now feeds (an index can feed several calls in turn; see `apply`).
    private var slots: [Int: Int] = [:]

    public init() {}

    /// Applies one event. Returns true if it added generated text (content, reasoning, or tool arguments).
    @discardableResult
    public mutating func apply(_ event: StreamEvent) -> Bool {
        switch event {
        case .model(let m):
            if snapshot.reportedModel == nil { snapshot.reportedModel = m }
            return false
        case .provider(let p):
            if provider == nil { provider = p }
            return false
        case .content(let s):
            snapshot.content += s
            return true
        case .reasoning(let s):
            snapshot.reasoning += s
            return true
        case .toolCallDelta(let index, let id, let name, let arguments):
            // Some servers (Ollama and proxies, in some versions) give parallel calls no index or the same one: a new
            // id under an index that already has a call starts another call.
            if let slot = slots[index], let id, !id.isEmpty, !calls[slot].call.id.isEmpty, calls[slot].call.id != id {
                slots[index] = nil
            }
            if slots[index] == nil {
                calls.append((index, ToolCall(id: "", name: "", arguments: "")))
                slots[index] = calls.count - 1
            }
            let slot = slots[index]!
            var c = calls[slot].call
            if let id, !id.isEmpty { c.id = id }
            c.name = Self.joinName(c.name, name ?? "")
            c.arguments += arguments ?? ""
            calls[slot].call = c
            snapshot.toolCalls = calls.enumerated().sorted { ($0.element.index, $0.offset) < ($1.element.index, $1.offset) }
                .map(\.element.call)
            return true
        case .finish(let f):
            finishReason = f
            return false
        case .usage(let u):
            usage = u
            return false
        case .note(let n):
            notes.append(n)
            return false
        case .discardToolCalls:
            calls = []
            slots = [:]
            snapshot.toolCalls = []
            return false
        case .native(let n):
            native = n
            return false
        case .declined:
            // A declined reply's tool calls never run (a refusal can come after a call was written).
            declined = true
            calls = []
            slots = [:]
            snapshot.toolCalls = []
            return false
        case .paused:
            paused = true
            return false
        case .requestID(let id):
            if !requestIDs.contains(id) { requestIDs.append(id) }
            return false
        case .usageRaw(let raw):
            usageRaw = raw
            return false
        }
    }

    /// A call's name with the next streamed piece of it. OpenAI sends the name once, some servers split it across
    /// deltas, and some repeat the whole name (or the name so far) in every delta: a piece equal to the name, or one
    /// that extends it, replaces it rather than being appended.
    static func joinName(_ name: String, _ piece: String) -> String {
        if name.isEmpty || piece.hasPrefix(name) { return piece.isEmpty ? name : piece }
        return name + piece
    }

    /// The finished assistant message. Tool calls without a server id get a local one.
    public func message(meta: TurnMeta) -> ChatMessage {
        let toolCalls = snapshot.toolCalls.enumerated().map { i, c in
            c.id.isEmpty ? ToolCall(id: "call_\(i)", name: c.name, arguments: c.arguments) : c
        }
        var m = ChatMessage(role: .assistant,
                            content: snapshot.content,
                            reasoning: snapshot.reasoning.isEmpty ? nil : snapshot.reasoning,
                            toolCalls: toolCalls,
                            meta: meta)
        m.native = native
        return m
    }
}

public enum TurnRunner {
    /// Runs one assistant turn, streaming snapshots to `onUpdate` at most every `updateInterval`.
    ///
    /// Never throws: cancellation, timeouts, repetition, and errors all produce an assistant message
    /// whose `meta.stopReason` says what happened, with whatever text arrived before the stop.
    public static func run(client: ChatClient,
                           request: ChatRequest,
                           limits: TurnLimits,
                           updateInterval: Duration = .milliseconds(50),
                           tap: WireTap? = nil,
                           onUpdate: @escaping @Sendable (TurnSnapshot) async -> Void) async -> ChatMessage {
        var request = request
        request.maxTokens = limits.maxTokens
        var reply = await run(client: client, model: request.model, limits: limits, updateInterval: updateInterval, onUpdate: onUpdate) {
            client.stream(request, tap: tap)
        }
        // OpenRouter reports Claude's cache writes without their lifetime: an hour's were priced as five minutes'
        // (seen live: $0.0012 at list price, $0.0019 charged). What the request asked for is what was written.
        if client.sendsHourCache(request), var u = reply.meta?.usage, u.cacheWriteHourTokens == nil, (u.cacheWriteTokens ?? 0) > 0 {
            u.cacheWriteHourTokens = u.cacheWriteTokens
            reply.meta?.usage = u
        }
        return reply
    }

    /// Runs one turn from a request body as it is (a replay); `model` is what the body asks for.
    public static func run(client: ChatClient, body: Data, model: String, limits: TurnLimits, tap: WireTap? = nil,
                           onUpdate: @escaping @Sendable (TurnSnapshot) async -> Void = { _ in }) async -> ChatMessage {
        await run(client: client, model: model, limits: limits, updateInterval: .milliseconds(50), onUpdate: onUpdate) {
            client.stream(body: body, model: model, tap: tap)
        }
    }

    static func run(client: ChatClient, model: String, limits: TurnLimits, updateInterval: Duration,
                    onUpdate: @escaping @Sendable (TurnSnapshot) async -> Void,
                    stream: () -> AsyncThrowingStream<StreamEvent, Error>) async -> ChatMessage {
        let clock = ContinuousClock()
        let start = clock.now
        var acc = TurnAccumulator()
        var repetition = RepetitionDetector()
        var repeatedLines = LineRepetition()
        var stop = StopReason.completed
        var errorText: String?
        var lastUpdate = start
        var firstToken: TimeInterval?

        func elapsed() -> TimeInterval {
            let d = clock.now - start
            return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        }

        // The events, and a nil when the wall-clock limit is up: pings, SSE comments and retry waits produce no events,
        // so checking the time per event alone let a turn run on past its limit.
        let source = stream()
        let (events, feed) = AsyncThrowingStream<StreamEvent?, Error>.makeStream()
        let pump = Task {
            do {
                for try await e in source { feed.yield(e) }
                feed.finish()
            } catch {
                feed.finish(throwing: error)
            }
        }
        let deadline = Task {
            try await Task.sleep(for: .seconds(limits.wallClock))
            feed.yield(nil)
        }
        defer {
            pump.cancel()                   // ends the request and closes the connection
            deadline.cancel()
        }

        do {
            for try await item in events {
                guard let event = item else {
                    stop = .timedOut
                    break
                }
                let generated = acc.apply(event)
                if generated, firstToken == nil { firstToken = elapsed() }
                if limits.detectRepetition, generated {
                    switch event {
                    case .reasoning(let s):
                        if repetition.append(s) || repeatedLines.append(s) { stop = .repetition }
                    case .content(let s):
                        if repetition.append(s) { stop = .repetition }
                    default: break
                    }
                    if stop == .repetition { break }
                }
                if elapsed() > limits.wallClock {
                    stop = .timedOut
                    break
                }
                if clock.now - lastUpdate >= updateInterval {
                    lastUpdate = clock.now
                    var snap = acc.snapshot
                    snap.elapsed = elapsed()
                    snap.timeToFirstToken = firstToken
                    await onUpdate(snap)
                }
            }
            // Breaking out of the loop ends the stream, which cancels the request and closes the connection.
            if Task.isCancelled { stop = .cancelled }
        } catch is CancellationError {
            stop = .cancelled
        } catch let e as URLError where e.code == .cancelled {
            stop = .cancelled
        } catch let e as URLError where e.code == .timedOut {
            stop = .timedOut
            errorText = "No data from the server for \(Int(client.idleTimeout)) seconds."
        } catch {
            stop = Task.isCancelled ? .cancelled : .failed
            if stop == .failed {
                errorText = error.localizedDescription
                // Retired preview models, renamed ones, ones the key can't use: say what to do about it.
                if case ChatError.http(404, _) = error {
                    errorText! += " The server doesn't offer \(model) (it may be retired or renamed, or not enabled for this "
                        + "key), or the endpoint's URL is wrong. Pick another model; Refresh Models lists what the server offers now."
                }
            }
        }

        var snap = acc.snapshot
        snap.elapsed = elapsed()
        snap.timeToFirstToken = firstToken
        await onUpdate(snap)

        var meta = TurnMeta(requestedModel: model,
                            // A server-side fallback continued on another model, which is also the one priced.
                            reportedModel: acc.native.flatMap { $0.model != model ? $0.model : nil } ?? acc.snapshot.reportedModel,
                            usage: acc.usage,
                            finishReason: acc.finishReason,
                            stopReason: stop,
                            error: errorText,
                            timeToFirstToken: firstToken,
                            duration: elapsed())
        meta.provider = acc.provider
        if !acc.notes.isEmpty { meta.notes = acc.notes }
        if acc.declined { meta.declined = true }
        if acc.paused { meta.paused = true }
        if !acc.requestIDs.isEmpty { meta.requestIDs = acc.requestIDs }
        meta.usageRaw = acc.usageRaw
        return acc.message(meta: meta)
    }
}

/// Detects a model stuck repeating itself: the tail of the output is one unit repeated many times.
public struct RepetitionDetector: Sendable {
    public var minRepeats = 8          // at least this many consecutive copies of the unit
    public var minSpan = 400           // and the repeated tail covers at least this many bytes
    public var maxPeriod = 500         // longest unit considered, in bytes
    public var checkEvery = 128        // bytes between checks
    private var buffer: [UInt8] = []
    private var sinceCheck = 0
    private let window = 8192

    public init() {}

    /// Appends generated text; returns true once the tail is repetitive.
    public mutating func append(_ text: String) -> Bool {
        buffer.append(contentsOf: text.utf8)
        if buffer.count > window * 2 { buffer.removeFirst(buffer.count - window) }
        sinceCheck += text.utf8.count
        guard sinceCheck >= checkEvery else { return false }
        sinceCheck = 0
        return Self.tailRepeats(buffer, minRepeats: minRepeats, minSpan: minSpan, maxPeriod: maxPeriod)
    }

    static func tailRepeats(_ b: [UInt8], minRepeats: Int, minSpan: Int, maxPeriod: Int) -> Bool {
        let n = b.count
        guard n >= minSpan else { return false }
        for p in 1...max(1, min(maxPeriod, n / minRepeats)) {
            let need = max(minRepeats * p, minSpan)
            guard need <= n else { continue }
            // The tail has period p iff b[i] == b[i + p] across it.
            var i = n - need
            var periodic = true
            while i < n - p {
                if b[i] != b[i + p] { periodic = false; break }
                i += 1
            }
            if periodic { return true }
        }
        return false
    }
}

/// Reasoning stuck in a long loop: Gemma 4 26B wrote the same 1.3 KB file into its thinking 64 times in 10 minutes
/// ("I'll do it." and the file again), a unit too long for `RepetitionDetector`. A line of some length seen this
/// many times in one reply's reasoning means the same.
public struct LineRepetition: Sendable {
    public var minLength = 40
    public var maxCount = 12
    private var partial = ""
    private var counts: [String: Int] = [:]

    public init() {}

    /// Appends reasoning; true once a line has come `maxCount` times.
    public mutating func append(_ text: String) -> Bool {
        partial += text
        guard let last = partial.lastIndex(of: "\n") else { return false }
        let done = partial[..<last]
        partial = String(partial[partial.index(after: last)...])
        for line in done.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.count >= minLength else { continue }
            counts[t, default: 0] += 1
            if counts[t]! >= maxCount { return true }
        }
        return false
    }
}
