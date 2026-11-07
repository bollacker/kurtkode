import Foundation
import Testing
@testable import AgentCore
@testable import KurtkodeCLI

// The terminal's live screen: everything that decides anything, without a terminal.

private let plain = TerminalStyle(on: false)

@Suite struct KeyDecoderTests {
    private func keys(_ s: String) -> [Key] {
        var d = KeyDecoder()
        return d.feed(Array(s.utf8))
    }

    @Test func typingGathersIntoText() {
        #expect(keys("héllo") == [.text("héllo")])
        #expect(keys("a\rb") == [.text("a"), .enter, .text("b")])
    }

    @Test func controlKeys() {
        #expect(keys("\u{3}") == [.ctrl("c")])
        #expect(keys("\u{4}\u{12}") == [.ctrl("d"), .ctrl("r")])
        #expect(keys("\n") == [.newline])                                   // Ctrl-J
        #expect(keys("\t\u{7F}") == [.tab, .backspace])
    }

    @Test func sequences() {
        #expect(keys("\u{1B}[A\u{1B}[B\u{1B}[C\u{1B}[D") == [.up, .down, .right, .left])
        #expect(keys("\u{1B}OA") == [.up])
        #expect(keys("\u{1B}[Z") == [.shiftTab])
        #expect(keys("\u{1B}[3~") == [.delete])
        #expect(keys("\u{1B}[H\u{1B}[F") == [.home, .end])
        #expect(keys("\u{1B}[1;5C\u{1B}b") == [.wordRight, .wordLeft])
        #expect(keys("\u{1B}\r") == [.newline])                             // Alt-Enter
        #expect(keys("\u{1B}[13;2u") == [.newline])                         // Shift-Enter, the kitty protocol
        #expect(keys("\u{1B}[99~").isEmpty)
    }

    @Test func aLoneEscWaitsToSeeIfItStartsASequence() {
        var d = KeyDecoder()
        #expect(d.feed([0x1B]).isEmpty)
        #expect(d.flush() == [.esc])
        #expect(d.flush().isEmpty)
        #expect(d.feed([0x1B]).isEmpty)
        #expect(d.feed(Array("[A".utf8)) == [.up])                          // cut between reads
    }

    @Test func aPasteArrivesWhole() {
        #expect(keys("\u{1B}[200~one\rtwo\nthree\u{1B}[201~x") == [.paste("one\ntwo\nthree"), .text("x")])
        var d = KeyDecoder()
        #expect(d.feed(Array("\u{1B}[200~half".utf8)).isEmpty)
        #expect(d.feed(Array(" done\u{1B}[201~".utf8)) == [.paste("half done")])
    }

    @Test func aCharacterCutBetweenReadsWaits() {
        var d = KeyDecoder()
        let bytes = Array("é".utf8)
        #expect(d.feed(bytes[..<1]).isEmpty)
        #expect(d.feed(bytes[1...]) == [.text("é")])
    }
}

@Suite struct TextBufferTests {
    @Test func editsAtTheCaret() {
        var b = TextBuffer("helo")
        b.left()
        b.insert("l")
        #expect(b.string == "hello" && b.caret == 4)
        b.backspace()
        b.delete()
        #expect(b.string == "hel")
    }

    @Test func wordsAndLines() {
        var b = TextBuffer("one two.three")
        b.wordLeft()
        #expect(b.caret == 8)
        b.deleteWord()
        #expect(b.string == "one three")
        b.end()
        b.deleteToLineStart()
        #expect(b.isEmpty)
        b.set("first\nsecond")
        b.home()
        b.deleteToLineEnd()
        #expect(b.string == "first\n")
    }

    @Test func movesBetweenLinesKeepingTheColumn() {
        var b = TextBuffer("long first line\nab\nthird line")
        var moved = b.move(up: true)
        #expect(moved && b.caret == "long first line\nab".count)     // clamped to the short line
        moved = b.move(up: true)
        #expect(moved)
        moved = b.move(up: true)
        #expect(!moved)                                     // the first line: the key goes to history
        for _ in 0..<2 {
            moved = b.move(up: false)
            #expect(moved)
        }
        moved = b.move(up: false)
        #expect(!moved)
    }
}

@Suite struct InputStateTests {
    private func typed(_ s: String, history: [String] = []) -> InputState {
        var i = InputState(history: history)
        _ = i.handle(.text(s))
        return i
    }

