import AgentCore
import Foundation

/// The text being typed: a buffer of characters and a caret, with no idea of terminals or runs.
public struct TextBuffer: Sendable, Equatable {
    public private(set) var characters: [Character] = []
    public private(set) var caret = 0

    public init(_ text: String = "") { set(text) }

    public var string: String { String(characters) }
    public var isEmpty: Bool { characters.isEmpty }

    public mutating func set(_ text: String) {
        characters = Array(text)
        caret = characters.count
    }

    public mutating func insert(_ text: String) {
        let new = Array(text)
        characters.insert(contentsOf: new, at: caret)
        caret += new.count
    }

    public mutating func backspace() {
        guard caret > 0 else { return }
        caret -= 1
        characters.remove(at: caret)
    }

    public mutating func delete() {
        if caret < characters.count { characters.remove(at: caret) }
    }

    public mutating func left() { caret = max(0, caret - 1) }
    public mutating func right() { caret = min(characters.count, caret + 1) }

    private var lineStart: Int { (characters[..<caret].lastIndex(where: \.isNewline) ?? -1) + 1 }
    private var lineEnd: Int { characters[caret...].firstIndex(where: \.isNewline) ?? characters.count }

    public mutating func home() { caret = lineStart }
    public mutating func end() { caret = lineEnd }

    public mutating func wordLeft() { caret = previousWord() }

    public mutating func wordRight() {
        var i = caret
        while i < characters.count, !isWord(characters[i]) { i += 1 }
        while i < characters.count, isWord(characters[i]) { i += 1 }
        caret = i
    }

    private func isWord(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

    private func previousWord() -> Int {
        var i = caret
        while i > 0, !isWord(characters[i - 1]) { i -= 1 }
        while i > 0, isWord(characters[i - 1]) { i -= 1 }
        return i
    }

    /// Ctrl-W: back to the start of the word.
    public mutating func deleteWord() {
        let start = previousWord()
        characters.removeSubrange(start..<caret)
        caret = start
    }

    /// Ctrl-U.
    public mutating func deleteToLineStart() {
        let start = lineStart
        characters.removeSubrange(start..<caret)
        caret = start
    }

    /// Ctrl-K.
    public mutating func deleteToLineEnd() { characters.removeSubrange(caret..<lineEnd) }

    /// Up or down a line of the text, keeping the column; false on the first or last line (the keys then go to history).
    public mutating func move(up: Bool) -> Bool {
        let start = lineStart, column = caret - start
        if up {
            guard start > 0 else { return false }
            let above = (characters[..<(start - 1)].lastIndex(where: \.isNewline) ?? -1) + 1
            caret = min(above + column, start - 1)
        } else {
            let end = lineEnd
            guard end < characters.count else { return false }
            let next = end + 1
            let nextEnd = characters[next...].firstIndex(where: \.isNewline) ?? characters.count
            caret = min(next + column, nextEnd)
        }
        return true
    }

    /// Replaces the `count` characters before the caret.
    public mutating func replaceBefore(count: Int, with text: String) {
        let start = max(0, caret - count)
        characters.removeSubrange(start..<caret)
        caret = start
        insert(text)
    }
}

/// A row of the completion list.
public struct Completion: Equatable, Sendable {
    public var text: String
    public var detail: String
    /// A command that needs nothing more: picking it runs it.
    public var runs: Bool

