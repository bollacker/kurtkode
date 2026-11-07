import Foundation

/// A task list the agent keeps for multi-step work. Each call replaces the whole list; the app shows the
/// latest one. No side effects, so it never needs approval.
public struct TodoWriteTool: Tool {
    public init() {}
    public let name = "todo_write"
    public let description = """
        Keep a todo list for tasks with several steps. Send the complete list each time: every item with \
        its status (pending, in_progress, or completed). Have exactly one item in_progress while working, \
        and mark items completed as soon as they're done. Skip this for simple one-step requests.
        """
    public let parameters: JSONValue = [
        "type": "object",
        "properties": [
            "todos": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "content": ["type": "string", "description": "The step, as a short imperative."],
                        "status": ["type": "string", "enum": ["pending", "in_progress", "completed"]],
                    ],
                    "required": ["content", "status"],
                ],
            ],
        ],
        "required": ["todos"],
    ]
    public let risk = ToolRisk.read

    public struct Item: Sendable, Hashable, Identifiable {
        public enum Status: String, Sendable { case pending, inProgress = "in_progress", completed }
        public var content: String
        public var status: Status
        public var id: String { content }
    }

    /// Parses a todo list from a call's arguments, tolerating the variations small models produce:
    /// the array as a JSON string, "done"/"in progress" spellings, and missing statuses.
    public static func items(from args: ToolArguments) throws -> [Item] {
        var raw = args.values["todos"]
        if case .string(let s)? = raw { raw = try? JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)) }
        guard case .array(let list)? = raw else { throw ToolFailure("todos must be an array of {content, status} objects") }
        return try list.map { entry in
            guard case .object(let o) = entry, case .string(let content)? = o["content"],
                  !content.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw ToolFailure("each todo needs a non-empty \"content\" string")
            }
            var status = Item.Status.pending
            if case .string(let s)? = o["status"] {
                switch s.lowercased().replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "-", with: "_") {
                case "completed", "complete", "done": status = .completed
                case "in_progress", "active", "doing", "started": status = .inProgress
                default: status = .pending
                }
            }
            return Item(content: content, status: status)
        }
    }

    public func summary(_ args: ToolArguments) -> String {
        guard let items = try? Self.items(from: args) else { return "Update todo list" }
        let done = items.filter { $0.status == .completed }.count
        if let current = items.first(where: { $0.status == .inProgress }) { return "Todo \(done)/\(items.count): \(current.content)" }
        return "Todo list: \(done)/\(items.count) done"
    }

    public func run(_ args: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let items = try Self.items(from: args)
        let inProgress = items.filter { $0.status == .inProgress }.count
        var text = "Todo list updated (\(items.filter { $0.status == .completed }.count)/\(items.count) completed)."
        if inProgress > 1 { text += " Note: \(inProgress) items are in_progress; keep just one." }
        return ToolOutput(text: text)
    }
}
