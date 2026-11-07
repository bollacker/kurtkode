import CryptoKit
import Foundation

/// What servers say about their rate limits, per host, so requests wait for a reset instead of collecting 429s
/// (parallel subagents on one Claude model use one budget). Anthropic sends `anthropic-ratelimit-*` headers on every
/// response; a request goes ahead unless the requests or input tokens left for the current window are used up.
public actor RateLimits {
    public static let shared = RateLimits()

    struct Window: Sendable {
        var remaining: Int
        var reset: Date
    }

    private var windows: [String: [String: Window]] = [:]     // scope → limit name → window

    /// The key the windows are kept under: the host, a short digest of the API key (never the key itself, so a second
    /// key gets its own budget) and the model class. Anthropic limits are per class (opus, sonnet, haiku), so Haiku
    /// subagents using up theirs mustn't hold back a Sonnet request; other models count on their own.
    public static func scope(host: String, apiKey: String?, model: String) -> String {
        let key = (apiKey ?? "").isEmpty ? "-" : SHA256.hash(data: Data(apiKey!.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        let m = model.lowercased()
        let family = ["opus", "sonnet", "haiku"].first { m.contains($0) } ?? m
        return "\(host)|\(key)|\(family)"
    }

    /// Records the limits a response reported.
    public func record(host: String, headers: [AnyHashable: Any], now: Date = Date()) {
        var found: [String: Window] = [:]
        for name in ["requests", "input-tokens", "tokens"] {
            guard let r = Self.header(headers, "anthropic-ratelimit-\(name)-remaining").flatMap({ Int($0) }),
                  let t = Self.header(headers, "anthropic-ratelimit-\(name)-reset").flatMap(Self.date) else { continue }
            found[name] = Window(remaining: r, reset: t)
        }
        guard !found.isEmpty else { return }
        windows[host, default: [:]].merge(found) { _, new in new }
    }

    /// How long to wait before sending to `host`: until the reset of a window that's used up (at most a minute), else 0.
    public func pause(host: String, now: Date = Date()) -> TimeInterval {
        let exhausted = (windows[host] ?? [:]).filter { name, w in
            w.reset > now && (name == "requests" ? w.remaining <= 0 : w.remaining < 1000)
        }
        guard let latest = exhausted.values.map(\.reset).max() else { return 0 }
        return min(60, latest.timeIntervalSince(now))
    }

    static func header(_ headers: [AnyHashable: Any], _ name: String) -> String? {
        for (k, v) in headers where (k as? String)?.lowercased() == name { return v as? String }
        return nil
    }

    static func date(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// Google's suggested wait in a 429 body (`"retryDelay": "30s"` in the error's details), capped at a minute.
    static func retryDelay(fromBody data: Data) -> TimeInterval? {
        let text = String(decoding: data.prefix(65_536), as: UTF8.self)
        guard let r = text.range(of: #""retryDelay"\s*:\s*"([0-9.]+)s""#, options: .regularExpression) else { return nil }
        let digits = text[r].split(separator: "\"").first { Double($0.dropLast()) != nil && $0.hasSuffix("s") }
        return digits.flatMap { Double($0.dropLast()) }.map { min($0, 60) }
    }
}