    public init(text: String, detail: String = "", runs: Bool = false) {
        self.text = text
        self.detail = detail
        self.runs = runs
    }
}

/// What was typed at a follow-up prompt. Whole words only: Enter on text typed ahead mustn't accept a paid hand-over
/// because it starts with the right letter.
public enum PromptWord {
    public static func says(_ typed: String?, _ words: String...) -> Bool {
        guard let typed else { return false }
        return words.contains(typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    public static func yes(_ typed: String?) -> Bool { says(typed, "y", "yes") }
}

/// What a key press asks of the rest of the program.
public enum InputAction: Equatable, Sendable {
    case submit(String)
    case answer(String?)
    case stop
    case interrupt
    case quit
    case cycleMode
    case showOutput
    case showRewind
    case suspend
    case attachImage
    case note(String)
}

/// A question's options under the composer: a list to move through and pick from, while typing still answers in words.
public struct QuestionChoices: Sendable, Equatable {
    /// How long after a question opens typing doesn't count as its answer.
    static let settle: TimeInterval = 0.5

    public var options: [UserQuestion.Option]
    public var multiple: Bool
    public var recommended: Int?
    public var selected = 0
    public var picked: Set<Int> = []

    public init(_ question: UserQuestion) {
        options = question.options
        multiple = question.multiple
        recommended = question.recommended
    }

    /// The pick as numbers, the way they'd be typed (`UserQuestion.answer(fromTyped:)`): the boxes ticked, or the option
    /// the list is on.
    public var answer: String {
        (picked.isEmpty ? [selected] : picked.sorted()).map { String($0 + 1) }.joined(separator: ",")
    }
}

/// The input line's state: the text, history, completions, long pastes, what's queued while a run goes, and a question
/// waiting for its answer. Every key goes through `handle`, so all of this can be tested without a terminal.
public struct InputState: Sendable {
    public var buffer = TextBuffer()
    /// A run is going: Enter queues.
    public var busy = false
    /// What's waiting for the run: messages at its next step, commands at its end.
    public private(set) var queued: [String] = []
    public private(set) var history: [String]
    private var recall: PromptRecall?
    private var recalled: String?
    public private(set) var pastes: [PastedText] = []
    public private(set) var images: [ImageAttachment] = []
    public var completions: [Completion] = []
    public private(set) var selected = 0
    private var hiddenFor: String?
    /// The question being answered, and the text set aside for it.
    public private(set) var question: String?
    private var setAside: TextBuffer?
    /// The question's options, when it has them.
    public private(set) var choices: QuestionChoices?
    private var questionOpened: Date?
    /// Ctrl-R: the search typed so far, and the match's place in the history.
    public private(set) var search: String?
    private var searchIndex: Int?
    private var lastEsc: Date?

    public init(history: [String] = []) { self.history = history }

    public var canCompleteNow: Bool { question == nil && search == nil && hiddenFor != buffer.string }

    /// The start of the token being completed, and what's typed of it: a command on the first word of the text, a path
    /// after `@`.
    public var completionToken: (kind: Character, text: String)? {
        let before = buffer.characters[..<buffer.caret]
        let start = before.lastIndex(where: \.isWhitespace).map { $0 + 1 } ?? 0
        let word = String(before[start...])
        if start == 0, word.hasPrefix("/") { return ("/", String(word.dropFirst())) }
        if word.hasPrefix("@") { return ("@", word.dropFirst().trimmingCharacters(in: CharacterSet(charactersIn: "\""))) }
        return nil
    }

    private mutating func clearEntry() {
        buffer = TextBuffer()
        recall = nil
        recalled = nil
        hiddenFor = nil
    }

    /// Something typed that a run can't take now, or that it's left behind: back in the draft, ahead of what's being typed.
    public mutating func restore(_ text: String) {
        buffer.set(joinedDraft([text, buffer.string]))
    }

    public mutating func addImage(_ image: ImageAttachment) { images.append(image) }

    /// The images typed with this message; they go with it.
    public mutating func takeImages() -> [ImageAttachment] {
        defer { images = [] }
        return images
    }

    // MARK: Questions

    public mutating func beginQuestion(_ prompt: String, choices: QuestionChoices? = nil, now: Date = Date()) {
        question = prompt
        self.choices = choices
        questionOpened = now
        search = nil
        searchIndex = nil
        setAside = buffer
        buffer = TextBuffer()
        completions = []
    }

    public mutating func endQuestion() {
        question = nil
        choices = nil
        questionOpened = nil
        buffer = setAside ?? TextBuffer()
        setAside = nil
    }

    // MARK: Queue

    /// Messages for the run's next step, up to the first command: that stays for the run's end, and what was typed after
    /// it stays behind it.
    public mutating func takeQueuedMessages() -> [String] {
        let messages = Array(queued.prefix { !Self.isCommand($0) })
        queued.removeFirst(messages.count)
        return messages
    }

    /// What goes next after a run that finished: a command alone, or the messages up to the next one as one request.
    public mutating func nextQueued() -> String? {
        guard let first = queued.first else { return nil }
        if Self.isCommand(first) { return queued.removeFirst() }
        let messages = queued.prefix { !Self.isCommand($0) }
        queued.removeFirst(messages.count)
        return messages.joined(separator: "\n\n")
    }

    /// A run that was stopped: nothing goes unasked. It's all back in the draft.
    public mutating func unqueue() {
        guard !queued.isEmpty else { return }
        buffer.set(joinedDraft(queued + [buffer.string]))
        queued = []
    }

    static func isCommand(_ text: String) -> Bool { SlashCommands.parse(text) != nil || UserShell.command(in: text) != nil }

    // MARK: Keys

    public mutating func handle(_ key: Key, now: Date = Date()) -> InputAction? {
        if search != nil { return handleSearch(key) }
        // What's typed just as a question opens was meant for what was being typed: it goes on there, and Enter doesn't
        // answer. Otherwise `y` and Enter already on their way would approve a card nobody has read.
        if let opened = questionOpened, now.timeIntervalSince(opened) < QuestionChoices.settle {
            switch key {
            case .text(let s):
                setAside?.insert(s)
                return nil
            case .enter: return nil
            default: break
            }
        }
        defer { if key != .esc { lastEsc = nil } }
        if choices != nil, let handled = handleChoices(key) { return handled }
        if !completions.isEmpty, let handled = handleCompletion(key) { return handled }
        switch key {
        case .text(let s): buffer.insert(s)
        case .paste(let s):
            if PastedText.isLong(s) {
                let paste = PastedText(id: (pastes.last?.id ?? 0) + 1, text: s)
                pastes.append(paste)
                buffer.insert(paste.token)
            } else {
                buffer.insert(s)
            }
        case .newline: buffer.insert("\n")
        case .enter: return enter()
        case .backspace: buffer.backspace()
        case .delete: buffer.delete()
        case .left: buffer.left()
        case .right: buffer.right()
        case .home: buffer.home()
        case .end: buffer.end()
        case .wordLeft: buffer.wordLeft()
        case .wordRight: buffer.wordRight()
        case .up: walk(older: true)
        case .down: walk(older: false)
        case .tab: return nil
        case .shiftTab: return question == nil ? .cycleMode : nil
        case .esc:
            if question != nil { return .answer(nil) }
            if busy { return .stop }
            defer { lastEsc = now }
            if let last = lastEsc, now.timeIntervalSince(last) < 0.6, buffer.isEmpty { return .showRewind }
        case .ctrl(let c): return control(c)
        }
        return nil
    }

    private mutating func enter() -> InputAction? {
        if question != nil {
            let text = PastedText.expand(buffer.string, pastes)
            buffer = TextBuffer()
            return .answer(text)
        }
        // A queued message goes later, and its images might then go with something else.
        if busy, !images.isEmpty { return .note("An image goes with a message once the run is done: press Enter then.") }
        // A trailing backslash goes on to the next line, as at a shell.
        if buffer.caret == buffer.characters.count, buffer.string.hasSuffix("\\"), !buffer.string.hasSuffix("\\\\") {
            buffer.backspace()
            buffer.insert("\n")
            return nil
        }
        let text = PastedText.text(of: buffer.string, pastes)
        guard !text.isEmpty || !images.isEmpty else { return nil }
        let waiting = recall?.waiting ?? ""
        remember(text)
        clearEntry()
        buffer.set(waiting)
        return .submit(text)
    }

    /// Goes in the history for ↑, unless a shell wouldn't keep it. The file is the caller's to save.
    private mutating func remember(_ text: String) {
        if !text.isEmpty, text != history.last { history.append(text) }
    }

    /// A message that arrived while a run goes.
    public mutating func enqueue(_ text: String) { queued.append(text) }

    /// ↑ and ↓: in multi-line text, up and down it; past its edge, the queue and then the history. Once a prompt is
    /// recalled, the arrows go on through them wherever the caret is, until it's edited.
    private mutating func walk(older: Bool) {
        guard question == nil else { return }
        let walking = recall?.isWalking == true && buffer.string == recalled
        if !walking {
            if buffer.move(up: older) { return }
            if older, buffer.isEmpty, let last = queued.popLast() {
                buffer.set(last)
                return
            }
            recall = PromptRecall(entries: history)
        }
        guard let next = older ? recall?.older(draft: buffer.string) : recall?.newer() else { return }
        recalled = next
        buffer.set(next)
    }

    private mutating func control(_ c: Character) -> InputAction? {
        switch c {
        case "c": return .interrupt
        case "d":
            if question != nil { return .answer(nil) }
            if buffer.isEmpty { return .quit }
            buffer.delete()
        case "a": buffer.home()
        case "e": buffer.end()
        case "b": buffer.left()
        case "f": buffer.right()
        case "k": buffer.deleteToLineEnd()
        case "u": buffer.deleteToLineStart()
        case "w": buffer.deleteWord()
        case "l": return nil
        case "o": return .showOutput
        case "z": return .suspend
        case "v": return .attachImage
        case "r":
            if question == nil {
                search = ""
                searchIndex = nil
            }
        default: break
        }
        return nil
    }

    // MARK: Choices

    /// A key the question's options take for themselves: what it asks for, if anything. Nil: the key goes to the text,
    /// which is the answer in the user's own words.
    private mutating func handleChoices(_ key: Key) -> InputAction?? {
        guard var list = choices else { return nil }
        defer { choices = list }
        switch key {
        case .up: list.selected = (list.selected + list.options.count - 1) % list.options.count
        case .down: list.selected = (list.selected + 1) % list.options.count
        case .text(let s) where s == " " && list.multiple && buffer.isEmpty:
            if list.picked.insert(list.selected).inserted == false { list.picked.remove(list.selected) }
        case .enter where buffer.isEmpty: return .some(.answer(list.answer))
        default: return nil
        }
        return .some(nil)
    }

    // MARK: Completions

    /// A key the list takes for itself: what it asks for, if anything. Nil: the key isn't the list's.
    private mutating func handleCompletion(_ key: Key) -> InputAction?? {
        let current = completions[min(selected, completions.count - 1)]
        switch key {
        case .up: selected = (selected + completions.count - 1) % completions.count
        case .down: selected = (selected + 1) % completions.count
        case .tab:
            fill(current)
        case .enter:
            fill(current)
            // A path, or a command that takes arguments, goes on being typed.
            guard current.runs else { return .some(nil) }
            let text = buffer.string.trimmingCharacters(in: .whitespacesAndNewlines)
            remember(text)
            clearEntry()
            completions = []
            return .submit(text)
        case .esc:
            hiddenFor = buffer.string
            completions = []
        default: return nil
        }
        return .some(nil)
    }

    private mutating func fill(_ c: Completion) {
        guard let token = completionToken else { return }
        // "/" or "@" plus what's typed of the name.
        let typed = String(buffer.characters[..<buffer.caret]).split(whereSeparator: \.isWhitespace).last.map(\.count) ?? 0
        let needsQuotes = token.kind == "@" && c.text.contains(" ")
        let text = String(token.kind) + (needsQuotes ? "\"\(c.text)\"" : c.text)
        buffer.replaceBefore(count: typed, with: text + (c.text.hasSuffix("/") ? "" : " "))
        completions = []
        selected = 0
    }

    /// Sets the list for what's typed; the selection starts over when it changes.
    public mutating func setCompletions(_ list: [Completion]) {
        if list != completions { selected = 0 }
        completions = list
    }

    // MARK: Search

    /// The history entry the search has found.
    public var searchMatch: String? { searchIndex.map { history[$0] } }

    private mutating func handleSearch(_ key: Key) -> InputAction? {
        switch key {
        case .text(let s):
            search = (search ?? "") + s
            findMatch(before: history.count)
        case .backspace:
            search = String((search ?? "").dropLast())
            findMatch(before: history.count)
        case .ctrl("r"):
            findMatch(before: searchIndex ?? history.count)
        case .ctrl("c"), .esc, .ctrl("g"):
            search = nil
            searchIndex = nil
        default:
            if let match = searchMatch { buffer.set(match) }
            search = nil
            searchIndex = nil
            // Enter only takes the match, to look at it; other keys go on as usual.
            if key != .enter { return handle(key) }
        }
        return nil
    }

    private mutating func findMatch(before end: Int) {
        guard let q = search, !q.isEmpty else {
            searchIndex = nil
            return
        }
        if let i = history[..<end].lastIndex(where: { $0.localizedCaseInsensitiveContains(q) }) { searchIndex = i }
        else if end == history.count { searchIndex = nil }
    }
}