    @Test func enterSubmitsAndRemembers() {
        var i = typed("  hello  ")
        #expect(i.handle(.enter) == .submit("hello"))
        #expect(i.buffer.isEmpty && i.history == ["hello"])
        #expect(i.handle(.enter) == nil)                    // nothing to send
    }

    @Test func aTrailingBackslashContinuesTheLine() {
        var i = typed("one\\")
        #expect(i.handle(.enter) == nil)
        #expect(i.buffer.string == "one\n")
    }

    @Test func historyWalksAndTheDraftComesBack() {
        var i = typed("half", history: ["old", "new"])
        _ = i.handle(.up)
        #expect(i.buffer.string == "new")
        _ = i.handle(.up)
        #expect(i.buffer.string == "old")
        _ = i.handle(.down)
        _ = i.handle(.down)
        #expect(i.buffer.string == "half")
    }

    @Test func multiLineTextTakesTheArrowsBeforeHistory() {
        var i = InputState(history: ["old"])
        _ = i.handle(.paste("one\ntwo"))
        _ = i.handle(.up)
        #expect(i.buffer.string == "one\ntwo")              // moved up inside it
        _ = i.handle(.up)
        #expect(i.buffer.string == "old")
    }

    @Test func longPastesBecomeTokensAndGoInFull() {
        var i = InputState()
        let long = String(repeating: "line\n", count: 20)
        _ = i.handle(.paste(long))
        _ = i.handle(.text(" look"))
        #expect(i.buffer.string == "[Pasted text #1: 20 lines] look")
        #expect(i.handle(.enter) == .submit(PastedText.messageMark + (long + " look").trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    @Test func theQueueGoesInOrder() {
        var i = InputState()
        i.enqueue("a message")
        i.enqueue("another")
        i.enqueue("!ls")
        i.enqueue("/compact")
        i.enqueue("last")
        #expect(i.takeQueuedMessages() == ["a message", "another"])             // the run's next step
        #expect(i.takeQueuedMessages().isEmpty)                                 // what's behind a command waits for it
        #expect(i.nextQueued() == "!ls")
        #expect(i.nextQueued() == "/compact")
        #expect(i.nextQueued() == "last")
        #expect(i.nextQueued() == nil)
        i.enqueue("one")
        i.enqueue("two")
        i.enqueue("/help")
        #expect(i.nextQueued() == "one\n\ntwo")                                 // messages in a row are one request
    }

    @Test func aStoppedRunPutsTheQueueBackInTheDraft() {
        var i = typed("typing")
        i.enqueue("queued")
        i.enqueue("!ls")
        i.unqueue()
        #expect(i.buffer.string == "queued\n\n!ls\n\ntyping" && i.queued.isEmpty)
    }

    @Test func upTakesBackWhatsQueued() {
        var i = InputState(history: ["old"])
        i.enqueue("first")
        i.enqueue("second")
        _ = i.handle(.up)
        #expect(i.buffer.string == "second" && i.queued == ["first"])
    }

    @Test func aQuestionSetsTheDraftAsideAndNeverSubmitsIt() {
        var i = typed("half a message")
        i.busy = true
        i.beginQuestion("Allow? ", now: .distantPast)
        #expect(i.buffer.isEmpty)
        _ = i.handle(.text("y"))
        #expect(i.handle(.enter) == .answer("y"))
        i.endQuestion()
        #expect(i.buffer.string == "half a message")
        i.beginQuestion("Allow? ")
        #expect(i.handle(.esc) == .answer(nil))
    }

    private func choosing(_ question: UserQuestion, draft: String = "") -> InputState {
        var i = typed(draft)
        i.beginQuestion("  › ", choices: QuestionChoices(question), now: Date(timeIntervalSince1970: 0))
        return i
    }
    private let later = Date(timeIntervalSince1970: 10)

    @Test func theArrowsMoveThroughTheOptionsAndEnterPicks() {
        var i = choosing(UserQuestion(question: "?", options: ["Red", "Green", "Blue"]))
        #expect(i.handle(.enter, now: later) == .answer("1"))
        i = choosing(UserQuestion(question: "?", options: ["Red", "Green", "Blue"]))
        _ = i.handle(.down, now: later)
        _ = i.handle(.down, now: later)
        _ = i.handle(.down, now: later)                     // round to the top
        _ = i.handle(.up, now: later)                       // and back to the bottom
        #expect(i.choices?.selected == 2)
        #expect(i.handle(.enter, now: later) == .answer("3"))
    }

