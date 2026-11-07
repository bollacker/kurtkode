import Foundation

/// The project's own test suite (COST_AUDIT.md improvement 11b): the command a project names as `"testCommand"` in its
/// `.kurtkode/settings.local.json` or `.kurtkode/settings.json` (the local file wins). After a main run that changed
/// files and ended on its own, kurtkode runs it once more from the project's root (wherever the model's `cd` left the
/// shell), authorized and sandboxed like any command, and a failure is a grounded reason to offer escalation. In P2b
/// this re-run agreed with gold on all 12 real-sized re-runs; the model's own last check flagged 89% of failures with
/// 77% precision. Nothing runs for a project that names no command.
public enum TestSuite {
    public static let key = "testCommand"

    public static func command(root: URL) -> String? {
        for name in [".kurtkode/settings.local.json", ".kurtkode/settings.json"] {
            guard let data = try? Data(contentsOf: root.appending(path: name)),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let command = (object[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !command.isEmpty
            else { continue }
            return command
        }
        return nil
    }
}
