import Foundation
import os

/// Logs main-thread stalls: a background thread asks the main queue to answer every 100 ms and records how
/// late the answer was. A stall of `threshold` or more is logged (category "hang") with its length, so freezes
/// can be measured, and reported: log show --last 1h --predicate 'subsystem == "org.mlcommons.kurt.kurtkode" AND category == "hang"'
final class HangMonitor: @unchecked Sendable {
    static let shared = HangMonitor()
    static let log = Logger(subsystem: "org.mlcommons.kurt.kurtkode", category: "hang")

    #if DEBUG
    let threshold: TimeInterval = 0.25
    #else
    let threshold: TimeInterval = 0.5
    #endif
    private let lock = NSLock()
    private var started = false
    private(set) var worst: TimeInterval = 0
    private(set) var count = 0

    func start() {
        guard lock.withLock({ () -> Bool in defer { started = true }; return !started }) else { return }
        let thread = Thread { [self] in
            while true {
                let sent = Date()
                let answered = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { answered.signal() }
                // Wait as long as it takes, so one long stall is logged once with its full length.
                answered.wait()
                let late = Date().timeIntervalSince(sent)
                if late >= threshold {
                    lock.withLock { count += 1; worst = max(worst, late) }
                    Self.log.notice("main thread stalled \(Int(late * 1000), privacy: .public) ms")
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        thread.name = "kurtkode.hang-monitor"
        thread.qualityOfService = .utility
        thread.start()
    }
}

#if DEBUG
/// KURTKODE_TRACE_BODIES=1: the main views print which of their inputs changed each time SwiftUI runs their body
/// (`Self._printChanges()`), for finding what re-renders while a reply streams. Launch with `open --stdout FILE`.
enum BodyTrace {
    static let on = ProcessInfo.processInfo.environment["KURTKODE_TRACE_BODIES"] != nil
}
#endif
