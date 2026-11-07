import Foundation

/// `!command` in the composer: the user runs a command themselves, as in a terminal (no approval, no
/// sandbox: they wrote it), in the session's working directory. The output joins the conversation as the
/// user's message, so the model sees it next turn; no reply is started.
public enum UserShell {
    /// The command after `!`, or nil when the text isn't one.
    public static func command(in text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("!") else { return nil }
        let c = t.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        return c.isEmpty ? nil : c
    }

    /// Runs it and returns the message for the conversation. Cancelling the task stops the command.
    public static func run(_ command: String, workspace: Workspace, shell: ShellState,
                           maxOutputBytes: Int = 8_000, progress: (@Sendable (String) -> Void)? = nil) async -> ChatMessage {
        var context = ToolContext(workspace: workspace, maxOutputBytes: maxOutputBytes, shell: shell, progress: progress)
        context.sandbox = nil
        let output: ToolOutput
        do { output = try await BashTool().run(ToolArguments(["command": .string(command)]), context: context) }
        catch let f as ToolFailure { output = .error(f.message) }
        catch { output = .error(error.localizedDescription) }
        var m = ChatMessage.user(message(command: command, output: output.text))
        m.userCommand = UserCommandInfo(command: command, output: output.display ?? output.text, exitCode: output.exitCode)
        return m
    }

    /// "I ran `cmd` myself:" and the output in a fence long enough not to be closed by the output.
    static func message(command: String, output: String) -> String {
        var fence = "```"
        while output.contains(fence) { fence += "`" }
        let inline = command.contains("\n") || command.contains("`") ? "\n\(fence)sh\n\(command)\n\(fence)\n" : " `\(command)` "
        return "I ran\(inline)in the project myself. Output:\n\(fence)\n\(output)\n\(fence)"
    }
}
