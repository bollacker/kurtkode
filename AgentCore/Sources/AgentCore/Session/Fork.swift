import Foundation

extension SessionStore {
    /// A new session from `session` at the turn whose reply is `reply`: with `after` false, the messages that turn was
    /// sent (to run it again, on another model or with another message); with `after` true, also its reply and tool
    /// results (to carry on from there). It starts on the model and endpoint that turn used. Compactions, wire
    /// records, and subagent runs of the copied part come along; files on disk are not touched or rewound.
    public func fork(_ session: Session, atReply reply: UUID, after: Bool, title: String) throws -> Session {
        guard let i = session.messages.firstIndex(where: { $0.id == reply }) else {
            throw ToolFailure("that turn isn't in the session")
        }
        let turn = session.messages[i]
        var end = i                                         // exclusive
        if after {
            let calls = Set(turn.toolCalls.map(\.id))
            end = i + 1
            while end < session.messages.count, let id = session.messages[end].toolCallID, calls.contains(id) { end += 1 }
        }
        var header = SessionHeader(endpointID: turn.meta?.endpointID ?? session.endpointID,
                                   model: turn.meta?.requestedModel ?? session.model, workspace: session.header.workspace)
        header.forkedFrom = session.header.id
        header.forkedAtReply = reply
        header.forkedAfter = after
        return try fork(session, into: header, end: end, title: title)
    }

    /// A new session from `session`, with everything before `message` (nil: everything), on the model it uses now: to
    /// send that message differently without losing this conversation. Files on disk are not touched or rewound.
    public func fork(_ session: Session, before message: UUID?, title: String) throws -> Session {
        var end = session.messages.count
        if let message {
            guard let i = session.messages.firstIndex(where: { $0.id == message }) else {
                throw ToolFailure("that message isn't in the session")
            }
            end = i
        }
        var header = SessionHeader(endpointID: session.endpointID, model: session.model, workspace: session.header.workspace)
        header.forkedFrom = session.header.id
        return try fork(session, into: header, end: end, title: title)
    }

    private func fork(_ session: Session, into header: SessionHeader, end: Int, title: String) throws -> Session {
        let messages = Array(session.messages[..<end])
        let ids = Set(messages.map(\.id))
        try create(header)
        var records: [SessionRecord] = [.title(title)]
        if let mode = session.permissionMode { records.append(.permissionMode(mode)) }
        if !session.folders.isEmpty { records.append(.folders(session.folders)) }
        records += messages.map { .message($0) }
        records += session.compactions.filter { ids.contains($0.lastSummarizedID) }.map { .compaction($0) }
        for r in records { try append(r, to: header.id) }

        // The copied turns' wire records and context index, and the subagent runs their task calls started.
        let fm = FileManager.default
        let fromWire = wireDirectory(for: session.header), toWire = wireDirectory(for: header)
        let replies = Set(messages.filter { $0.role == .assistant }.map(\.id))
        try? fm.createDirectory(at: toWire, withIntermediateDirectories: true)
        for id in replies {
            try? fm.copyItem(at: WireLog.url(fromWire, id), to: WireLog.url(toWire, id))
        }
        let index = fromWire.appending(path: "index.jsonl")
        if let data = try? Data(contentsOf: index) {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601              // as WireLog writes it
            let keep = data.split(separator: 0x0A).filter { line in
                (try? dec.decode(ContextSnapshot.self, from: Data(line))).map { replies.contains($0.replyID) } ?? false
            }
            try? Data(keep.joined(separator: [0x0A]) + [0x0A]).write(to: toWire.appending(path: "index.jsonl"))
        }
        let runs = messages.compactMap { $0.toolResult?.subagentRun }
        if !runs.isEmpty {
            let from = subagentDirectory(for: session.header), to = subagentDirectory(for: header)
            try? fm.createDirectory(at: to, withIntermediateDirectories: true)
            for run in runs {
                try? fm.copyItem(at: from.appending(path: "\(run.uuidString).jsonl"), to: to.appending(path: "\(run.uuidString).jsonl"))
            }
        }
        return try load(header.id) ?? session
    }
}