    @Test func spacePicksSeveralAndEnterSendsThem() {
        let question = UserQuestion(question: "?", options: ["Red", "Green", "Blue"], multiple: true)
        var i = choosing(question)
        _ = i.handle(.text(" "), now: later)
        _ = i.handle(.down, now: later)
        _ = i.handle(.down, now: later)
        _ = i.handle(.text(" "), now: later)
        _ = i.handle(.up, now: later)
        _ = i.handle(.text(" "), now: later)
        _ = i.handle(.text(" "), now: later)                // ticked, then unticked
        #expect(i.choices?.picked == [0, 2] && i.buffer.isEmpty)
        guard case .answer(let typed?)? = i.handle(.enter, now: later) else { Issue.record("no answer"); return }
        #expect(question.answer(fromTyped: typed) == "Red; Blue")
    }

    @Test func enterWithNothingTickedTakesTheOptionTheListIsOn() {
        var i = choosing(UserQuestion(question: "?", options: ["Red", "Green"], multiple: true))
        _ = i.handle(.down, now: later)
        #expect(i.handle(.enter, now: later) == .answer("2"))
    }

    @Test func typingAnswersInWordsOverTheOptions() {
        var i = choosing(UserQuestion(question: "?", options: ["Red", "Green"], multiple: true))
        _ = i.handle(.text("neither"), now: later)
        _ = i.handle(.text(" "), now: later)                // a space in the words, not a tick
        _ = i.handle(.text("one"), now: later)
        _ = i.handle(.down, now: later)
        #expect(i.choices?.picked == [] && i.buffer.string == "neither one")
        #expect(i.handle(.enter, now: later) == .answer("neither one"))
    }

    @Test func enterJustAsAQuestionOpensDoesntPickItsFirstOption() {
        var i = choosing(UserQuestion(question: "?", options: ["Red", "Green"]))
        #expect(i.handle(.enter, now: Date(timeIntervalSince1970: 0.2)) == nil)
        #expect(i.question != nil)
        #expect(i.handle(.enter, now: Date(timeIntervalSince1970: 0.6)) == .answer("1"))
    }

    @Test func escSkipsAndTheDraftComesBack() {
        var i = choosing(UserQuestion(question: "?", options: ["Red", "Green"]), draft: "half a message")
        #expect(i.buffer.isEmpty)
        #expect(i.handle(.esc, now: later) == .answer(nil))
        i.endQuestion()
        #expect(i.choices == nil && i.buffer.string == "half a message")
        // Nothing of the list stays behind: the arrows are the composer's again.
        _ = i.handle(.up, now: later)
        #expect(i.choices == nil)
    }

    @Test func escStopsARunAndTwiceOpensRewindWhenIdle() {
        var i = InputState()
        i.busy = true
        #expect(i.handle(.esc) == .stop)
        i.busy = false
        let start = Date()
        #expect(i.handle(.esc, now: start) == nil)
        #expect(i.handle(.esc, now: start.addingTimeInterval(0.3)) == .showRewind)
        #expect(i.handle(.esc, now: start.addingTimeInterval(9)) == nil)        // too slow
    }

    @Test func ctrlDQuitsOnlyOnAnEmptyLine() {
        var i = typed("x")
        _ = i.handle(.home)
        #expect(i.handle(.ctrl("d")) == nil)
        #expect(i.buffer.isEmpty)
        #expect(i.handle(.ctrl("d")) == .quit)
    }

    @Test func modesAndKeysGoOut() {
        var i = InputState()
        #expect(i.handle(.shiftTab) == .cycleMode)
        #expect(i.handle(.ctrl("o")) == .showOutput)
        #expect(i.handle(.ctrl("c")) == .interrupt)
        #expect(i.handle(.ctrl("v")) == .attachImage)
    }

    @Test func completionsFillRunAndHide() {
        var i = typed("/co")
        #expect(i.completionToken?.kind == "/" && i.completionToken?.text == "co")
        i.setCompletions([Completion(text: "compact"), Completion(text: "context", runs: true)])
        _ = i.handle(.down)
        #expect(i.selected == 1)
        #expect(i.handle(.enter) == .submit("/context"))        // needs nothing more: it runs
        i = typed("/co")
        i.setCompletions([Completion(text: "compact")])
        _ = i.handle(.tab)
        #expect(i.buffer.string == "/compact ")
        i = typed("look at @sr")
        #expect(i.completionToken?.kind == "@" && i.completionToken?.text == "sr")
        i.setCompletions([Completion(text: "src/")])
        _ = i.handle(.tab)
        #expect(i.buffer.string == "look at @src/")             // a folder stays open
        i = typed("/co")
        i.setCompletions([Completion(text: "compact")])
        _ = i.handle(.esc)
        #expect(i.completions.isEmpty && !i.canCompleteNow)
    }

