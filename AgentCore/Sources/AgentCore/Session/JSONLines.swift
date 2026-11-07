import Foundation

/// Appends to JSON Lines files that several writers share: the app and the command line on one session, two CLI runs,
/// a background reconciler beside a running turn. Each append holds an exclusive lock on the file (`flock`, which every
/// kurtkode process takes) and writes with `O_APPEND`, so a record always lands after every earlier one and never on
/// top of another writer's (a seek to the end followed by a write could: both writers found the same end). `rewrite`
/// replaces the file by renaming a new one over it, under that lock; so a writer that opened the old file and then
/// waited for the lock checks, once it has it, that the path still names the file it holds, and opens it again if not.
enum JSONLines {
    /// Appends `line` (ending in a newline), first ending a torn last line (a crash mid-write) with a newline, so the
    /// record starts a line of its own. Returns the file's size before and after, for noticing other writers.
    @discardableResult
    static func append(_ line: Data, to url: URL, create: Bool = false) throws -> (before: UInt64, after: UInt64) {
        let fd = try openLocked(url, flags: O_RDWR | O_APPEND | (create ? O_CREAT : 0))
        defer { close(fd) }
        defer { flock(fd, LOCK_UN) }
        let before = try size(fd)
        var data = line
        if before > 0 {
            var last: UInt8 = 0
            if pread(fd, &last, 1, off_t(before - 1)) == 1, last != 0x0A { data.insert(0x0A, at: 0) }
        }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let n = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                offset += n
            }
        }
        return (before, try size(fd))
    }

    /// Replaces the file's lines with `transform`'s result, holding the same lock as `append`, so no append made
    /// meanwhile is lost. The new lines go to a temporary file renamed over the old one while the lock is held, so a
    /// crash midway leaves the old file whole (truncating and writing in place could leave it empty); writers waiting
    /// for the lock on the old file notice the rename and open the new one.
    static func rewrite(_ url: URL, _ transform: ([Data]) throws -> [Data]) throws {
        let fd = try openLocked(url, flags: O_RDWR | O_CREAT)
        defer { close(fd) }
        defer { flock(fd, LOCK_UN) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        try handle.seek(toOffset: 0)
        let data = try handle.readToEnd() ?? Data()
        var out = Data()
        for line in try transform(data.split(separator: 0x0A).map { Data($0) }) { out.append(line); out.append(0x0A) }
        let temp = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        let tfd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o644)
        guard tfd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        do {
            let th = FileHandle(fileDescriptor: tfd, closeOnDealloc: false)
            try th.write(contentsOf: out)
            guard fsync(tfd) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            close(tfd)
            guard rename(temp.path, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        } catch {
            close(tfd)
            unlink(temp.path)
            throw error
        }
    }

    /// Opens `url` and takes its exclusive lock, reopening when the path was renamed over (by `rewrite`) while this
    /// waited, so the lock held is always on the file the path names.
    private static func openLocked(_ url: URL, flags: Int32) throws -> Int32 {
        while true {
            let fd = open(url.path, flags | O_CLOEXEC, 0o644)
            guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            while flock(fd, LOCK_EX) != 0 {
                guard errno == EINTR else {
                    let e = errno
                    close(fd)
                    throw POSIXError(POSIXErrorCode(rawValue: e) ?? .EIO)
                }
            }
            var held = stat(), named = stat()
            if fstat(fd, &held) == 0, stat(url.path, &named) == 0, held.st_dev == named.st_dev, held.st_ino == named.st_ino {
                return fd
            }
            // Renamed over or removed meanwhile: open what the path names now (or fail as `open` does).
            flock(fd, LOCK_UN)
            close(fd)
        }
    }

    private static func size(_ fd: Int32) throws -> UInt64 {
        var st = stat()
        guard fstat(fd, &st) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return UInt64(st.st_size)
    }
}
