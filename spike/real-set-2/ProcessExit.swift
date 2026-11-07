import Foundation

// From 28e9843 (Workspace.swift), for fixtures at commits before it: see build_kk.sh.
extension Process {
    /// Starts it with a signal for its end. `waitUntilExit()` sometimes never returned for a process that had exited
    /// (once in about 4,000 rg runs: an eval stuck for 5 hours with no child left); the termination handler, set before
    /// the start, always comes.
    func startWithExitSignal() throws -> DispatchSemaphore {
        let done = DispatchSemaphore(value: 0)
        terminationHandler = { _ in done.signal() }
        try run()
        return done
    }

    /// Its exit status once `exited` (from `startWithExitSignal`) fires; past `timeout` seconds it's stopped, and -1
    /// if even that doesn't end it.
    func waitForExit(_ exited: DispatchSemaphore, timeout: Double) -> Int32 {
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            terminate()
            if exited.wait(timeout: .now() + 2) == .timedOut { return -1 }
        }
        return terminationStatus
    }
}