    @Test func historySearchFindsOlderMatches() {
        var i = InputState(history: ["fix the tests", "add a feature", "fix the build"])
        _ = i.handle(.ctrl("r"))
        _ = i.handle(.text("fix"))
        #expect(i.searchMatch == "fix the build")
        _ = i.handle(.ctrl("r"))
        #expect(i.searchMatch == "fix the tests")
        _ = i.handle(.enter)
        #expect(i.search == nil && i.buffer.string == "fix the tests")
    }
}

@Suite struct MarkdownLinesTests {
    private func render(_ lines: [String]) -> [String] {
        var m = MarkdownLines(style: plain)
        return lines.map { m.render($0) }
    }

    @Test func structure() {
        #expect(render(["# Title", "## Sub ##", "- item", "  * nested", "> quote", "---"])
                == ["Title", "Sub", "• item", "  • nested", "│ quote", String(repeating: "─", count: 40)])
    }

    @Test func aCodeBlockIsLeftAlone() {
        #expect(render(["```swift", "let x = **1**", "# not a heading", "```", "after"])
                == ["  swift", "  let x = **1**", "  # not a heading", "", "after"])
    }

    @Test func inlineMarks() {
        let m = MarkdownLines(style: plain)
        #expect(m.inline("a **bold** and *it* and `code` and [text](http://x)") == "a bold and it and code and text (http://x)")
    }

    @Test func aStrayMarkStays() {
        let m = MarkdownLines(style: plain)
        #expect(m.inline("2 * 3 * 4") == "2 * 3 * 4")
        #expect(m.inline("snake_case and **open") == "snake_case and **open")
    }

    @Test func colorMarksWhatItMeans() {
        var m = MarkdownLines(style: TerminalStyle(on: true))
        #expect(m.render("use `x`").contains("\u{1B}[36mx\u{1B}[0m"))
    }
}

@Suite struct TerminalTextTests {
    @Test func widthIgnoresEscapesAndCountsWideCharacters() {
        #expect(TerminalText.width("\u{1B}[1mhello\u{1B}[0m") == 5)
        #expect(TerminalText.width("日本") == 4)
        #expect(TerminalText.width("e\u{301}") == 1)
        #expect(TerminalText.width("›") == 1 && TerminalText.width("🙂") == 2)
    }

    @Test func truncationKeepsEscapesAndCloses() {
        #expect(TerminalText.truncate("hello world", to: 6) == "hello…")
        #expect(TerminalText.truncate("short", to: 6) == "short")
        let cut = TerminalText.truncate("\u{1B}[2mhello world\u{1B}[0m", to: 6)
        #expect(TerminalText.width(cut) == 6 && cut.hasSuffix("\u{1B}[0m"))
    }

    @Test func layoutWrapsAndPlacesTheCaret() {
        let (rows, positions) = TerminalText.layout(Array("abcdef\ng"), width: 4)
        #expect(rows == ["abcd", "ef", "g"])
        #expect(positions[4].row == 1 && positions[4].column == 0)
        #expect(positions.last?.row == 2 && positions.last?.column == 1)
    }

    @Test func diffsAreCutAndLoseTheirFileLines() {
        let lines = DiffPreview.lines("--- a\n+++ b\n@@ -1 +1 @@\n-old\n+new\n", limit: 2, style: plain)
        #expect(lines == ["@@ -1 +1 @@", "-old", "… 1 more lines"])
    }
}

@Suite struct FrameTests {
    private func frame(_ input: InputState = InputState(), status: StatusInfo = StatusInfo(), live: String = "", tail: [String] = [],
                       width: Int = 40, height: Int = 24) -> Frame {
        Frame.make(input: input, status: status, live: live, tail: tail, width: width, height: height, style: plain)
    }

