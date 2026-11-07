import CoreGraphics
let pid = Int(CommandLine.arguments[1])!
let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in l where (w[kCGWindowOwnerPID as String] as? Int) == pid { let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]; print(w[kCGWindowNumber as String]!, w[kCGWindowName as String] ?? "-", b["Width"] ?? "", b["Height"] ?? "") }
