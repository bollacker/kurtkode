import AppKit
let pid = pid_t(CommandLine.arguments[1])!
guard let app = NSRunningApplication(processIdentifier: pid) else { print("no app"); exit(1) }
print(app.bundleURL?.path ?? "-", app.terminate() ? "terminate sent" : "terminate refused")