    @Test func idleIsTheComposerAndTheStatus() {
        var s = StatusInfo()
        s.model = "org/some-model"
        s.mode = "Ask"
        let f = frame(status: s, width: 200)
        #expect(f.rows.count == 2 && f.rows[0] == "› ")
        #expect(f.rows[1].hasPrefix("some-model · Ask"))
        #expect(f.caretRow == 0 && f.caretColumn == 2)
    }

    @Test func theCaretFollowsWrappedText() {
        var i = InputState()
        _ = i.handle(.text(String(repeating: "x", count: 50)))
        let f = frame(i, width: 21)
        #expect(f.rows[1].hasPrefix("  x"))                 // wrapped, aligned under the text
        #expect(f.caretRow == 2)
    }

    @Test func aRunShowsWhatItsDoing() {
        var s = StatusInfo()
        s.runStarted = Date()
        s.activity = "Run tests"
        s.steps = 3
        let f = frame(status: s, live: "partial line", tail: ["output"], width: 100)
        #expect(f.rows[0] == "partial line" && f.rows[1] == "  output")
        #expect(f.rows[2].contains("Run tests") && f.rows[2].contains("step 3") && f.rows[2].contains("esc to stop"))
    }

    @Test func aQuestionSaysItsWaitingNotWorking() {
        var s = StatusInfo()
        s.runStarted = Date()
        var i = InputState()
        i.beginQuestion("  › ")
        let rows = frame(i, status: s, width: 100).rows
        #expect(rows.contains { $0.contains("waiting for your answer") } && !rows.contains { $0.contains("esc to stop") })
        #expect(rows.contains { $0.hasPrefix("  › ") })
    }

    @Test func aQuestionsOptionsAreListedUnderTheComposer() {
        var i = InputState()
        let question = UserQuestion(question: "?", options: [.init("SQLite", description: "Nothing to run."), "Postgres"])
        i.beginQuestion("  › ", choices: QuestionChoices(question))
        let rows = frame(i, width: 100).rows
        #expect(rows.contains("  1. SQLite (recommended)  Nothing to run."))
        #expect(rows.contains("  2. Postgres"))
        #expect(rows.contains { $0.contains("enter answer") && !$0.contains("space select") })
    }

    @Test func tickBoxesShowWhenSeveralMayBePicked() {
        var i = InputState()
        var choices = QuestionChoices(UserQuestion(question: "?", options: ["Red", "Green"], multiple: true))
        choices.picked = [1]
        i.beginQuestion("  › ", choices: choices)
        let rows = frame(i, width: 100).rows
        #expect(rows.contains("  1. [ ] Red") && rows.contains("  2. [x] Green"))
        #expect(rows.contains { $0.contains("space select") })
    }

    @Test func aDescriptionTheRowCutsOffIsShownInFull() {
        var i = InputState()
        let long = String(repeating: "word ", count: 12) + "end"
        i.beginQuestion("  › ", choices: QuestionChoices(UserQuestion(question: "?", options: [.init("Red", description: long), "Green"])))
        let rows = frame(i, width: 40, height: 40).rows
        #expect(rows.contains { $0.contains("end") })
        #expect(rows.allSatisfy { TerminalText.width($0) < 40 })
    }

    @Test func nothingIsAsWideAsTheTerminal() {
        var s = StatusInfo()
        s.model = String(repeating: "m", count: 200)
        s.runStarted = Date()
        var i = InputState()
        i.enqueue(String(repeating: "q", count: 200))
        for row in frame(i, status: s, width: 30).rows { #expect(TerminalText.width(row) < 30) }
    }

    @Test func aHugeDraftStaysOnTheScreenAroundTheCaret() {
        var i = InputState()
        _ = i.handle(.paste((1...5).map { "line \($0)" }.joined(separator: "\n")))
        for n in 6...40 { _ = i.handle(.newline); _ = i.handle(.text("line \(n)")) }
        let f = frame(i, height: 10)
        #expect(f.rows.count <= 9)
        #expect(f.rows[f.caretRow].contains("line 40"))
    }

    @Test func queuedItemsShow() {
        var i = InputState()
        i.enqueue("a message")
        i.enqueue("!ls")
        let rows = frame(i, width: 100).rows
        #expect(rows.contains { $0.contains("a message") } && rows.contains { $0.contains("!ls") })
    }
}

@Suite struct LiveScreenTests {
    @Test func itGoesBackToTheFramesTopAndClearsDown() {
        var s = LiveScreen()
        let first = s.update(commit: "", frame: Frame(rows: ["› a", "status"], caretRow: 0, caretColumn: 3))
        #expect(first.contains("› a\nstatus\u{1B}[1A\r\u{1B}[3C"))
        #expect(!first.contains("\u{1B}[J"))                // nothing drawn yet
        let second = s.update(commit: "output\n", frame: Frame(rows: ["› b", "status"], caretRow: 1, caretColumn: 0))
        #expect(second.contains("\r\u{1B}[Joutput\n› b\nstatus"))
        let third = s.update(commit: "", frame: Frame(rows: ["x"], caretRow: 0, caretColumn: 0))
        #expect(third.contains("\u{1B}[1A\r\u{1B}[J"))      // from the second row
    }

