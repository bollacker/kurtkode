import Darwin
import Foundation

/// System-wide memory, read the way `memory_pressure` reports it.
///
/// Per-process numbers are misleading here: MLX model memory doesn't show in a process's RSS, so the
/// app watches the system-wide free percentage instead.
public struct MemoryStatus: Sendable, Equatable {
    public var totalBytes: UInt64
    /// `kern.memorystatus_level`: the "System-wide memory free percentage" from `memory_pressure`.
    public var freePercent: Int
    public var swapUsedBytes: UInt64
    public var swapTotalBytes: UInt64

    public var freeBytes: UInt64 { totalBytes / 100 * UInt64(max(0, freePercent)) }

    public enum Level: Sendable { case ok, low, critical }

    public var level: Level {
        switch freePercent {
        case ..<15: .critical
        case ..<30: .low
        default: .ok
        }
    }

    public static func current() -> MemoryStatus {
        var total: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &total, &size, nil, 0)

        var level: Int32 = 0
        size = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_level", &level, &size, nil, 0)

        var swap = xsw_usage()
        size = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &size, nil, 0)

        return MemoryStatus(totalBytes: total, freePercent: Int(level),
                            swapUsedBytes: swap.xsu_used, swapTotalBytes: swap.xsu_total)
    }
}
