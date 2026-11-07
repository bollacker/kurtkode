import Foundation
import Testing
@testable import AgentCore

// BUG_HUNT_2026-11-02.md Part 1, items 2, 3, 4, 11 and 12: the permission and danger-check layer.

private func rules(_ allow: [String] = [], ask: [String] = [], deny: [String] = [], root: URL) -> PermissionRules {
    PermissionRules(rules: PermissionsSection(allow: allow, ask: ask, deny: deny).rules(source: "test", includeAllow: true), root: root)
}

private func bashAction(_ r: PermissionRules, _ command: String) -> PermissionRule.Action? {
    r.decision(toolName: "bash", args: ToolArguments(["command": .string(command)]))?.action
}

private final class Asked: @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [ApprovalRequest] = []
    func add(_ r: ApprovalRequest) { lock.withLock { _requests.append(r) } }
    var requests: [ApprovalRequest] { lock.withLock { _requests } }
}

@Suite struct BugHuntPermsTests {
    let roots = ["/Users/k/proj"]

    // MARK: Item 2: wrappers that stop unwrapping

    @Test func envDropsEveryAssignmentEvenWithANameNoShellAccepts() {
        #expect(ShellSplit.unwrap(["env", "A.B=1", "rm", "-rf", "~"]) == ["rm", "-rf", "~"])
        #expect(ShellSplit.unwrap(["env", "-i", "A-B=1", "X=2", "/bin/rm", "x"]) == ["rm", "x"])
        #expect(ShellSplit.unwrap(["env", "--", "a.b=1", "rm", "x"]) == ["rm", "x"])
        #expect(DangerousCommands.reason("env A.B=1 rm -rf ~", roots: roots) != nil)
        // An assignment before a command (not after env) must be a shell name; otherwise it's the command.
        #expect(ShellSplit.unwrap(["A.B=1", "rm"]) == ["A.B=1", "rm"])
    }

    @Test func timeoutsLongOptionsAndAnUnreadableDuration() {
        #expect(ShellSplit.unwrap(["timeout", "--signal", "KILL", "5", "rm", "-rf", "~"]) == ["rm", "-rf", "~"])
        #expect(ShellSplit.unwrap(["timeout", "--signal=KILL", "--kill-after", "2", "5s", "rm"]) == ["rm"])
        #expect(ShellSplit.unwrap(["timeout", "-s", "KILL", "-k", "1", "0.5", "rm"]) == ["rm"])
        #expect(ShellSplit.unwrap(["timeout", "-sKILL", "5", "rm"]) == ["rm"])
        #expect(ShellSplit.unwrap(["timeout", "--preserve-status", "1m", "rm"]) == ["rm"])
        #expect(DangerousCommands.reason("timeout --signal KILL 5 rm -rf ~", roots: roots) != nil)
        // Something that isn't a duration where one belongs: the line is asked about, not guessed at.
        #expect(ShellSplit.unreadableWrapper(["timeout", "--frobnicate", "KILL", "5", "rm"]) != nil)
        #expect(ShellSplit.unreadableWrapper(["timeout", "soon", "rm"]) != nil)
        #expect(DangerousCommands.reason("timeout --frobnicate KILL 5 git status", roots: roots) != nil)
    }

    @Test func otherWrappersLongOptions() {
        #expect(ShellSplit.unwrap(["nice", "--adjustment", "5", "rm", "x"]) == ["rm", "x"])
        #expect(ShellSplit.unwrap(["nice", "--adjustment=5", "rm", "x"]) == ["rm", "x"])
        #expect(ShellSplit.unwrap(["nice", "-5", "rm", "x"]) == ["rm", "x"])
        #expect(ShellSplit.unwrap(["xargs", "--max-args", "1", "rm"]) == ["rm"])
        #expect(ShellSplit.unwrap(["xargs", "-0", "-n1", "-I{}", "rm", "{}"]) == ["rm", "{}"])
        #expect(ShellSplit.unwrap(["xargs", "-J", "%", "rm", "%"]) == ["rm", "%"])
        #expect(ShellSplit.unwrap(["sudo", "--user", "root", "rm", "x"]) == ["rm", "x"])
        #expect(ShellSplit.unwrap(["sudo", "-iu", "root", "rm", "x"]) == ["rm", "x"])
        #expect(ShellSplit.unwrap(["stdbuf", "--output", "L", "rm", "x"]) == ["rm", "x"])
        #expect(ShellSplit.unwrap(["stdbuf", "-oL", "rm", "x"]) == ["rm", "x"])
        #expect(ShellSplit.unwrap(["time", "-o", "t.txt", "rm", "x"]) == ["rm", "x"])
        for line in ["xargs --max-args 1 rm -rf ~", "nice --adjustment 5 rm -rf ~", "stdbuf --output L rm -rf ~",
                     "sudo --user root git status", "env --chdir /x rm -rf ~"] {
            #expect(DangerousCommands.reason(line, roots: roots) != nil, "\(line)")
        }
        // An option kurtkode doesn't know, which may take the next word: asked, and a deny rule can't be skipped by it.
        for words in [["nice", "--frobnicate", "x", "rm"], ["xargs", "--frob", "rm"], ["sudo", "-Q", "rm"], ["env", "-Z", "rm"]] {
            #expect(ShellSplit.unreadableWrapper(words) != nil, "\(words)")
        }
        let r = rules(["Bash(git status:*)"], deny: ["Bash(rm:*)"], root: URL(fileURLWithPath: "/p"))
        #expect(bashAction(r, "nice --frobnicate 5 rm -rf x") == .deny || bashAction(r, "nice --frobnicate 5 rm -rf x") == .ask)
        #expect(bashAction(r, "timeout --signal KILL 5 rm x") == .deny)
        #expect(bashAction(r, "env A.B=1 rm x") == .deny)
        // Ordinary wrapped commands still read.
        for words in [["timeout", "60", "swift", "test"], ["env", "-i", "PATH=/bin", "make"], ["nohup", "make"], ["command", "-v", "git"],
                      ["xargs", "-r", "grep", "x"], ["caffeinate", "-i", "make"]] {
            #expect(ShellSplit.unreadableWrapper(words) == nil, "\(words)")
        }
    }