    @Test func committedTextAlwaysEndsItsLine() {
        var s = LiveScreen()
        #expect(s.update(commit: "no newline", frame: Frame(rows: ["x"], caretRow: 0, caretColumn: 0)).contains("no newline\nx"))
    }
}

private final class Lines: @unchecked Sendable {
    let lock = NSLock()
    var text = ""
    var live: [String] = []
}

@Suite struct RichRendererTests {
    private func renderer(_ lines: Lines) -> Renderer {
        Renderer(style: .interactive, rich: true, live: { s in lines.lock.withLock { lines.live.append(s) } },
                 out: { s in lines.lock.withLock { lines.text += s } }, err: { _ in })
    }

    @Test func finishedLinesGoOutRenderedAndTheRestWaits() {
        let l = Lines()
        let r = renderer(l)
        var snap = TurnSnapshot()
        snap.content = "# Title\nhalf"
        r.handle(.streaming(snap))
        #expect(l.text == "Title\n" && l.live.last == "half")
        r.handle(.assistant(ChatMessage(role: .assistant, content: "# Title\nhalf a **line**")))
        #expect(l.text == "Title\nhalf a line\n" && l.live.last == "")
    }

    @Test func anEditShowsItsDiff() {
        let l = Lines()
        var info = ToolResultInfo(toolName: "edit_file", isError: false, truncated: false, duration: 0)
        info.display = "--- a\n+++ b\n@@ -1 +1 @@\n-old\n+new\n"
        renderer(l).handle(.toolFinished(ChatMessage(role: .tool, content: "ok", toolCallID: "1", toolResult: info)))
        #expect(l.text.contains("-old") && l.text.contains("+new") && !l.text.contains("--- a"))
    }

    @Test func aCommandLeavesItsLastLines() {
        let l = Lines()
        var info = ToolResultInfo(toolName: "bash", isError: false, truncated: false, duration: 0)
        info.display = "one\ntwo\nthree\nfour\n[Exit code 0.]"
        renderer(l).handle(.toolFinished(ChatMessage(role: .tool, content: "x", toolCallID: "1", toolResult: info)))
        #expect(!l.text.contains("one") && l.text.contains("four") && l.text.contains("4 lines"))
        #expect(!l.text.contains("Exit code"))
    }

