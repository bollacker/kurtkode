import Foundation
import Testing
@testable import AgentCore
@testable import KurtkodeCLI

/// Answers to give in order, and the prompts they were asked with.
private final class Script: @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [String?]
    private(set) var prompts: [String] = []
    init(_ answers: [String?]) { self.answers = answers }
    func read(_ prompt: String, _ card: String) -> String? {
        lock.withLock {
            prompts.append(prompt)
            return answers.isEmpty ? nil : answers.removeFirst()
        }
    }
}

private func decide(_ answers: [String?], rule: AllowRule? = nil, cancelled: Bool = false) async -> (ApprovalDecision, [String]) {
    let script = Script(answers)
    let d = await ApprovalPrompt.decide(card: "card", suggestedRule: rule, cancelled: { cancelled }) { script.read($0, $1) }
    return (d, script.prompts)
}

/// BUG_HUNT_2026-11-02 Part 1 item 1: an empty answer at a plain-mode approval card approved it.
@Suite struct BugHuntApprovalPromptTests {
    @Test func emptyAnswerAsksAgainInsteadOfAllowing() async {
        let (d, prompts) = await decide(["", "  ", "n"])
        #expect(d == .deny(feedback: nil))
        #expect(prompts == ["  › ", ApprovalPrompt.again, ApprovalPrompt.again])
        #expect(await decide(["", "y"]).0 == .allow)
    }

    @Test func endOfInputDenies() async {
        // `printf 'fix it\n\n' | kurtkode`: the blank line once approved the first command.
        #expect(await decide([""]).0 == .deny(feedback: nil))
        #expect(await decide([nil]).0 == .deny(feedback: nil))
    }

    @Test func cancelledReadDenies() async {
        // Ctrl-C ends the read with an empty line.
        let (d, prompts) = await decide([""], cancelled: true)
        #expect(d == .deny(feedback: nil))
        #expect(prompts.count == 1)
        #expect(await decide(["y"], cancelled: true).0 == .deny(feedback: nil))
    }

    @Test func wordsAndFeedback() async {
        let rule = AllowRule.command("swift test")
        #expect(await decide(["y"]).0 == .allow)
        #expect(await decide([" YES "]).0 == .allow)
        #expect(await decide(["n"]).0 == .deny(feedback: nil))
        #expect(await decide(["no"]).0 == .deny(feedback: nil))
        #expect(await decide(["a"], rule: rule).0 == .allowAlways(rule))
        #expect(await decide(["always"]).0 == .allow)
        #expect(await decide(["use the other folder "]).0 == .deny(feedback: "use the other folder"))
    }

    @Test func flushingIsOnlyForATerminal() throws {
        var fds: [Int32] = [0, 0]
        #expect(pipe(&fds) == 0)
        defer { close(fds[0]); close(fds[1]) }
        #expect(!ApprovalPrompt.flushTypedAhead(fd: fds[0]))
    }
}