    // MARK: Item 3: one allow rule no longer exempts the whole line

    @Test func aRuleNamingADangerExemptsOnlyTheCommandsItMatches() {
        let r = rules(["Bash(git reset --hard:*)"], root: URL(fileURLWithPath: "/Users/k/proj"))
        func danger(_ c: String) -> String? {
            DangerousCommands.reason(c, roots: roots) { r.allowsDanger($0, reasons: $1, roots: roots) }
        }
        #expect(danger("git reset --hard") == nil)
        #expect(danger("git reset --hard HEAD~1 && echo done") == nil)
        #expect(danger("git reset --hard && rm -rf ~/Projects/other") == "deletes a folder outside the project (~/Projects/other)")
        #expect(danger("rm -rf ~/Projects/other; git reset --hard") != nil)
        #expect(danger("git reset --hard && git push --force") != nil)
        let both = rules(["Bash(git reset --hard:*)", "Bash(rm:*)"], root: URL(fileURLWithPath: "/Users/k/proj"))
        #expect(DangerousCommands.reason("git reset --hard && rm -rf ~/Projects/other", roots: roots) {
            both.allowsDanger($0, reasons: $1, roots: roots) } == "deletes a folder outside the project (~/Projects/other)")
        // A broad rule names no danger.
        let broad = rules(["Bash(git:*)"], root: URL(fileURLWithPath: "/Users/k/proj"))
        #expect(DangerousCommands.reason("git reset --hard", roots: roots) { broad.allowsDanger($0, reasons: $1, roots: roots) } != nil)
        // A rule naming one deletion doesn't cover another on the same command.
        let one = rules(["Bash(rm -rf /Users/k/other:*)"], root: URL(fileURLWithPath: "/Users/k/proj"))
        func oneDanger(_ c: String) -> String? { DangerousCommands.reason(c, roots: roots) { one.allowsDanger($0, reasons: $1, roots: roots) } }
        #expect(oneDanger("rm -rf /Users/k/other") == nil)
        #expect(oneDanger("rm -rf /Users/k/other ~") != nil)
    }

    @Test func inTheLoopTheRestOfTheLineIsStillAsked() async throws {
        let ws = try makeProject(git: true)
        let line = "git reset --hard && rm -rf /nonexistent-kk-bughunt/other"
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("a", "bash", "{\"command\":\"\(line)\"}"), SSE.content("ok")]))
        let asked = Asked()
        var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .fullAuto),
                                 approve: { r in asked.add(r); return .deny(feedback: "no") })
        // With both commands allowed, the first one's rule used to stand for the whole line and skip the danger check.
        config.permissionRules = rules(["Bash(git reset --hard:*)", "Bash(rm:*)"], root: ws.root)
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("go")], config: config, workspace: ws) { _ in }
        #expect(asked.requests.count == 1)
        #expect(asked.requests.first?.reason == "this command deletes a folder outside the project (/nonexistent-kk-bughunt/other)")

        // The rule's own command alone still runs unasked.
        let (c2, _) = MockServer.client(.init(turns: [SSE.toolCall("b", "bash", #"{"command":"git reset --hard"}"#), SSE.content("ok")]))
        let asked2 = Asked()
        var config2 = config
        config2.approve = { r in asked2.add(r); return .deny(feedback: "no") }
        await AgentLoop.run(client: c2, model: "m", systemPrompt: "S", history: [.user("go")], config: config2, workspace: ws) { _ in }
        #expect(asked2.requests.isEmpty)
    }

    // MARK: Item 4: variable and relative targets

    @Test func recursiveDeletesOfComputedOrRelocatedTargets() {
        for c in [#"rm -rf "$BUILD_DIR/""#, #"rm -rf "${HOME}/Library""#, "rm -rf ${HOME}/", "rm -rf $(pwd)/x", "rm -rf `pwd`",
                  "rm -rf $DIR", "cd ~ && rm -rf Documents", "cd /Users/k/other; rm -rf src", "cd .. && rm -rf proj",
                  "cd $X && rm -rf build", "cd && rm -r Documents", "pushd ~/x; rm -rf y", "rm -rf ./..", "rm -rf build/../..",
                  "rm -rf a/.."] {
            #expect(DangerousCommands.reason(c, roots: roots) != nil, "\(c)")
        }
        #expect(DangerousCommands.reason(#"rm -rf "$BUILD_DIR/""#, roots: roots) == "deletes a path computed when it runs ($BUILD_DIR/)")
        #expect(DangerousCommands.reason("cd ~ && rm -rf Documents", roots: roots)
                == "deletes a folder outside the project (Documents, after cd ~)")
        for c in ["rm -rf build", "rm -rf ./dist", "cd sub && rm -rf build", "cd /Users/k/proj/sub && rm -rf build",
                  "cd /tmp && rm -rf x", "cd ~ && cd /Users/k/proj && rm -rf build", "rm $FILE", "rm -rf build/../dist",
                  "rm -rf $HOME/../k/proj/build".replacingOccurrences(of: "$HOME/../k", with: "/Users/k")] {
            #expect(DangerousCommands.reason(c, roots: roots) == nil, "\(c)")
        }
    }

    // MARK: Item 11: a subagent's approval says why it asks

    @Test func aSubagentsApprovalKeepsItsReason() async throws {
        let ws = try makeProject(git: true)
        let generalTask = #"{"description":"Reset","prompt":"Reset the repo.","agent":"general"}"#
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "task", generalTask),                                     // main agent
            SSE.toolCall("call_s1", "bash", #"{"command":"git reset --hard"}"#),             // subagent: asked
            SSE.content("Couldn't."),                                                         // subagent
            SSE.content("Done."),                                                             // main agent
        ]))
        let asked = Asked()
        var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .fullAuto),
                                 approve: { r in asked.add(r); return .deny(feedback: nil) })
        config.subagents = SubagentSetup()
        await AgentLoop.run(client: client, model: "m", systemPrompt: nil, history: [.user("Go")], config: config, workspace: ws) { _ in }
        let r = try #require(asked.requests.first)
        #expect(r.summary.hasPrefix("[general subagent]"))
        #expect(r.reason == "this command discards uncommitted changes (git reset --hard)")
    }

    // MARK: Item 12: "Always allow" offers no more than the command seen

    @Test func suggestedRulesStayNarrow() {
        let bash = BashTool()
        func rule(_ c: String) -> AllowRule? { PermissionPolicy.suggestedRule(bash, ToolArguments(["command": .string(c)])) }
        #expect(rule("git status") == .command("git status"))
        #expect(rule("git -C sub status") == .command("git -C sub status"))
        #expect(rule("git -c core.pager=cat log") == .command("git -c core.pager=cat log"))
        #expect(rule("git --git-dir=x status") == .command("git --git-dir=x status"))
        #expect(rule("git --no-pager log") == .command("git --no-pager log"))                // unknown option: this line only
        #expect(rule("npm --prefix x test") == .command("npm --prefix x test"))
        #expect(rule("timeout 60 swift test") == .command("timeout 60 swift test"))
        #expect(rule("env FOO=1 make") == .command("env FOO=1 make"))
        #expect(rule("FOO=1 make test") == .command("FOO=1 make test"))
        #expect(rule("bash script.sh") == .command("bash script.sh"))
        #expect(rule("python3 x.py") == .command("python3 x.py"))
        #expect(rule("python3 -m pytest -q") == .command("python3 -m pytest"))
        #expect(rule("python3 -c print(1)") == nil)
        #expect(rule("node -e x") == nil)
        #expect(rule("bash") == nil)
        #expect(rule("npx some-tool --fix") == .command("npx some-tool --fix"))
        #expect(rule("ls -la") == .command("ls"))
        // And the rule offered allows the command it was offered for.
        for c in ["git -C sub status", "npm --prefix x test", "timeout 60 swift test", "bash script.sh"] {
            guard let prefix = rule(c)?.value else { Issue.record("\(c)"); continue }
            #expect(PermissionPolicy.commandMatches(c, prefix: prefix), "\(c)")
            #expect(!PermissionPolicy.commandMatches("git push", prefix: prefix))
        }
    }
}
