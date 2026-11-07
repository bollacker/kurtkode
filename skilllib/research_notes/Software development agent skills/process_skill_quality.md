# Quality of the best-known software-development PROCESS skills (as of 2026-10-25)

Scope: process (P) items from TAXONOMY_v0 (items 1, 6, 7, 11, 12, 13, 14, 28, 29, 30, 31, 32, 38, 50-52, 75, 76). Full SKILL.md text was read over the web (raw.githubusercontent.com and the GitHub API) on 2026-10-25. Nothing was cloned. Quotes are kept under 15 words; everything else is summarized.

Source repos and their popularity (GitHub stars and last push, from the GitHub API on 2026-10-25):
- obra/superpowers: 304,727 stars, pushed 2026-10-23. Current release is v7.0.1 (2026-10-21). — [GitHub API](https://api.github.com/repos/obra/superpowers); [commits](https://github.com/obra/superpowers/commits/main)
- affaan-m/ECC ("everything-claude-code"): 288,271 stars, pushed 2026-10-20 — [GitHub API](https://api.github.com/repos/affaan-m/ECC)
- anthropics/skills: 183,570 stars — [GitHub API](https://api.github.com/repos/anthropics/skills)
- anthropics/claude-code (plugins folder): 153,320 stars — [GitHub API](https://api.github.com/repos/anthropics/claude-code)
- wshobson/agents: 41,656 stars — [GitHub API](https://api.github.com/repos/wshobson/agents)
- trailofbits/skills: 7,791 stars, pushed 2026-10-24 — [GitHub API](https://api.github.com/repos/trailofbits/skills)
- anthropics/claude-code-security-review: 6,536 stars, last pushed 2026-02-11 — [GitHub API](https://api.github.com/repos/anthropics/claude-code-security-review)

Structural note: in superpowers v7, `root-cause-tracing` is no longer a separate skill. It is now `root-cause-tracing.md`, a supporting file inside `systematic-debugging/`, next to `defense-in-depth.md`, `condition-based-waiting.md` and `find-polluter.sh` — [superpowers tree](https://github.com/obra/superpowers/tree/main/skills/systematic-debugging)

---

## What concrete guidance does each skill give? (by taxonomy item)

### Takeaway
Two house styles dominate. **Superpowers** writes short, enforcement-heavy discipline skills: an "Iron Law", a phase gate, a rationalization table and a red-flags list. It covers debugging, TDD, verification, receiving review and the plan/execute pipeline far better than anything else. **Anthropic's plugins and Trail of Bits** write procedure-heavy multi-agent workflows with confidence thresholds and false-positive filters, and they are strongest for performing code review and security review. **wshobson and ECC** skills are mostly generic tutorial or checklist content (stack-specific and not agent-specific), with weak enforcement. Refactoring and codebase orientation have no strong canonical skill.

### Cited Findings

#### Items 31/32: Systematic debugging and root-cause tracing

**superpowers `systematic-debugging`** (9.5 KB SKILL.md plus 3 technique files, 1 script, 4 pressure-test scenarios and a CREATION-LOG) — [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/systematic-debugging/SKILL.md); [tree](https://github.com/obra/superpowers/tree/main/skills/systematic-debugging)
- Description is trigger-only: "Use when encountering any bug, test failure, or unexpected behavior, before proposing fixes" — [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/systematic-debugging/SKILL.md)
- Iron Law: "NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST" — [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/systematic-debugging/SKILL.md)
- Four mandatory phases, each a numbered checklist:
  - Phase 1, root-cause investigation: read errors completely, reproduce, check recent changes, instrument every component boundary in multi-layer systems (with a worked CI/keychain/codesign bash example), and trace data flow backward.
  - Phase 2, pattern analysis: find a working example and list every difference.
  - Phase 3, hypothesis: state one hypothesis and test it with the smallest change.
  - Phase 4, implementation: write a failing test first, make a single fix, verify.
  - [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/systematic-debugging/SKILL.md)
- Distinctive rule: after three failed fixes, stop and question the architecture with the human. The skill frames this as "NOT a failed hypothesis - this is a wrong architecture" — [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/systematic-debugging/SKILL.md)
- Other enforcement elements:
  - a red-flags list of thoughts such as "Just try changing X and see if it works"
  - a list of human-partner phrases that signal the agent is off track ("Stop guessing", "Is that not happening?")
  - an 8-row rationalization table
  - a quick-reference table
  - a "no root cause" exit path, with the claim that 95% of such cases are incomplete investigation
  - [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/systematic-debugging/SKILL.md)
- `root-cause-tracing.md` covers:
  - a 5-step backward trace (symptom, immediate cause, caller chain, bad value, original trigger)
  - instrumenting with `new Error().stack` and `console.error` in tests
  - a bisection script (`find-polluter.sh`) that finds which test pollutes shared state
  - one real worked example (an empty `projectDir` that caused `git init` to run in the source tree)
  - adding defense-in-depth layers after the source fix
  - [root-cause-tracing.md](https://github.com/obra/superpowers/blob/main/skills/systematic-debugging/root-cause-tracing.md)
- Weaknesses I observed:
  - The examples are TypeScript- and Node-centric.
  - There is nothing on debuggers, bisecting by commit (`git bisect`), logs or core dumps, or concurrency and flaky-timing bugs beyond a pointer to condition-based-waiting.
  - "Ask for help" and "discuss with your human partner" give no guidance for autonomous runs where no human is present.
  - The phase gate is absolute, with no proportionality for trivial typos.
  - [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/systematic-debugging/SKILL.md)

**wshobson `debugging-strategies`** (6.2 KB plus a 6.3 KB tools reference) — [wshobson SKILL.md](https://github.com/wshobson/agents/blob/main/plugins/developer-essentials/skills/debugging-strategies/SKILL.md)
- A human-developer tutorial:
  - the scientific method (observe, hypothesize, experiment, analyze, repeat)
  - "rubber duck debugging" and "take breaks"
  - four phases (reproduce, gather information, hypothesize, test and verify)
  - patterns for intermittent, performance and production bugs
  - a "when stuck" checklist covering typos, case sensitivity, off-by-one and similar slips
  - [wshobson SKILL.md](https://github.com/wshobson/agents/blob/main/plugins/developer-essentials/skills/debugging-strategies/SKILL.md)
- It has no gate, no stop rule, no rationalization table and no fix-attempt limit. The description reads like marketing ("Master systematic debugging techniques…") rather than a trigger condition. Some advice is human-only ("Take breaks when stuck"). — [wshobson SKILL.md](https://github.com/wshobson/agents/blob/main/plugins/developer-essentials/skills/debugging-strategies/SKILL.md)

**Trail of Bits `patching-bugs`** (7.2 KB orchestrator plus sub-skills reproduce-bug, validate-bug, implement-patch and prove-patch) — [SKILL.md](https://github.com/trailofbits/skills/blob/main/plugins/patching-bugs/skills/patching-bugs/SKILL.md)
- A heavyweight pipeline for one known bug:
  - pin the baseline SHA
  - normalize the report into a `finding.json` with a falsifiable claim and an invariant
  - a fresh agent reproduces the bug, then a *different* fresh agent validates it, receiving only the artifacts and not the transcript
  - up to 3 patch attempts, each proven by yet another fresh agent
  - a regression-hunt over `baseline..patch_commit`
  - JSON-schema-validated records checked by a bundled script, and HTML reports
  - [SKILL.md](https://github.com/trailofbits/skills/blob/main/plugins/patching-bugs/skills/patching-bugs/SKILL.md)
- Key rule: "never infer a passing check from an agent's summary" — [SKILL.md](https://github.com/trailofbits/skills/blob/main/plugins/patching-bugs/skills/patching-bugs/SKILL.md)
- This is the most rigorous design for independent verification of a fix, but it is far too heavy for everyday debugging. It also requires `uv` and the regression-hunt plugin. — [SKILL.md](https://github.com/trailofbits/skills/blob/main/plugins/patching-bugs/skills/patching-bugs/SKILL.md)

#### Item 13: Test-driven development

**superpowers `test-driven-development`** (9.6 KB plus `writing-good-tests.md` at 8.3 KB) — [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/test-driven-development/SKILL.md)
- Iron Law: "NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST". Code written before its test must be deleted, with no keeping it "as reference" — [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/test-driven-development/SKILL.md)
- Red-green-refactor:
  - shown as a graphviz flowchart
  - "Verify RED" and "Verify GREEN" are marked MANDATORY: the test must fail for the expected reason, not from a typo
  - paired Good/Bad TypeScript examples (a real-behavior test versus a mock-only test; minimal code versus a YAGNI-violating version)
  - [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/test-driven-development/SKILL.md)
- The v7 text adds that "other tests" means the project's whole suite, and that any red test seen must be reported by name — [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/test-driven-development/SKILL.md)
- The skill also includes:
  - an 11-row rationalization table (for example, "I'll test after", "Deleting X hours is wasteful")
  - a 13-item red-flags list
  - a bug-fix example
  - an 8-item verification checklist
  - a "When Stuck" table (hard to test means the design is too coupled)
  - [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/test-driven-development/SKILL.md)
- Weaknesses I observed:
  - It is dogmatic. The only exceptions are prototypes, generated code and config, and the human must approve them.
  - There is no guidance for legacy code without a test harness, UI or visual work, exploratory spikes beyond "throw away", or languages where test-first is awkward.
  - Examples are TypeScript only.
  - There is no notion of characterization tests for existing behavior.
  - [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/test-driven-development/SKILL.md)

**ECC `tdd-workflow`** (21.6 KB) — [SKILL.md](https://github.com/affaan-m/ECC/blob/main/skills/tdd-workflow/SKILL.md)
- Features:
  - test-first, with an 80%+ coverage requirement across unit, integration and E2E tests (Playwright)
  - git checkpoint commits after RED and after GREEN as evidence
  - a test-runner detection step and command matrix for npm, pnpm, yarn and bun
  - a "Plan Handoff" section that treats `*.plan.md` files as untrusted input, with a prompt-injection safety checklist
  - [SKILL.md](https://github.com/affaan-m/ECC/blob/main/skills/tdd-workflow/SKILL.md)
- It is JS-ecosystem-centric and long. The coverage percentage target invites coverage padding. Its enforcement is weaker than superpowers (no rationalization table in the portion read). Its strength is checkpoint-commit evidence of RED then GREEN. — [SKILL.md](https://github.com/affaan-m/ECC/blob/main/skills/tdd-workflow/SKILL.md)

#### Item 28: Code review, performing it

**Anthropic `code-review` plugin command** (7.3 KB) — [code-review.md](https://github.com/anthropics/claude-code/blob/main/plugins/code-review/commands/code-review.md)
- A multi-agent pipeline:
  - a haiku gate agent skips closed, draft, trivial or already-reviewed PRs
  - a haiku agent collects the relevant CLAUDE.md paths
  - a sonnet agent summarizes the PR
  - 4 parallel reviewers: 2 sonnet agents for CLAUDE.md compliance and 2 opus agents for bugs in the diff
  - every flagged bug is then re-checked by a separate validation subagent, and unvalidated issues are dropped
  - [code-review.md](https://github.com/anthropics/claude-code/blob/main/plugins/code-review/commands/code-review.md)
- High-signal bar: flag only code that fails to compile, logic that is wrong regardless of input, or a CLAUDE.md violation where the rule can be quoted. It has an explicit false-positive list (pre-existing issues, linter-catchable issues, nitpicks, issues silenced in code). Key line: "False positives erode trust and waste reviewer time" — [code-review.md](https://github.com/anthropics/claude-code/blob/main/plugins/code-review/commands/code-review.md)
- Optional `--comment` posts inline GitHub comments, with suggestion blocks only when committing the suggestion fully fixes the issue. It also gives precise permalink formatting rules (full SHA, line ranges) — [code-review.md](https://github.com/anthropics/claude-code/blob/main/plugins/code-review/commands/code-review.md)
- Drift: the plugin README still describes the older design ("Agent #4: Analyze git blame/history" and 0-100 confidence scoring with an 80 threshold). The current command uses validation subagents instead. Docs and behavior are out of sync. — [README](https://github.com/anthropics/claude-code/blob/main/plugins/code-review/README.md) vs [code-review.md](https://github.com/anthropics/claude-code/blob/main/plugins/code-review/commands/code-review.md)
- Gaps:
  - It deliberately excludes design, test coverage and general security unless CLAUDE.md requires them.
  - It depends on GitHub and `gh`.
  - It is a slash command, not a portable SKILL.md.
  - [code-review.md](https://github.com/anthropics/claude-code/blob/main/plugins/code-review/commands/code-review.md)

**Anthropic `feature-dev` / `pr-review-toolkit` code-reviewer agents** (about 3-4 KB each) — [feature-dev code-reviewer](https://github.com/anthropics/claude-code/blob/main/plugins/feature-dev/agents/code-reviewer.md); [pr-review-toolkit code-reviewer](https://github.com/anthropics/claude-code/blob/main/plugins/pr-review-toolkit/agents/code-reviewer.md)
- Each reviews `git diff` against CLAUDE.md rules, bugs and quality. Each defines a 0-100 confidence rubric, reports "Only … issues with confidence ≥ 80", and groups findings as Critical or Important with file:line and a concrete fix — [feature-dev code-reviewer](https://github.com/anthropics/claude-code/blob/main/plugins/feature-dev/agents/code-reviewer.md)
- pr-review-toolkit adds specialist agents: silent-failure-hunter, pr-test-analyzer, type-design-analyzer, comment-analyzer and code-simplifier — [plugin tree](https://github.com/anthropics/claude-code/tree/main/plugins/pr-review-toolkit)

**superpowers `requesting-code-review`** (3.0 KB plus a 6.4 KB `code-reviewer.md` prompt template) — [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/requesting-code-review/SKILL.md); [code-reviewer.md](https://github.com/obra/superpowers/blob/main/skills/requesting-code-review/code-reviewer.md)
- How it works:
  - dispatch a fresh reviewer subagent with a crafted context (description, plan or requirements, BASE and HEAD SHAs), never the session history
  - fix Critical immediately, fix Important before proceeding, note Minor
  - [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/requesting-code-review/SKILL.md)
- Reviewer template:
  - checks plan alignment, code quality, architecture, testing and production readiness
  - review is read-only, with no subagent spawning
  - spec silence is not permission: judge behavior the spec doesn't cover by "what a reasonable person… would expect"
  - a "Declined to judge" list so nothing is dropped silently
  - output: Strengths, Critical/Important/Minor with file:line, and a merge verdict
  - [code-reviewer.md](https://github.com/obra/superpowers/blob/main/skills/requesting-code-review/code-reviewer.md)
- Weakness: no false-positive validation step and no confidence threshold. Its severity grading is advisory, and executing-plans tells the controller to re-grade. — [executing-plans](https://github.com/obra/superpowers/blob/main/skills/executing-plans/SKILL.md)

**wshobson `code-review-excellence`** (6.8 KB) is a human-team review guide:
- review goals, kind feedback examples, a "modified sandwich" method
- time budgets ("2-3 minutes" for context)
- "Limit PR Size: 200-400 lines", "Review Promptly: Within 24 hours"
- emoji verdict templates
- little that changes agent behavior, with no false-positive control or evidence requirement
- [SKILL.md](https://github.com/wshobson/agents/blob/main/plugins/developer-essentials/skills/code-review-excellence/SKILL.md)

#### Item 29: Receiving review feedback

**superpowers `receiving-code-review`** (6.2 KB) — [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/receiving-code-review/SKILL.md)
- Response pattern: READ, UNDERSTAND (restate), VERIFY against the codebase, EVALUATE, RESPOND, IMPLEMENT one item at a time with a test for each.
- Forbids performative agreement ("You're absolutely right!", "Great point!") and all gratitude expressions. Correct feedback gets "Fixed. [description]".
- If any item is unclear, stop and ask about all unclear items before implementing any.
- External-reviewer checklist: is it correct for this codebase, does it break things, is there a reason for the current implementation, does it work across platforms, does the reviewer have the context?
- YAGNI check: grep for actual usage before "implementing properly".
- When to push back, and how to correct your own wrong pushback.
- GitHub inline-thread replies via `gh api …/replies`.
- [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/receiving-code-review/SKILL.md)
- This is the only prominent skill found for item 29. Gaps: no workflow for batching many PR comments (tracking resolution, re-requesting review, marking threads resolved), and no handling of automated bot reviewers. Its blanket ban on "thanks" is a stylistic choice some teams will reject. — [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/receiving-code-review/SKILL.md)

#### Items 6, 7, 11, 12: Planning and plan execution

**superpowers `brainstorming`** (13.6 KB, rebuilt in v7.0.0 and retuned in v7.0.1; ships a visual-companion browser server and a builder-check prompt) — [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/brainstorming/SKILL.md); [commits](https://github.com/obra/superpowers/commits/main)
- Opening idea: the agent's belief about what the user wants "is usually thinner than it feels".
- Explore the code and context before asking anything, and never ask what the context already answers.
- First message: about 200 words that echo the request, report findings, and end with one question. If the user didn't ask for brainstorming, offer to "just dive in".
- One question per message, open questions before menus, and play back about 200-300 words per part.
- Lay out 2-3 approaches with trade-offs and a recommendation, in their own message.
- Size the work as a short or full design doc. A full doc goes to a fresh "builder check" subagent, whose questions are sorted into three piles (answered already, minor, theirs).
- A `<HARD-GATE>` blocks any building until the design doc is approved. Spikes are allowed as labeled throwaway work.
- [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/brainstorming/SKILL.md)
- Weakness: very conversational, with many human turns. It is a poor fit for autonomous or batch agents, and its description ("You MUST use this before any creative work") over-triggers by design. — [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/brainstorming/SKILL.md)

**superpowers `writing-plans`** (10.3 KB) — [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/writing-plans/SKILL.md)
- Audience: an engineer who knows the language but not the codebase or the decisions made.
- Plan structure:
  - a mandatory header (Goal, Architecture, Tech Stack, Spec path)
  - "Global Constraints" with exact values copied from the spec
  - "Review Focus": the five input classes or failure modes the spec implies but no test exercises, each then pinned to a test
- Tasks and steps:
  - a file-structure map
  - tasks sized as the smallest unit worth a reviewer gate
  - per-task Files and Interfaces blocks (what it consumes and produces, with exact signatures)
  - checkbox steps, each with a run command and an `Expected:` result
- Explicit principle: "A plan longer than the code it describes has written the code instead".
- Five-point self-review: spec coverage, step scan, type consistency, Review Focus, proportion.
- Handoff offers subagent-driven or native (inline) execution, with a recommendation.
- [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/writing-plans/SKILL.md)

**superpowers `executing-plans`** (18.1 KB plus `task-start` and `task-done` scripts) — [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/executing-plans/SKILL.md)
- Inline execution with no check-ins between tasks. Plan conflicts are decided as ledgered rulings ("Ruling: what — why — cost if wrong").
- Only four things stop the agent: irreversible or destructive actions, security-sensitive actions, external side effects like push or publish, and a hopelessly broken plan.
- A ledger file (`.superpowers/sdd/<plan>/progress.md`) survives context compaction.
- A pre-flight interface-conflict scan.
- A per-task "completion contract" with evidence; the `task-done` script runs the tests and appends the ledger line only on a pass.
- One final whole-branch review on the most capable model, then a single TDD-verified fix pass for Critical and Important findings. Minors are deferred and listed.
- The final message must list every ruling and every deferred minor.
- [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/executing-plans/SKILL.md)
- `subagent-driven-development` (19.5 KB) is the per-task subagent alternative: a fresh implementer plus a reviewer per task, model selection, a fix loop and a final review — [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/subagent-driven-development/SKILL.md)
- Weakness: tightly coupled to superpowers' own pipeline, directory conventions and scripts (`../subagent-driven-development/scripts/…`). It is hard to adopt piecemeal. — [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/executing-plans/SKILL.md)

**Anthropic `feature-dev` command** (5.1 KB plus code-explorer, code-architect and code-reviewer agents) — [feature-dev.md](https://github.com/anthropics/claude-code/blob/main/plugins/feature-dev/commands/feature-dev.md)
- Seven phases:
  1. Discovery.
  2. Codebase exploration with 2-3 parallel code-explorer agents, each returning 5-10 key files, which the main agent then reads.
  3. Clarifying questions (marked "CRITICAL… DO NOT SKIP"), presented as one organized list.
  4. Architecture: 2-3 code-architect agents (minimal, clean, pragmatic) and a recommendation.
  5. Implementation, only after explicit approval.
  6. Quality review by 3 parallel reviewers.
  7. Summary.
  - [feature-dev.md](https://github.com/anthropics/claude-code/blob/main/plugins/feature-dev/commands/feature-dev.md)
- Simpler and more portable than superpowers, but it has:
  - no written plan artifact
  - no TDD or verification gate (Implementation says only "Write clean, well-documented code")
  - no rationalization defenses
  - questions asked as one batched list, the opposite of superpowers' one-at-a-time approach
  - [feature-dev.md](https://github.com/anthropics/claude-code/blob/main/plugins/feature-dev/commands/feature-dev.md)

#### Item 30: Verification before claiming completion

**superpowers `verification-before-completion`** (3.6 KB) — [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/verification-before-completion/SKILL.md)
- Iron Law: "NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE".
- Five-step Gate Function: IDENTIFY the command that proves the claim, RUN it fresh, READ the output and exit code, VERIFY, then claim.
- A claim-to-evidence table:
  - "tests pass" needs fresh output with 0 failures
  - "bug fixed" needs the original symptom re-tested
  - "regression test works" needs red-green verified
  - "agent completed" needs a VCS diff check
  - "requirements met" needs a line-by-line checklist
- Red flags include "should", "probably", and premature "Great!" or "Done!". The regression-test pattern is revert the fix, confirm the test fails, restore.
- [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/verification-before-completion/SKILL.md)
- Short, high density, and language-neutral. Gaps: no guidance on what counts as verification for UI or visual work, for deployed services, or for tasks where no test exists.

**ECC `verification-loop`** (3.1 KB) is a six-phase quality-gate script (build, types, lint, tests with an 80% coverage target, a secrets and `console.log` grep, a diff review) that ends in a PASS/FAIL report. It is a useful tool-style checklist, but JS/Python-specific, and its "security scan" is two greps. — [SKILL.md](https://github.com/affaan-m/ECC/blob/main/skills/verification-loop/SKILL.md)

#### Item 14: Refactoring safely

- I found no prominent canonical "refactor safely" process skill in superpowers, anthropics/skills or the claude-code plugins. Superpowers covers refactoring only through TDD's REFACTOR step ("Keep tests green. Don't add behavior."). — [TDD SKILL.md](https://github.com/obra/superpowers/blob/main/skills/test-driven-development/SKILL.md); [superpowers tree](https://api.github.com/repos/obra/superpowers/git/trees/main?recursive=1)
- **wshobson `refactor-clean`** (a 23 KB command):
  - opens with smell detection (thresholds such as "Long methods/functions (>20 lines)") and SOLID violations
  - prioritized refactoring plan
  - pattern application (Factory, Strategy)
  - it is analysis- and design-oriented, with no behavior-preservation gate in the portion read (first 90 lines)
  - [refactor-clean.md](https://github.com/wshobson/agents/blob/main/plugins/code-refactoring/commands/refactor-clean.md)
- **igmarin `refactor-code`** (a Rails skill with 28 stars, so not prominent, but the cleanest process content found):
  - HARD-GATE: "NO REFACTORING WITHOUT CHARACTERIZATION TESTS FIRST"
  - never mix behavior and structural changes in one step
  - one boundary per step
  - document compatibility shims and when they get removed
  - run the full suite after every step
  - "Observed output" labeling, with a ban on presenting expected output as observed
  - it ships a personal-evals fixture
  - [SKILL.md](https://github.com/igmarin/rails-agent-skills/blob/main/skills/refactor-code/SKILL.md); [repo tree](https://api.github.com/repos/igmarin/rails-agent-skills/git/trees/main?recursive=1)

#### Items 50, 51, 52, 75: Git workflow (commits, PRs, worktrees, conflicts)

**superpowers `using-git-worktrees`** (6.8 KB) — [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/using-git-worktrees/SKILL.md)
- Step 0: detect existing isolation by comparing `git rev-parse --git-dir` with `--git-common-dir`, with a submodule guard.
- Ask before creating a worktree.
- Prefer a native harness tool (such as `EnterWorktree`) over `git worktree add`, to avoid "phantom state".
- Verify `.worktrees/` is gitignored.
- Run project setup and baseline tests, with a sandbox fallback.
- [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/using-git-worktrees/SKILL.md)

**superpowers `finishing-a-development-branch`** (7.8 KB) — [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/finishing-a-development-branch/SKILL.md)
- Run the full suite first.
- Detect a normal repo versus a worktree versus detached HEAD.
- Confirm the base branch.
- Present exactly 3 options: merge locally, push and open a PR, or keep as-is.
- Discarding work requires the user to type `discard`.
- Never `--force` a worktree removal. Rejected pushes are investigated, never force-pushed.
- [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/finishing-a-development-branch/SKILL.md)
- Superpowers has no commit-message, PR-description or merge-conflict skill. — [superpowers tree](https://api.github.com/repos/obra/superpowers/git/trees/main?recursive=1)

**Anthropic `commit-commands`** (`/commit` is 0.6 KB, `/commit-push-pr` is 0.8 KB):
- inject `git status`, `git diff HEAD`, branch and recent log through `!` shell expansion
- then "create a single git commit" in one message with no other text
- they carry no guidance on atomicity, message quality or splitting commits
- [commit.md](https://github.com/anthropics/claude-code/blob/main/plugins/commit-commands/commands/commit.md); [commit-push-pr.md](https://github.com/anthropics/claude-code/blob/main/plugins/commit-commands/commands/commit-push-pr.md)

**wshobson `git-advanced-workflows`** (5.6 KB) and **ECC `git-workflow`** (15.3 KB) are human-oriented git references:
- interactive rebase, cherry-pick, bisect (including `git bisect run`), worktrees, reflog recovery, `--force-with-lease`
- branching strategies (GitHub Flow, trunk-based, GitFlow), Conventional Commits, conflict resolution
- wshobson recommends `git rebase -i`, which agents cannot run interactively in many harnesses
- neither has agent-specific safety gates such as asking before force-push
- [wshobson SKILL.md](https://github.com/wshobson/agents/blob/main/plugins/developer-essentials/skills/git-advanced-workflows/SKILL.md); [ECC SKILL.md](https://github.com/affaan-m/ECC/blob/main/skills/git-workflow/SKILL.md)

#### Item 1: Codebase orientation / exploration

**ECC `codebase-onboarding`** (8.2 KB) — [SKILL.md](https://github.com/affaan-m/ECC/blob/main/skills/codebase-onboarding/SKILL.md)
- Four phases: reconnaissance (manifests, framework fingerprints, entry points, top-2-level tree, tooling, test layout), architecture mapping (including tracing one request end to end), convention detection (naming, error style, git conventions), and artifact generation (an onboarding guide plus a starter CLAUDE.md under 100 lines).
- Good rules: "Don't read everything", "Verify, don't guess", "Flag unknowns".
- Its output is aimed at a human onboarding doc rather than the agent's own working context.
- [SKILL.md](https://github.com/affaan-m/ECC/blob/main/skills/codebase-onboarding/SKILL.md)

**Anthropic `feature-dev` code-explorer agent** (2.1 KB) traces a feature from entry points through call chains, architecture layers and implementation details. It returns file:line references and a list of essential files. — [code-explorer.md](https://github.com/anthropics/claude-code/blob/main/plugins/feature-dev/agents/code-explorer.md)

**Trail of Bits `audit-context-building`** (4.0 KB) — [SKILL.md](https://github.com/trailofbits/skills/blob/main/plugins/audit-context-building/skills/audit-context-building/SKILL.md)
- Builds per-function records of invariants, assumptions (with what establishes them, or `nothing found`), callees and open questions.
- Dispatched to subagents with a return schema, so prose cannot flood the main context.
- Rule: "follow the calls", and every claim cites a line or becomes an open question.
- Built for security audits, but the best-designed exploration method found.
- [SKILL.md](https://github.com/trailofbits/skills/blob/main/plugins/audit-context-building/skills/audit-context-building/SKILL.md)

#### Item 38: Security review

**Anthropic `security-review`** (10.8 KB; the same `/security-review` command shipped in Claude Code) — [security-review.md](https://github.com/anthropics/claude-code-security-review/blob/main/.claude/commands/security-review.md)
- Injects the branch diff against `origin/HEAD`.
- Objective: only HIGH-CONFIDENCE vulnerabilities newly introduced by the change.
- Categories: input validation and injection, authn/authz, crypto and secrets, deserialization and RCE, XSS, data exposure.
- Three phases: repo security context, comparison against existing patterns, data-flow assessment.
- Required per-finding format: file:line, severity, category, exploit scenario, fix.
- A long false-positive filter: 17+ hard exclusions (DoS, rate limiting, test files, regex DoS, and others) and 12 "precedents" (for example, env vars are trusted; React is XSS-safe unless `dangerouslySetInnerHTML`).
- Execution: one sub-task finds issues, a parallel sub-task re-checks each one, and anything below 8/10 confidence is dropped.
- [security-review.md](https://github.com/anthropics/claude-code-security-review/blob/main/.claude/commands/security-review.md)
- Weaknesses:
  - The exclusion list is opinionated: memory-safety in memory-safe languages, all DoS, outdated dependencies.
  - Two items are both numbered "16" (a sign of light editorial maintenance).
  - Last pushed in February 2026.
  - [security-review.md](https://github.com/anthropics/claude-code-security-review/blob/main/.claude/commands/security-review.md); [GitHub API](https://api.github.com/repos/anthropics/claude-code-security-review)

**Trail of Bits `differential-review`** (7.4 KB plus methodology, adversarial, reporting and patterns files, and an adversarial-modeler agent) — [SKILL.md](https://github.com/trailofbits/skills/blob/main/plugins/differential-review/skills/differential-review/SKILL.md)
- Risk-first triage by file (auth, crypto, external calls and value transfer count as HIGH), with depth scaled to codebase size.
- Git blame on removed security code.
- Quantified blast radius by counting callers.
- Test-coverage check on modified code.
- Adversarial exploit modeling for HIGH-risk changes.
- A mandatory report file.
- Rationalization table (for example, "Heartbleed was 2 lines", "Refactors break invariants").
- Red flags: code removed from "fix" or "CVE" commits, removed access modifiers.
- Quality checklist.
- [SKILL.md](https://github.com/trailofbits/skills/blob/main/plugins/differential-review/skills/differential-review/SKILL.md)

**Trail of Bits `fp-check`** (6.7 KB plus references) — [SKILL.md](https://github.com/trailofbits/skills/blob/main/plugins/fp-check/skills/fp-check/SKILL.md)
- Verifies suspected bugs. Step 0 restates the claim, root cause, trigger, impact and threat model ("Half of false positives collapse at this step").
- Routes to standard or deep verification, with six gate reviews and bug-class-specific requirements.
- Rationalization row: "LLMs are biased toward seeing bugs and overrating severity".
- Batch triage looks for exploit chains.
- [SKILL.md](https://github.com/trailofbits/skills/blob/main/plugins/fp-check/skills/fp-check/SKILL.md)

**ECC `security-review`** (13 KB) is a secure-coding checklist with TypeScript FAIL/PASS snippets (secrets in env vars, zod validation, file upload limits, SQL injection and so on). It is better suited for writing code than for reviewing a diff. — [SKILL.md](https://github.com/affaan-m/ECC/blob/main/skills/security-review/SKILL.md)

#### Item 76: Writing skills

**superpowers `writing-skills`** (16.7 KB plus references: Anthropic best practices copy, bulletproofing, discovery, persuasion principles, testing-with-subagents) — [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/writing-skills/SKILL.md)
- Frames skill writing as TDD for documentation: run a pressure scenario on a subagent without the skill (RED), record its rationalizations verbatim, write the minimal skill, re-run (GREEN), and close loopholes (REFACTOR).
- Iron Law: "NO SKILL WITHOUT A FAILING TEST FIRST", which applies to edits too.
- Description must state only triggering conditions, never a workflow summary, because agents follow the summary instead of reading the skill.
- Test approach is matched to skill type: discipline, technique, pattern or reference.
- **"Match the Form to the Failure"** table: prohibitions plus rationalization tables for discipline failures; positive recipes for output-shape problems; required template slots for omissions; conditionals keyed to observable predicates.
- Micro-test wording first: 5+ reps, a no-guidance control, and manual reading of flagged matches.
- Detailed creation checklist.
- [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/writing-skills/SKILL.md)

**Anthropic `skill-creator`** (33 KB, 485 lines, plus grader, comparator and analyzer agents, eval-viewer HTML, and scripts `run_eval.py`, `aggregate_benchmark.py`, `improve_description.py`, `run_loop.py`, `package_skill.py`) — [SKILL.md](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md); [tree](https://api.github.com/repos/anthropics/skills/git/trees/main?recursive=1)
- Workflow: capture intent and interview, draft, write 2-3 realistic test prompts in `evals/evals.json`, run with-skill and baseline in parallel, draft assertions while they run, grade and aggregate, review in a viewer, iterate.
- Optional blind A/B comparison.
- Separate description-optimization loop for triggering accuracy.
- Says to make descriptions "a little bit 'pushy'" because Claude tends to undertrigger.
- Writing style: explain the why rather than "heavy-handed musty MUSTs". All-caps ALWAYS/NEVER is a "yellow flag".
- Keep SKILL.md under 500 lines and use progressive disclosure.
- [SKILL.md](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md)
- Direct philosophical conflict: skill-creator discourages MUST/NEVER and pushes descriptions that summarize what the skill does. Superpowers uses Iron Laws in caps and forbids workflow summaries in descriptions. — [skill-creator](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md) vs [writing-skills](https://github.com/obra/superpowers/blob/main/skills/writing-skills/SKILL.md)

### Inferences
- Superpowers skills share a recognizable template: a trigger-only description, a one-line core principle, an Iron Law in a code block, a phase checklist, a rationalization table, a red-flags list, a quick-reference table, and cross-references to sibling skills. Most SKILL.md files are 3-10 KB. That template is itself a candidate standard for kurtkode's skill library.
- Anthropic's and Trail of Bits' review and security tools solve a problem superpowers ignores, namely **false positives**. They use independent validation subagents, confidence thresholds and explicit exclusion lists. Superpowers' reviewer prompt has no equivalent.
- The wshobson and ECC "developer-essentials" style (human tutorial, best-practice bullets, "Master X" descriptions) gives the model knowledge it mostly already has and little behavioral constraint. These are low value as process skills.
- Most Anthropic plugin content is in slash-command or agent form, not SKILL.md. Adopting it into a cross-harness skill library means converting it, including replacing `!` shell injection and `gh`-specific steps.

### Gaps
- I did not read every supporting file: TDD's `writing-good-tests.md`, superpowers' `testing-skills-with-subagents.md` and `bulletproofing.md`, ToB `methodology.md` and `adversarial.md`, and the full ECC tdd-workflow, git-workflow and security-review files (only the first 110 lines). Judgments about those files rest on the SKILL.md and headers.
- I did not find a prominent standalone merge-conflict-resolution or PR-description process skill. Both items 51 and 52 lack a canonical source in the repos searched.
- I did not survey OpenAI Codex or Cursor-native rules files (for example AGENTS.md collections) for these process areas.

---

## What failure modes do they target, and is there evidence they work?

### Takeaway
Each skill names specific agent failure modes: guess-and-check fixing, test-after, premature "Done!", sycophantic acceptance of review, building before understanding, and false-positive floods in review. Evidence of effectiveness is mostly self-reported pressure-scenario testing (superpowers) or not stated at all (Anthropic plugins, wshobson, ECC). The best evidence found is superpowers' own 2026 micro-test design docs, which report small-sample (5-25 rep) controlled comparisons on specific wording choices, not on whole-skill outcomes.

### Cited Findings
- **systematic-debugging** targets: proposing fixes before investigating, stacking multiple fixes, "one more fix" loops, and skipping the process under time pressure. — [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/systematic-debugging/SKILL.md)
  - Evidence: CREATION-LOG reports 4 validation tests (academic, time pressure, complex system, failed first fix), all marked "passed". It gives no sample sizes and no baseline comparison. — [CREATION-LOG.md](https://github.com/obra/superpowers/blob/main/skills/systematic-debugging/CREATION-LOG.md)
  - The pressure-test scenarios ship in the repo (`test-pressure-1..3.md`, `test-academic.md`). — [tree](https://github.com/obra/superpowers/tree/main/skills/systematic-debugging)
  - The root-cause-tracing example claims "1847 tests passed, zero pollution" for one real session. That is anecdotal. — [root-cause-tracing.md](https://github.com/obra/superpowers/blob/main/skills/systematic-debugging/root-cause-tracing.md)
- **TDD** targets writing code before tests, tests that pass immediately, mock-testing, and sunk-cost retention of untested code. The v7 addition targets agents that run only their own test file and omit failures they saw. — [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/test-driven-development/SKILL.md)
- **verification-before-completion** targets unverified success claims, trusting subagent "success" reports, and linter-as-compiler substitution. — [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/verification-before-completion/SKILL.md)
- **receiving-code-review** targets performative agreement ("You're absolutely right!"), blind implementation, partial implementation of unclear batches, and YAGNI feature creep from reviewers. — [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/receiving-code-review/SKILL.md)
- **executing-plans** targets four failures: re-implementing completed tasks after context compaction (hence the ledger), silent deviation from the plan (hence ledgered rulings), check-in stalls, and accepting reviewer severity labels uncritically. — [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/executing-plans/SKILL.md)
  - Evidence: an eval of the plan-scoped ledger workspace reports 15/15 RED reps refusing to adopt a foreign plan's ledger, 5/5 GREEN, and a 5/5 regression control on legitimate resume. Earlier fixture versions were found invalid during the eval. — [eval results](https://github.com/obra/superpowers/blob/main/docs/superpowers/specs/2026-07-06-sdd-plan-scoped-workspace-eval-results.md)
- **writing-skills / skill wording** evidence: a 2026-06-10 design spec reports micro-tests (opus, 5 reps per phrasing). — [positive-instruction spec](https://github.com/obra/superpowers/blob/main/docs/superpowers/specs/2026-06-10-positive-instruction-redesign-design.md)
  - Results:
    - A prohibition ("don't restate the brief") produced 4.4 re-typed spec values, worse than no guidance (3.6).
    - A positive recipe produced 3.0 with zero variance.
    - Adding a nuance clause to the recipe degraded it to 3.8.
    - A discrete prohibition ("do not ask reviewer to re-run tests") gave 0/5 violations against 3/5 in the control.
  - From these it derives a doctrine: tripwires, recognition tables and discrete prohibitions work; composition prohibitions backfire.
  - It also reports that Codex re-reads SKILL.md about 500 times per long session, so prose length is a real cost.
- The superpowers `persuasion-principles.md` reference grounds its authority, commitment and scarcity framing in Meincke et al. (2025), which reports persuasion raising LLM compliance from 33% to 72% (N=28,000). That study was about compliance with objectionable requests, not coding-skill adherence. — [persuasion-principles.md](https://github.com/obra/superpowers/blob/main/skills/writing-skills/references/persuasion-principles.md)
- Jesse Vincent's launch post (2025-10-09) describes his testing:
  - Early subagent testing gave false "perfect scores" because Claude was "quizzing the subagents like they were on a gameshow".
  - Realistic pressure scenarios (production outage, sunk cost) worked better.
  - Evidence of efficacy is anecdotal.
  - [blog.fsck.com](https://blog.fsck.com/2025/10/09/superpowers/)
- Simon Willison's coverage describes Vincent as one of the most creative coding-agent users, which is reputational rather than empirical. — [Simon Willison](https://simonwillison.net/2025/Oct/10/superpowers/)
- Superpowers' `tests/` tree tests mostly harness integration, scripts (`test-find-polluter.sh`, `test-render-graphs.sh`) and skill size, not behavioral outcomes of the process skills. — [superpowers tree](https://api.github.com/repos/obra/superpowers/git/trees/main?recursive=1)
- **Anthropic code-review** targets false positives and noise. It states the rationale ("False positives erode trust") but publishes no precision or recall numbers in the command or README. — [code-review.md](https://github.com/anthropics/claude-code/blob/main/plugins/code-review/commands/code-review.md); [README](https://github.com/anthropics/claude-code/blob/main/plugins/code-review/README.md)
- **Anthropic security-review** also targets false positives through the >80% exploitability bar, the exclusions and the second-pass filter. The repo contains a `claudecode/evals/` directory, but I did not find published results in the command file. — [security-review.md](https://github.com/anthropics/claude-code-security-review/blob/main/.claude/commands/security-review.md); [repo tree](https://api.github.com/repos/anthropics/claude-code-security-review/git/trees/main?recursive=1)
- **Trail of Bits fp-check** names the bias directly: "LLMs are biased toward seeing bugs and overrating severity". It states no measured results. — [SKILL.md](https://github.com/trailofbits/skills/blob/main/plugins/fp-check/skills/fp-check/SKILL.md)
- **Anthropic skill-creator** is the only source that builds evaluation into the authoring workflow: with-skill versus baseline runs, assertions, benchmark aggregation with variance, blind comparison and description-trigger optimization. It does not publish evidence about its own effectiveness. — [SKILL.md](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md)
- igmarin `refactor-code` ships an eval fixture (`personal-evals/skill-refactor-safely-controller-extraction` with `criteria.json`). No results were published. — [repo tree](https://api.github.com/repos/igmarin/rails-agent-skills/git/trees/main?recursive=1)
- The wshobson and ECC skills read state no target failure modes and no evidence. — [wshobson debugging-strategies](https://github.com/wshobson/agents/blob/main/plugins/developer-essentials/skills/debugging-strategies/SKILL.md); [ECC verification-loop](https://github.com/affaan-m/ECC/blob/main/skills/verification-loop/SKILL.md)

### Inferences
- No skill in any area has published outcome-level evidence (for example, "bugs fixed correctly with and without the skill on N tasks"). Kurtkode could differentiate by running its own with-skill versus baseline evals using skill-creator's harness design, on local models per Kurt's testing preference.
- The superpowers wording doctrine ("match the form to the failure") is the most actionable empirical finding for authoring. It also partly reconciles the conflict with skill-creator: use MUST/NEVER for discipline gates, and use explained positive recipes for output shape.
- Star counts (300k for superpowers, 288k for ECC) measure popularity, not efficacy. The ECC skills I read are generic.

### Gaps
- No independent (non-author) evaluation of any of these skills was found.
- I did not check whether Anthropic has published precision numbers for `/code-review` or `/security-review` in blog posts or docs.
- The Meincke et al. paper was not read directly; it is cited secondhand via superpowers.

---

## Which is best in each area, and what would an improved version add?

### Takeaway
Adopt or adapt superpowers for debugging, TDD, verification, receiving review, planning and writing skills. Adapt Anthropic's and Trail of Bits' multi-agent, false-positive-filtered designs for performing code review and security review. Write new skills for refactoring, commit/PR/conflict hygiene and codebase orientation, borrowing the best parts listed below. Across the board, improved versions should add proportionality (a fast path for trivial work), autonomous-mode behavior (what to do when no human is available), multi-language examples kept short, and a real eval set.

### Cited Findings (best-of-area verdicts, with basis)

| Item | Best existing | Why | Runner-up | Suggested action |
|---|---|---|---|---|
| 31/32 Debugging / RCA | superpowers `systematic-debugging` + `root-cause-tracing.md` | Explicit gate, the 3-fix architecture stop, boundary instrumentation, backward trace, a polluter-bisect script, and shipped pressure tests ([SKILL.md](https://github.com/obra/superpowers/blob/main/skills/systematic-debugging/SKILL.md)) | ToB `patching-bugs` for independent fix proof ([SKILL.md](https://github.com/trailofbits/skills/blob/main/plugins/patching-bugs/skills/patching-bugs/SKILL.md)) | Adapt |
| 13 TDD | superpowers `test-driven-development` | Mandatory watch-it-fail, Good/Bad examples, a rationalization table, and a full-suite rule ([SKILL.md](https://github.com/obra/superpowers/blob/main/skills/test-driven-development/SKILL.md)) | ECC `tdd-workflow` RED/GREEN checkpoint commits ([SKILL.md](https://github.com/affaan-m/ECC/blob/main/skills/tdd-workflow/SKILL.md)) | Adapt (add legacy and characterization path) |
| 28 Perform review | Anthropic `/code-review` | Parallel reviewers, then per-issue validation, a high-signal bar and an explicit false-positive list ([code-review.md](https://github.com/anthropics/claude-code/blob/main/plugins/code-review/commands/code-review.md)) | superpowers `code-reviewer.md` for plan alignment and the "declined to judge" list ([code-reviewer.md](https://github.com/obra/superpowers/blob/main/skills/requesting-code-review/code-reviewer.md)) | Rewrite as a SKILL.md merging both |
| 29 Receive review | superpowers `receiving-code-review` | The only serious one: verify-before-implement, anti-sycophancy, a YAGNI grep, clarify-all-first ([SKILL.md](https://github.com/obra/superpowers/blob/main/skills/receiving-code-review/SKILL.md)) | none found | Adopt, then add a PR-thread workflow |
| 6/7/11/12 Plan & execute | superpowers `brainstorming` → `writing-plans` → `executing-plans` | Design gate, the plan as "decisions the implementer cannot make", Interfaces blocks, Review Focus, a compaction-proof ledger, ledgered rulings ([writing-plans](https://github.com/obra/superpowers/blob/main/skills/writing-plans/SKILL.md); [executing-plans](https://github.com/obra/superpowers/blob/main/skills/executing-plans/SKILL.md)) | Anthropic `feature-dev` (simpler, parallel explorers and architects) ([feature-dev.md](https://github.com/anthropics/claude-code/blob/main/plugins/feature-dev/commands/feature-dev.md)) | Adapt and decouple from superpowers paths and scripts |
| 30 Verification | superpowers `verification-before-completion` | Compact claim-to-evidence table and gate function, language-neutral ([SKILL.md](https://github.com/obra/superpowers/blob/main/skills/verification-before-completion/SKILL.md)) | ECC `verification-loop` as a tool checklist ([SKILL.md](https://github.com/affaan-m/ECC/blob/main/skills/verification-loop/SKILL.md)) | Adopt plus a small per-stack gate list |
| 14 Refactoring | igmarin `refactor-code` (obscure, Rails-only) | Characterization-test gate, no mixing behavior and structure, one boundary per step, observed-output labeling ([SKILL.md](https://github.com/igmarin/rails-agent-skills/blob/main/skills/refactor-code/SKILL.md)) | wshobson `refactor-clean` for the smell catalog only ([refactor-clean.md](https://github.com/wshobson/agents/blob/main/plugins/code-refactoring/commands/refactor-clean.md)) | Rewrite (language-neutral) |
| 50-52, 75 Git | superpowers `using-git-worktrees` + `finishing-a-development-branch` | Agent-specific safety (isolation detection, native-tool preference, typed `discard`, no force) ([worktrees](https://github.com/obra/superpowers/blob/main/skills/using-git-worktrees/SKILL.md); [finishing](https://github.com/obra/superpowers/blob/main/skills/finishing-a-development-branch/SKILL.md)) | wshobson/ECC git references for bisect, reflog and rebase knowledge ([wshobson](https://github.com/wshobson/agents/blob/main/plugins/developer-essentials/skills/git-advanced-workflows/SKILL.md)) | Adapt worktrees and finishing; write new commit-hygiene, PR-description and conflict skills |
| 1 Orientation | ToB `audit-context-building` (method) + ECC `codebase-onboarding` (checklist) | ToB: follow the calls, cite every claim, `nothing found` assumptions, schema-bound subagents. ECC: concrete recon checklist ([ToB](https://github.com/trailofbits/skills/blob/main/plugins/audit-context-building/skills/audit-context-building/SKILL.md); [ECC](https://github.com/affaan-m/ECC/blob/main/skills/codebase-onboarding/SKILL.md)) | Anthropic code-explorer agent ([code-explorer.md](https://github.com/anthropics/claude-code/blob/main/plugins/feature-dev/agents/code-explorer.md)) | Rewrite, combining these |
| 38 Security review | Anthropic `/security-review` for diffs; ToB `differential-review` + `fp-check` for depth | Anthropic: high-confidence bar, exploit scenario per finding, FP precedents. ToB: risk triage, blame on removed security code, blast radius, FP gates ([security-review.md](https://github.com/anthropics/claude-code-security-review/blob/main/.claude/commands/security-review.md); [differential-review](https://github.com/trailofbits/skills/blob/main/plugins/differential-review/skills/differential-review/SKILL.md); [fp-check](https://github.com/trailofbits/skills/blob/main/plugins/fp-check/skills/fp-check/SKILL.md)) | ECC `security-review` as a secure-coding checklist ([SKILL.md](https://github.com/affaan-m/ECC/blob/main/skills/security-review/SKILL.md)) | Adapt Anthropic's as the default; link ToB skills for deep audits |
| 76 Writing skills | Both: superpowers `writing-skills` (wording discipline and pressure testing) + Anthropic `skill-creator` (eval harness and trigger optimization) | Complementary: superpowers has the empirically grounded form-to-failure doctrine; skill-creator has the tooling ([writing-skills](https://github.com/obra/superpowers/blob/main/skills/writing-skills/SKILL.md); [skill-creator](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md)) | — | Write a merged kurtkode version that resolves the MUST-vs-explain conflict explicitly |

### Inferences (what improved versions should add)
- **Debugging:** a proportionality clause, so a typo with an obvious stack trace takes a fast path. Also an autonomous-mode rule for the 3-failed-fixes case (write up findings and stop, instead of "discuss with partner"); `git bisect run` and delta debugging (taxonomy item 33); debugger use; concurrency and flaky-test branches; and a non-TypeScript example.
- **TDD:** a legacy-code path using characterization tests (borrowed from igmarin), guidance for UI and visual work and for exploratory code, an explicit link to the verification skill's revert-then-fail check, and a language-neutral example set kept to one primary and one alternate.
- **Code review (perform):** merge Anthropic's validate-each-finding step and false-positive list with superpowers' plan alignment and "declined to judge" list. Make it harness-neutral (local diff first, GitHub optional), add a calibrated severity rubric, keep the README in sync with behavior, and include an eval set of seeded bugs to measure precision and recall.
- **Receiving review:** a workflow for many-comment PRs: a ledger of comments with status, reply in thread, one commit per logical fix, re-request review, and how to treat bot reviewers. Soften or justify the "no thanks" rule for human-facing contexts.
- **Planning:** a non-interactive or batch mode for brainstorming (assume defaults and record them as rulings, mirroring executing-plans), decoupling from superpowers paths and scripts, and a single plan template usable by both subagent and inline execution.
- **Verification:** a per-stack table of what "verified" means (compiled languages, web UI with screenshots, CLI, services), plus reporting of what could *not* be verified (ToB's "explicit validation gaps" idea from post-patch-validation, [README](https://github.com/trailofbits/skills/blob/main/README.md)).
- **Refactoring:** a new language-neutral skill. Characterization tests first; structure-only commits; one boundary per step; run the suite after each step; revert on red; record observed output; compatibility shims with a removal condition. Include a short catalog of safe mechanical moves (rename, extract, inline, move) and when to use codemods (item 65).
- **Git:** new skills for atomic commits (stage by hunk, message explains why), PR descriptions (what, why, how verified, risks), and merge-conflict resolution: understand both sides' intent via `git log -p` on each side, never pick "ours" or "theirs" wholesale without reading, and re-run tests after resolving. Keep superpowers' safety gates (no force-push, confirm destructive operations).
- **Orientation:** combine ECC's recon checklist with ToB's "follow the calls, cite a line or mark it an open question" rule. Write output for the agent's own working notes (entry points, build and test commands, conventions, unknowns) rather than a human onboarding doc. Delegate exploration to subagents that return compact records.
- **Security review:** keep Anthropic's high-confidence bar and per-finding exploit scenario. Make the exclusion list configurable rather than hardcoded, add ToB's blame-on-removed-security-code and blast-radius steps for HIGH-risk files, and route deep findings to an fp-check-style verifier.
- **Writing skills:** state when to use prohibition-style Iron Laws (discipline failures) and when to use explained positive recipes (shape failures), citing the superpowers micro-test data. Adopt skill-creator's with-skill versus baseline eval loop. Require a trigger-only description, but test triggering with skill-creator's description optimizer.
- **Format across the library:** the superpowers template (Iron Law, phases, rationalization table, red flags, quick reference) at 3-10 KB is a good default for P skills. Heavy material belongs in reference files, per skill-creator's 500-line guidance and the superpowers measurement that SKILL.md prose is re-read hundreds of times per session.

### Gaps
- The "best" verdicts are based on reading text, not on running the skills. No head-to-head eval was performed in this research.
- Licensing for reuse was not checked per repo (superpowers has a top-level LICENSE file, which I did not read; ToB, ECC and wshobson were not checked; skill-creator ships its own LICENSE.txt). This needs checking before adopting text verbatim.
