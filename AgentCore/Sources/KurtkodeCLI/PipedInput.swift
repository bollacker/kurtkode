import Darwin
import Foundation

/// `-p`'s piped input, which joins the prompt.
public enum PipedInput {
    public enum Plan: Equatable, Sendable {
        /// A terminal: nothing is piped.
        case none
        /// Read to the end, however slowly it comes: a pipe (`git diff | kurtkode -p "review this"`) or a file.
        case readAll
        /// Read only if something arrives soon: a socket or a device, which a script or CI job can leave open without
        /// ever writing to it (waiting for its end would hang forever).
        case readIfReady
    }

    /// How to treat input on `fd`. Without a prompt, the input is the prompt: it's read to the end whatever it is.
    public static func plan(fd: Int32, promptGiven: Bool) -> Plan {
        if isatty(fd) == 1 { return .none }
        if !promptGiven { return .readAll }
        var info = stat()
        guard fstat(fd, &info) == 0 else { return .readIfReady }
        switch info.st_mode & S_IFMT {
        case S_IFIFO, S_IFREG: return .readAll
        default: return .readIfReady
        }
    }

    /// The piped text (nil when there's none, or it was skipped). `note` gets a line for stderr: that the input was
    /// skipped, or that a pipe is still being waited for.
    public static func read(fd: Int32, promptGiven: Bool, waitMilliseconds: Int32 = 500, note: (String) -> Void) -> String? {
        let plan = plan(fd: fd, promptGiven: promptGiven)
        guard plan != .none else { return nil }
        var fds = [pollfd(fd: fd, events: Int16(POLLIN), revents: 0)]
        let ready = poll(&fds, 1, waitMilliseconds) > 0
        if !ready {
            if plan == .readIfReady {
                note("kurtkode: not reading stdin: nothing arrived within \(Double(waitMilliseconds) / 1000) s and it isn't a "
                     + "pipe or a file (pipe the input, or give it with < FILE)")
                return nil
            }
            if promptGiven { note("kurtkode: waiting for stdin to end (run with < /dev/null to leave it out)") }
        }
        guard let data = try? FileHandle(fileDescriptor: fd, closeOnDealloc: false).readToEnd(), !data.isEmpty else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