    @Test func aCommandsLiveOutputIsLeftToTheScreen() {
        let l = Lines()
        renderer(l).handle(.toolProgress(callID: "1", text: "output"))
        #expect(l.text.isEmpty)
    }
}

@Suite struct CLISessionCommandTests {
    private func session(_ route: MockServer.Route) async throws -> (CLISession, URL) {
        let support = FileManager.default.temporaryDirectory.appending(path: "kk-cli-\(UUID().uuidString.prefix(8))")
        let project = support.appending(path: "project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let mock = Endpoint(name: "Mock", kind: .openai, baseURL: URL(string: "http://mock.invalid/v1")!)
        try EndpointStore(fileURL: support.appending(path: "endpoints.json")).save([mock])
        let defaults = try #require(UserDefaults(suiteName: "kk-cli-\(UUID().uuidString)"))
        defaults.set(mock.id.uuidString, forKey: "defaultEndpointID")
        defaults.set("test-model", forKey: "defaultModel")
        let settings = AppSettings(support: support, defaults: defaults, environment: [:])
        var options = CLIOptions()
        options.mcp = false
        options.skillRouting = .off
        let (client, _) = MockServer.client(route)
        let s = try await CLISession(settings: settings, workspace: project, options: options, makeClient: { _, _ in client })
        return (s, support)
    }

    @Test func renameIsKept() async throws {
        let (s, _) = try await session(.init(chunks: SSE.content("hi")))
        _ = try await s.send("hello")
        try await s.rename("My chat")
        #expect(s.session.displayTitle == "My chat")
        #expect(try await s.sessions().first?.title == "My chat")
    }

    @Test func retryReplacesTheLastReply() async throws {
        let (s, _) = try await session(.init(chunks: [], turns: [SSE.content("first"), SSE.content("second")]))
        _ = try await s.send("hello")
        _ = try await s.retry()
        #expect(s.session.messages.map(\.content) == ["hello", "second"])
    }

    @Test func retryNeedsAReply() async throws {
        let (s, _) = try await session(.init(chunks: []))
        await #expect(throws: CLISession.Failure.self) { try await s.retry() }
    }

    @Test func resumeSwitchesSessions() async throws {
        let (s, _) = try await session(.init(chunks: SSE.content("hi")))
        _ = try await s.send("the first chat")
        let first = s.session.header.id
        s.clear()
        _ = try await s.send("the second chat")
        try await s.resume(first)
        #expect(s.session.header.id == first && s.session.messages.first?.content == "the first chat")
    }

    @Test func aStatusReportSaysWhereThingsStand() async throws {
        let (s, _) = try await session(.init(chunks: SSE.content("hi")))
        _ = try await s.send("hello")
        #expect(s.statusReport.contains("test-model") && s.statusReport.contains("hello"))
    }

    @Test func queuedTextGoesInAtTheNextStep() async throws {
        let call = SSE.toolCall("c1", "list_dir", #"{"path":"."}"#)
        let (s, _) = try await session(.init(chunks: [], turns: [call, SSE.content("done")]))
        final class Once: @unchecked Sendable {
            let lock = NSLock()
            var texts = ["also check the tests"]
        }
        let once = Once()
        s.takeQueued = { once.lock.withLock { defer { once.texts = [] }; return once.texts } }
        s.mode = .fullAuto
        _ = try await s.send("look around")
        let users = s.session.messages.filter { $0.role == .user }.map(\.content)
        #expect(users == ["look around", "also check the tests"])
    }
}

@Suite struct SetupCommandTests {
    private func settings() -> AppSettings {
        let support = FileManager.default.temporaryDirectory.appending(path: "kk-setup-\(UUID().uuidString.prefix(8))")
        return AppSettings(support: support, defaults: UserDefaults(suiteName: "kk-setup-\(UUID().uuidString)")!, environment: ["MY_KEY": "secret"])
    }

    private func run(_ args: [String], _ s: AppSettings, key: String? = nil,
                     saved: @escaping (String, UUID) throws -> Void = { _, _ in Issue.record("no key should be saved") }) async -> (Int32, String) {
        final class Out: @unchecked Sendable { var text = "" }
        let out = Out()
        let code = await SetupCommands.run(["endpoint"] + args, settings: s, readKey: { _ in key }, saveKey: saved) { out.text += $0 }
        return (code, out.text)
    }

    @Test func addsListsAndRemoves() async {
        let s = settings()
        let (added, _) = await run(["add", "lan", "http://192.168.1.2:1234/v1", "--no-key"], s)
        #expect(added == 0)
        let (_, listed) = await run(["list"], s)
        #expect(listed.contains("lan") && listed.contains("192.168.1.2"))
        #expect(await run(["add", "LAN", "http://x/v1", "--no-key"], s).0 == 1)     // names are unique
        #expect(await run(["remove", "lan"], s).0 == 0)
        #expect(await run(["remove", "lan"], s).0 == 1)
    }

    @Test func aKeyComesFromTheEnvironmentAndNeverTheArguments() async {
        let s = settings()
        final class Got: @unchecked Sendable { var key: String? }
        let got = Got()
        let (code, text) = await run(["add", "remote", "https://api.example.com/v1", "--key-env", "MY_KEY"], s) { key, _ in got.key = key }
        #expect(code == 0 && got.key == "secret" && !text.contains("secret"))
        #expect(await run(["add", "other", "https://api.example.com/v1", "--key-env", "UNSET"], s).0 == 1)
    }

    @Test func thisMacsServerCantBeRemoved() async {
        let s = settings()
        #expect(await run(["remove", Endpoint.localLMStudio.name], s).0 == 1)
    }

    @Test func aBadURLIsRefused() async {
        #expect(await run(["add", "x", "not a url", "--no-key"], settings()).0 == 2)
    }
}
