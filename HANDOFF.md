# kurtkode: handoff

**Start here (2026-11-06: prompt caching, branch `caching`, worktree ~/git/kurtkode-caching).**
- **The research:** CACHING_REPORT.md covers what Claude Code and Codex do, each provider's levers, and this Mac's
  Claude Code logs. Its finding is that 98% of prompt tokens are cache reads, and that context size is now the lever.
- **The plan:** CACHING_PLAN.md.
- **Built:** Phase 0 and Phase 1, in 7 commits on top of main, not merged and not pushed. The plan's "Status" table
  says what went in and what differs, for example that the between-turn mode switch still changes the system prompt.
- **Commands:**
  - `kurtkode cost cache` names every cache miss's cause and cost;
  - Settings → Prompt cache defaults to an hour for your sessions and five minutes for the rest.
- **Live check:** OpenRouter, $0.017, done 2026-11-06. `session_id`, provider stickiness, one-off
  `prompt_cache_options` and the hour TTL all work. It found an OpenRouter hour-write pricing bug, now fixed
  (bed1437). OpenAI's own API and native Anthropic weren't checked.
- **Next:**
  - Phase 2, the compaction experiment (≈$10–15, the user's approval);
  - Phase 3, the ChatGPT plan backend, which is researched and waits on the user's four decisions.

**Start here (2026-11-04 to 06: what the cost data decides).** COST_AUDIT.md section 12: 47 real tasks in six
repositories and three languages ($54.74 in all) settle the tiers (Haiku 85% of real edits, deepseek-off 63%, ling 28%),
so building more edit tasks of the same shape would only re-confirm them. Its two proposals are done (a56fbdf, not
pushed): deepseek-v4-flash-0731 (reasoning off) is a reviewer only, off the retry ladder (ling, then Haiku), and the
shipped pool's notes quote section 12; the ladder's own tests run on `ModelPool.threeRungs`, a test-only copy of the old
pool. On this Mac, the saved `~/Library/Application Support/kurtkode/pool.json` was the old shipped pool unchanged; it
was replaced with the new one (`kurtkode pool init`, 2026-11-06) and the old kept as `pool.json.before-2026-11-06`.
**Live sessions are journaled, but there's almost nothing to learn from**: 34 sessions, 41 main runs, 204 requests,
$0.72 at list price since September, mostly local models, 2 judgments from the user; the installed `kurtkode.app` is
from 2026-09-27, older than the signals and thumbs (Phase 2). Real-session labels (COST_AUDIT.md P4) need a current
install used for real work on a hosted model. Open, each the user's call (section 12): the router's Brier comparison on
the 153 labeled failures (free), a same-model retry on cut-off replies (≈$2), a higher output limit for the escalation
target (≈$2–4), real-sized lookups from a second codebase (the only new tasks worth building, ≈$5 to run).

**Start here (2026-11-03: the Go sets run, and the eval's grading fixed).** REAL_TASKS_PLAN.md "A second language
from another author". Sets `cel` (google/cel-go, 5) and `opa` (OPA, 6), committed 00a4954 with b6bbb45's sandbox fix
(GOCACHE). Pilot and Main (391e314, $4.75, `eval-results/runs/real4`): Haiku 31/33, deepseek-off 24/33, ling 11/33,
every failure checked by hand. Run them with `~/sdk/go/bin` on PATH, `GOTOOLCHAIN=local`, `GOPROXY=off` and
`GOMODCACHE=~/sdk/gomodcache`; their code runs only in kurtkode's sandbox (`validate_task.py --sandbox-only`, which
also needs GOCACHE set by hand). A rebuilt release `kurtkode-eval` raises a Keychain dialog: the pilot waited 7¾ hours
on it. Then BUG_HUNT_2026-11-02.md's P3, the eval harness's grading flaws, fixed in 13bbba8 ("Status: P3 fixed"): gold
measures a run's change from `refs/kurtkode/base` (so committed work counts), its suite runs in a process group of its
own, its note names the failing tests, a fixture that can't be made is an infrastructure failure, and runs carry their
options' fingerprint so a set won't resume under other options. Still open: the cascade on the Go sets (little to show
with 2 Haiku failures), the sandbox's localhost bind for tests that start a server (a design decision), P4.

**Start here (2026-11-02: the bug hunt, the default model picker, the pool editor).** BUG_HUNT_2026-11-02.md: 131
candidate findings across the codebase, prioritized P0 to P4. P0 to P2 are fixed and merged into main (75641ac, not pushed;
its "Status: P0, P1 and P2 fixed" names the commit per item and what changes for the user); P3 is above; P4 is left.
The default model picker (8e62b04; TODO.md "Default model picker") compiles but hasn't been seen on screen. Settings →
Pool now edits the pool in the app (b9d1daa: add, duplicate, move, remove, the retry rung, provider pins; an unreadable
pool.json is copied aside first).

**Start here (2026-10-31: the real local models).** FUNCTIONAL_TEST_RESULTS.md "Real local models": Phase 5's reach on qwen3-coder
(`t11.py`). Four fixes, uncommitted on branch `capabilities` when written. A vision model's reading is still unproven.

**Start here (2026-10-31: Round 8 and its fixes).** FUNCTIONAL_TEST_RESULTS.md "Round 8" has the 60 candidates and its "Fixes"
says what went in, how each was checked and what still rests on a unit test or a compile. Six commits on main, acde196 to
85b9373, not pushed; the install was held for these, and they're the first build worth installing since Phase 5. Before touching
the sandbox read GAP_ANALYSIS.md "The sandbox" in the worktrees section: a guard names a path, so every guarded path's ancestors are
pinned against renames, a worktree gets a list of what it may write rather than `.git`, and `GitRepo.safeConfig` goes on
every git kurtkode runs. A full-suite summary line can be missing when the run died: check for it, don't only count failures.
Open: TODO.md "Round 8", the user's hand checks (FUNCTIONAL_TESTS.md 22B.11, 22B.12), a real MCP server and a real vision model.

**Start here (2026-10-31: `ask_user` asks like Claude's tool).** A call now takes `questions`, 1 to 4 asked together, each
with a `header`, options with a `label` and `description`, and `multiple`. The tool's old flat form and models' loose
forms (lists as JSON text, plain-string options) still parse (`AskUserTool.questions(in:)`). The first option shows as
recommended, except when several may be picked. The app's card shows the questions together; the live CLI has a list
under the composer (`QuestionChoices`: ↑↓, space, Enter; typing still answers in words, and Enter is ignored for 0.5s
after a question opens, so a stray Enter can't pick the first option), `--plain` keeps numbered prompts. Esc or Skip
skips the rest. Tested by `AskUserQuestionsTests`, `spike/functest/cli/t6.py` (a real pty) and `live_ask.py`, live on
Claude, GPT and Gemini through OpenRouter and Gemini natively ($0.26). Not tested: native Anthropic (the account has no
credit) and clicking the app's card (`KURTKODE_AUTOANSWER` covers its answer path). The eval doesn't offer `ask_user`, so
its prompts don't change.

**Start here (2026-10-30: agent capabilities, branch `capabilities`).** GAP_ANALYSIS.md "Phase 5, agent capabilities, as
built". The last batch of the quality-of-life order: `web_fetch` for every model, images and PDFs in `read_file`, `/btw`,
four more hook events, MCP resources and cancellation, a first-run sheet. Left for the user's decision: `/goal` and `/loop`
(they spend unattended, so they need limits decided), moving a running command to the background, MCP prompts and OAuth.
`web_fetch` is in `AllTools`, so like the `task` change before it, a rebuilt `kurtkode-eval` sends a different prompt.

**Start here (2026-10-30: worktrees and review, merged 1e61445).** GAP_ANALYSIS.md "Phase 5, worktrees and
review, as built". The third batch of the quality-of-life order: sessions in worktrees (`kurtkode -w NAME`, the sidebar's
branch button), subagents with `isolation: worktree` that may write beside you and in the background, Changes against
what's uncommitted or the branch's start, comments on diff lines sent as one message, opening a file at its line, and a
Git panel with branches, stashes, push, a written commit message and merging a worktree back. The sandbox opens the
repository's `.git` to a worktree by where it is, never by what its `.git` file says: see that section before touching
`LinkedGit`. The `task` tool's description and schema changed, so a rebuilt `kurtkode-eval` sends a new prompt: compare
runs across this change with that in mind. Next in the order: agent capabilities.

**Start here (2026-10-30: the CLI's live screen, merged 40e1950, was branch `cli-interaction`).** GAP_ANALYSIS.md "Phase 5, CLI, as built".
The second batch of the quality-of-life order: `kurtkode` in a terminal now keeps a live composer and status line at the
bottom of a normal scrolling terminal (`KurtkodeCLI/Terminal/`), with typing and queueing during a run, Esc, Shift-Tab,
rendered Markdown, diffs, `/status`, `/resume`, `/copy`, `/export`, working `/rename` and `/retry`, `kurtkode endpoint`
and `kurtkode doctor`. `--plain`, piped input and `-p` keep the old path. Tested by unit tests and three scenarios in a
real pty (`spike/functest/cli/`). Next in the order: worktrees and review, then agent capabilities.

**Start here (2026-10-30: the app's everyday friction, merged 7317319).** GAP_ANALYSIS.md "Phase 5, app friction,
as built". The user set cost work aside for quality of life, with Claude Code and Codex as the standard; a comparison of
both (from their current docs) ranked the app's daily friction first, the CLI's interaction layer second, worktrees and
review third, agent capabilities fourth. The first batch is built on `app-friction` in the worktree
`~/git/kurtkode-friction`: Esc, prompt recall, paste chips, commands in the queue, a todo strip, grouped tool rows with
live times, find in chat, fork and copy on messages, sidebar badges and search, model-written titles, and the offer to
continue a run that was cut off. CLI unchanged. Tested by unit tests and by driving the app on a mock server (below).

**Start here (2026-10-30: group D, an Opus cascade, Sonnet as the frontier).** REAL_TASKS_PLAN.md's last three
sections. Group D (write tests for a fixed bug) is the real set `rdw`, committed 16b9283; Haiku's pilot passed 3 of 3
with real tests ($0.05), so the set is easy. A live cascade escalating Haiku to Opus over all 24 real tasks ($15.98)
fixed 7 of 8 failed runs at $1.57 each, against Sonnet's 9 of 9 at $0.72, so the shipped pool's frontier entry is now
**Sonnet** (`ModelPool.shipped`; user's decision). Found there and fixed: the after-run suite check ran in the run's
persistent shell, so a model's `cd` moved it (kk01 #3 escalated on exit 127); it now runs from the project's root in
a copy of the shell (`AgentLoop.runCheck(fromRoot:)`, `TestSuiteTests`).
Still open from section 10: the same-model retry on runaway reasoning.

**Start here (2026-10-28, later: three of section 10's proposals built and committed).** COST_AUDIT.md **section 11**:
escalation after a review only on "wrong" ("has problems" goes to fixing on the session's model; `CodeReview.escalates`,
`CLISession.reviewToFix`); a new escalation reason for a main run that changed nothing on a change request
(`Escalation.gaveUp`, `asksForChange`, `RunSignals.changeAsked`; 2 fires on 794 stored runs, both real failures); the
`handoff-notes` skill reworded so low context isn't a reason to stop. Also `ReviewSim.ownDiff` now diffs against the
fixture's last eval commit. Still open from section 10: the same-model retry on runaway reasoning (paid, small) and
Opus vs Sonnet as the standard tier's escalation target (the user's call; decided 2026-10-30: Sonnet).

**Start here (2026-10-28: the real-task measurements finished).** All of REAL_TASKS_PLAN.md's paid rows ran on the
first 11 real tasks: Pilot, Main, Frontier (Sonnet 10/11), P3 at real size, P5, and a **live cascade** over all 21 real
tasks (new `--cascade` mode, `EvalKit/Cascade.swift`: Haiku main runs in a real CLI session, the product's escalation
offer taken, Sonnet through the hand-over; 84% → 98% at $0.13 a run). COST_AUDIT.md **section 10** has the results and
the decisions they change (proposals for the user: same-model retry on runaway reasoning, Opus vs Sonnet as the
escalation target, escalate after a review only on "wrong", an "edit request ended with no change" reason, the
`handoff-notes` skill's wording). Grading fixes on the way: edited test helpers judged against the original tests,
a new test file that clashes with the hidden tests set aside, six lookup patterns widened, P3's diff against the run's
own first commit, `--regold` rebuilding a kurtkode fixture's `.build`, `--regold-cascade`. Stores (gitignored):
`eval-results/runs/real2`, `cascade2` (and `cascade1-32k`, set aside), `bank1` judgments. Nothing committed yet.
`AgentCore/Sources/AgentCore/LLM/WireFormat.swift` and its test have someone else's uncommitted edits (since
2026-10-27 19:52), compiled into the current eval binary; leave them out of commits. Session 18's paragraph follows.

**Start here (2026-10-27, session 18: the audit's decisions implemented).** The user asked for COST_AUDIT.md's
recommended decisions to be implemented in its recommended order, with no paid calls. **All are on main**: the branch
`cost-audit-improvements` (16 commits, up to 9a5e9e6) was fast-forwarded into main locally on 2026-10-27, not pushed; COST_AUDIT.md section 8 lists each with its test.
In short: code-changing subagent tasks default to Haiku (11a); the system prompt's root, date and git status are its
last section, with a cache breakpoint before them on Claude wires (improvement 1; **P1 confirmed it live**); no Opus fallback grader; the retry ladder is off by default; a time-cost column ($30 an hour);
OpenRouter price jumps over 3× are held until confirmed; reports count every request under its own model and read
settled charges; unpriced remote models count toward limits at $3/$15 a million; the eval's cap counts runs in flight.
cf6's 340 glitch-priced deepseek runs were corrected in place (backups in `eval-results/backups/`). Then, with the
user's approval (≈$0.48 in all; COST_AUDIT.md section 9): **P1** (8 of 10 Haiku runs read the cached prefix on their
first request, against 0 of 1,463 before; −37% a run on five bank tasks); **P3** (Sonnet's one-request review flagged 22
of 22 real cheap failures, 1 false alarm in 12 passes, $0.006–0.011 a review); **decision 4** built on it (the escalation
card reviews the change on the offer's model first, re-run second; commit 2e9e131); **improvement 7** built (the note to
delegate also after 30k tokens of reads in a row, never forced) and replayed on Haiku (`--delegation-tokens`): the new
trigger never fired on the scenarios and Haiku ignored the note 6 of 6 times where the old rule gave it. After the merge, **11b** was
built (a project's `testCommand` in `.kurtkode/settings.json` runs again after a main run that changed files; a failure
is an escalation reason; COST_AUDIT.md end of section 9) and **REAL_TASKS_PLAN.md** plans 20 more real tasks (decisions
for the user at its end); its first 11 tasks are built and validated ("The first 11, built"), and the Haiku pilot ($0.55) and the Main row
($3.23; Haiku 22/33, deepseek-off 14/33, ling 11/33; the cheap signals flag 34 of 52 failures) ran on them (sections
"Pilot" and "Main"; store `eval-results/runs/real2`). Left: optional P5 and P3 on real-sized failures; unbuilt 11c's charged prices, B9's last two
purposes and B11 (Next steps). Rebuilding `kurtkode-eval` changes its signature, so the next paid run raises
a Keychain prompt again. Four timing tests (`stopsAtWallClockLimitAndClosesConnection`,
`stopAllEndsRunningCommandsAndTheirChildren`, `timeoutKillsTheWholeProcessGroup`, `cancellationStopsTheCommand`) failed
in a full-suite run at load average 14 and pass alone; everything else passes. Session 17's paragraph
follows.

**Start here (2026-10-26, end of session 17: the cost audit).** **`COST_AUDIT.md` is the independent audit of the
cost-optimization architecture** that AUDIT_PROMPT.md asked for; its working papers and scripts are in `spike/cost-audit/`.
No paid call was made, no model loaded, no product code changed. **Verdict in short**: measuring and the static defaults
are sound and every headline number in the docs reproduces from the stores, but the acting mechanisms barely reach the
bill (nothing automatic moves a hosted main run down a tier; delegation never trips; escalation is advisory), the
benchmarks have no routing headroom (an oracle router beats always-ling by 0–1.5 points; kNN over task text is worse
than the per-model prior, so **P3 should be shelved**), and the detector figures come from enriched samples (20–74%
precise at real failure rates). Two findings worth more than any cascade: **the system prompt's Environment block
(path, date, git summary) sits before the tools and instruction files, so fresh subagent and eval runs never read the
prompt cache** (0 of 480 Haiku runs; cache writes are 54% of Haiku's eval cost), and **the default grader for a
Haiku-run important task is Opus** (deliberate in `ModelPool.grader`; the docs say Haiku) at ≈$0.019 a grade. Also:
deepseek-v4-flash-0731's prices in cf6 and the pool note carry a 10× OpenRouter listing glitch; Sonnet 5.5's cache-read
price is 2× high; several report and accounting defects (COST_AUDIT.md F6). **P2 was then run** (the user approved $10; $10.80 list spent, the Sonnet cap overshot by two in-flight runs): ten
real-sized tasks from responsedigger's history as `--bank real` (`EvalKit/TaskBankReal.swift`, fixtures and `tasks.json`
in `eval-results/real-fixtures/`, store `eval-results/runs/real1`, 72 runs). After **P2b** (2026-10-27, ≈$0.66: the 12
truncated cells re-run at `--max-tokens 16384` with the four sandbox-broken tests skipped by a root `conftest.py` in the
fixtures): **ling 10%, deepseek-off 72%, Haiku 83%, Sonnet 100%**; Haiku is the cheapest success ($0.057 against Sonnet's
$0.78 a run); the bank's 95% floor does not transfer; the after-run re-check agreed with gold on all 12 re-runs, so
"the suite fails after the run" is a usable escalation trigger. Harness limits found and fixed or scored around: the
4,096-token OpenRouter output cap (`--max-tokens`), the sandbox breaking tests that signal child processes (skipped
in the fixtures), deepseek priced at 3× its charge (open). **Decisions for the user** are in COST_AUDIT.md section 7:
the subagent default for real-sized work (Haiku, not ling), the prompt-prefix fix, the grader default. Session 16's paragraph follows.

**Start here (2026-10-26, end of session 16).** **Next: an independent audit of the cost-optimization architecture**,
in a new session, with the prompt in `AUDIT_PROMPT.md`; `COST_ARCHITECTURE.md` maps every cost mechanism to its code,
default and evidence, and lists the lessons so far. Everything is committed; nothing runs in the background. LM
Studio had the user's qwen/qwen3-coder-30b loaded (used as is, not loaded or unloaded by the session).

**Phase 3 (review and cost, part 2) is done**: GAP_ANALYSIS.md "Phase 3 plan"
(with the user's four decisions), "Phase 3 as built" (C1, C3, A6, A4, A7) and "Phase 3 measured"; Round 7 in
FUNCTIONAL_TEST_RESULTS.md (37 review findings, fixed or noted; 645 tests). Commits: 1023b70 plan, b723d99 C1
(snapshots in a shadow git repository per project, beside the sessions; Changes tab, `/diff`, revert by file and hunk),
88bdb36 C3 (rewind from snapshots; files-only, conversation-only; checkpoints list, `/rewind`), 32310b0 A6 (cross-vendor
review, `/review`, Fix These, automatic for important subagent changes; deepseek-v4-flash-0731 shipped as a reviewer),
1b0ffff A4 (advisory escalation card one tier up, `/escalate`, offers recorded; `--trigger-sim`, `--ladder`), 76c3106 A7
(forced or kurtkode-written `task` call at the delegation threshold; `--kk-delegation`), 8d02540 Round 7, then the
measurement commit. **Main findings**: a cheap reviewer is worth running on every code change (deepseek caught 51 of 55
bad changes for $0.0001); no judge makes escalation automatic-worthy (each costs about what the next model does);
A7's threshold never trips for hosted models. **Open, for the user**: the Anthropic key answers "credit balance too
low", so the pool's Haiku and Opus (which resolve to that endpoint first) fail until it's topped up; a token-based
delegation threshold (A7 stays on for local sessions: the user's call after the measurements). Leftovers: Round 7's noted
items (R7-5 concurrent edits during a run, R7-32 old builds, R7-36/37), opening a file at a line in the user's editor,
the app's three-button rewind dialog and checkpoint list not clicked through by hand. The installed app and CLI are
older than Phase 0 (`make install`, `make install-cli` are the user's).

**Session 15 (2026-10-26).** **Phase 2 (cost in sessions) is done**: a model pool with tiers and a
retry ladder, listed capabilities, a reasoning setting per model, pool defaults for subagents and the grader on hosted
sessions, thumbs and end-of-run signals on main runs, `kurtkode cost report`/`whatif`, daily budgets, and Round 6's 30
fixes. Read "Next steps" item 0 below, then GAP_ANALYSIS.md "Phase 2 as built" and "Phase 2 measured". The rest of
this paragraph is session 14's.

**Session 14 (2026-10-25).** Session 13 wrote `GAP_ANALYSIS.md`: kurtkode against Claude Code and
Codex, the gaps ranked, a six-phase plan, and the user's decisions on it (section "Decisions"). Phase 0 is built and
committed (3b976cf). **Session 14 is building Phase 1** (agentic core) one item per commit, in the order B4, B5, B2,
B1, B6, B7; GAP_ANALYSIS.md "Phase 1 as built" says what each changed and what live testing on Gemma 4 26B found.
**Done so far: B4** (grep on a bundled ripgrep), **B5** (multi-edit, a loose second pass, read before edit,
`apply_patch` for GPT families), **B2** (background commands, exported variables carried), **B1** (`present_plan`, a
plan card, read-only bash in Plan mode), **B6** (more instruction files, nested ones on first touch, `@imports`,
project memory with `remember`, `#` and `/memory`), **B7** (a structured compaction summary, the last test command
in the tracked facts). **Phase 1 is done**, measured on the task bank before and after (GAP_ANALYSIS.md "Phase 1 on the
task bank"), and **Round 5 of the functional tests** reviewed, probed and fixed it (FUNCTIONAL_TEST_RESULTS.md "Round 5":
35 findings, 10 serious, all fixed; 19B end to end on pmock and Gemma). See "Next steps" item 0. 537 tests pass. The
installed app and CLI are older than 3b976cf (`make install`, `make install-cli` are the user's). Everything below
this paragraph is the older handoff, still accurate unless it says otherwise.

Read this first, then `PLAN.md` (decisions D1–D16, per-phase findings with measurements, eval tables, and a section per
feature added since), `SUBAGENTS_DESIGN.md` (subagent management: design, decisions, all five phases built), and
`TODO.md` (agreed enhancements not yet scheduled), `FUNCTIONAL_TESTS.md` (the end-to-end suite) and
`SYSTEM_PROMPT.md` (the system prompt's templates: how the prompt is built, overridden and cached),
`EVAL_PLAN.md` and `EVAL_RESULTS.md` (the subagent and judge evaluation: run store, 34-task bank, judges, delegation;
what it found), `COST_FLOOR_PLAN.md` and `COST_FLOOR_RESULTS.md` (every paid OpenRouter model screened for the cheapest one above a
quality floor: ling-3.0-flash clears 95% at $0.0002 a task; delegation economics; the cheapest judge), `SUBAGENT_ROUTING_DESIGN.md` (proposal, not built: when to delegate, routing subagents to models, judging runs,
retries, cost against quality, task similarity; the user took decisions D1–D8 on 2026-10-24; P1 judging built,
see its "P1 as built"; P2 built (delegation rules, task bank, judge calibration), see "P2 as built"; P3 is next),
`FUNCTIONAL_TEST_RESULTS.md` (session 6's run of it; session 7's "Round 2"; "Round 3" of 2026-10-15 and its
fixes; "Round 4" of 2026-10-17 and its A and B fixes), and `COST_TRACKING_DESIGN.md` (cost data for choosing models:
design, decisions, status). Last updated 2026-10-17, end of the tenth session: round 4 of the functional tests (six
code reviews by area, each candidate probed: 29 findings), then **all six A items and all 21 B items fixed** (only
R4-29, a C item, and the traced-but-not-probed review list remain). 382 tests pass with 11 known issues (round 3's C
items); Debug app and CLI build with no warnings. **Everything is committed** (round 4 suite 0df1bd9, A fixes fdeb4c6,
B fixes ce6dba1, the icon exports 6635fdf; HEAD is this handoff).
**The installed app is current**: `/Applications/kurtkode.app` is the Release build of ce6dba1 (round 4's A and B fixes;
the user ran `make install` after this handoff; checked 2026-10-24 by grepping it for strings ce6dba1 added). The CLI in
`~/.local/bin` is not installed (use
`AgentCore/.build/release/kurtkode` after `make cli`; the debug CLI at `AgentCore/.build/debug/kurtkode` is current).

## What this is

A native macOS SwiftUI app, plus a command-line twin, that works like Claude Code / Codex: an agent that reads,
edits, and runs commands in a project folder (or a chat's working folder), backed by local models on LM Studio or any
OpenAI-compatible endpoint (OpenRouter is configured). Key goals: **several models, from different sources, in one
session** (per-turn model switching, subagents on other models, a summarizer model, a fallback model), and, since
session 4, **debugging tool use** (every request recorded; a Debug window with a timeline and a context journal), and
since session 5, **subagent management** (each run recorded and debuggable; live list and stop; parallel and
background runs), and since session 8, **closed models spoken natively** (Anthropic's Messages API, Google's
`generateContent`) with their reasoning made visible as far as the servers allow, and their prompt caches kept.

- Repo: `~/git/kurtkode` (standalone git repo, branch `main`, no remote, no `gh`).
- Machine: M1 Max, **64 GB RAM**; macOS 15.7; Xcode 16.4; Swift 6.1. **Disk: about 81 GB free** (2026-10-12; 129 GB the
  day before, 31 GB in session 4). Not this work: kurtkode's build folders are ~2 GB; LM Studio's cache is 54 GB.
- A second LM Studio on the user's LAN: `http://192.168.1.20:1234` (qwen/qwen3.5-9b loaded, 68k context; also
  gemma-4-e4b, llama-3.x 8B/3B and others listed). The user offered it for tests; it's in their saved endpoints.

## Status

| Work | Commits | State |
|---|---|---|
| 0 Spike + skeleton | 9861e8b, 4b86db0 | done |
| 1 Chat MVP | 583168e | done |
| 2 Read-only agent | 592f0a3 | done |
| 3 Edits, bash, approvals, rewind | b64e0db | done |
| 4 Context management | 6b1395d | done |
| 4.5 Profiles, multi-model sessions, eval suite | 9a19df0 (local), 0c7a297 (OpenRouter), 12572ac (nudge study) | done |
| 5 Power features | 15e8c7e sandbox · 1eb9e37 slash commands · 2fa81fa @file, !cmd · 51db32a queued input · fb4c7bb Models window · 51c3ad6 endpoints · f7f5fae git panel · c138146 images | done |
| 6 Extensibility | 7a38f1b MCP stdio · 4100a60 subagents · 4b80960 hooks · 3a1a6f6 CLI · 570abda MCP HTTP (token auth) | done, except MCP OAuth |
| App icon, packaging | d27fd5f, 42c77eb; 0aeb181 (`make release` / `make install`) | done |
| Freezes | 16e716a (streaming, code highlighting, live output); 207d2b7 (model browser: 61 s and 57 s in use) | fixed; the user confirmed the browser |
| Shared run setup (app and CLI) | cddc164 | done |
| Lost replies retried on another provider, then a fallback model | a4c8c90; measured 99d162a | done (local 30/30 recovered; OpenRouter 2/2 passes) |
| CLI line editing, history, completion; Ctrl-C stops `!commands` | 91979d7 | done (checked in a real pty) |
| Extra folders per session; tools in plain chats | 5cdf972 | done |
| Wire log, turn notes, tool records, Debug window (Timeline) | 264a9b7 | done |
| Context journal (Debug window, Journal mode) | 0f6d69b | done |
| Journal search and filters | 3626277 | done |
| Compactions planned first; skipped when they can't shrink the prompt; summary output room | 348da70 | done (measured on Gemma at 8k) |
| Summary thinking switch (`reasoning_effort`); the fallback summary never thinks | cf0d093 | done (long-doc both ways) |
| Compaction leftovers: `/compact` summary room, summaries in eval results | 0e901ca | done (4+4 long-doc trials) |
| Subagent management design (`SUBAGENTS_DESIGN.md`) | c85b2ef | agreed with the user |
| Subagents 1: each run a child session (also fixes runs leaking into the parent's wire log) | 038b87e | done |
| Subagents 2: Debug window (Subagent section, drill-in with breadcrumb, Journal, totals) | 3c0e974 | done |
| Subagents 3: live control (Agents tab, stop one, `/agents`); CLI Ctrl-C stops the subagent first | 1c3b09f, c9c066b | done |
| Subagents 4: parallel runs (slots per model, writers one at a time, approval queue) | 7bfbf36 | done (also on two machines) |
| Subagents 5: background runs (reports delivered as messages, the loop waits) | 8ac6f03 | done |
| Debugging layer 3: replay (with changes, cost estimate, comparison), cURL, fork, export; summary requests recorded | 715e9dc | done (replayed on the LAN Qwen) |
| Debugging layer 4: `kurtkode inspect`, `replay`, `export` | a47795a | done |
| Functional test run (all 87 tests; results file) | see FUNCTIONAL_TEST_RESULTS.md | done: 82 pass, 5 partial (4 fixed) |
| F1 a reply that is only a tool-call marker (`<tool_call|>`) gets a nudge | 445c5da | done |
| F3 appends after a torn last line start a new line (sessions, wire index) | f684795 | done |
| F4 `kurtkode -p` prints why a run failed (stderr; `"error"` in JSON) | bfdbae6 | done |
| F2 the CLI saves each record as the run goes (was: all at the end) | b1e649c | done |
| F5 one MCP hub per project folder however its path is spelled | 77832b7 | done |
| `/compact` predicts and skips when a summary wouldn't shrink the prompt; new summary counted in place of the old | 0397ba0 | done |
| Functional tests round 2 (section 16) | results commit after c447845 | 4 pass, 5 partial, 2 fail; findings F8–F16, O1–O2 |
| Round-2 fixes: F10 cut stream fails, F11 app/CLI reload a session the other changed, F12 commands stopped at quit/exit, F13 MCP server exit shown, F9 CLI symlink sessions, F8 cut-off call wording, F15 accessibility names, O1 open-todos nudge, O2 stable launch-only endpoint ids | c447845 | done, each with tests and a real check (FUNCTIONAL_TEST_RESULTS.md "Fixes after round 2") |
| F14 streaming stalls (heading-split Equatable Markdown pieces, follow-scroll ≤ 2/s) | c447845 | first attempt, no measurable effect |
| F14 fixed: each Markdown piece a row of the transcript's lazy stack (`MarkdownPieces`), incremental split (`MarkdownSplitCache`), slower updates for long replies, follow by edge (`ScrollPosition`); F16 fixed with it; `KURTKODE_TRACE_BODIES` | aec2d05 (measurements 796108c) | 8/8 soak runs without a stall ≥ 250 ms; CPU per 60 KB stream 112–119 s → 45–52 s |
| F17 "rows drawn twice": not a bug (borderless contact sheets); `spike/functest/ocrheadings.swift` | 3273636 | closed |
| Context meter button only when there's a meter (found checking the installed app) | 7d2eaf2 | done |
| Native Anthropic (Messages API) and Gemini (`generateContent`) endpoints: thinking/signatures round-trip, summarized reasoning shown, Settings presets, replay/cURL per format (PLAN.md "Native Anthropic and Gemini APIs") | fe1b94f | built, unit-tested, checked live |
| Prompt caches: cache tokens recorded and shown, Claude 1-hour cache setting, summaries keep Claude's cache, list-price cost (PLAN.md "Prompt caches on the native APIs") | caeaf6a | built, 258 tests; checked live on Haiku 5.5, Opus 5.5, Gemini 3 Flash (~$0.06); key trimming fix after the user's Anthropic key failed |
| A session keeps its system prompt across processes (date and git status sent as a note on resume) | 1c14520 | 259 tests; checked live (Haiku: resume read 3,638/3,852 from cache, was 0) |
| Closed models' reasoning: Steps tab (server order), shown vs billed reasoning, dropped thinking in the Journal, cache line and cost in the budget chart, effort sweeps (PLAN.md "Seeing closed models' reasoning") | 4446178 | 262 tests; checked in the app on recorded sessions and live on LM Studio Gemma |
| Keyed runs (effort sweeps on Haiku/Opus/Gemini, a real dropped-thinking case); trimming in steps near the limit (PLAN.md "Keyed runs, and trimming in steps") | e48a5f2, 3f57ae1 | 263 tests; Gemma: history changed on 2 of 10 turns (was every turn) |
| Declined replies not retried or nudged; spending limits (run $2 default, session off) with a toolbar cost readout; 32k output / 30 min limits for Claude and Gemini (PLAN.md "Closed-model fixes") | 40b78d5, 30d6e6f, a037658 | 266 tests; Gemma regression run |
| Switch costs in the model menu, notice and CLI; Privacy list of files withheld from remote models, cloud marker, Gemini free-tier note (PLAN.md "Switching costs and privacy") | 9c2831b, 7086f56 | 269 tests; Gemma run |
| Rate-limit pacing, Gemini retry delays, retired-model message; web search for Claude and Gemini (off by default); lean prompt style for frontier models (PLAN.md "Rate limits, web search, and a lean prompt") | b1212ff, 51aba17, 4019078 | 275 tests; eval detailed vs lean on Haiku and Gemini; web search live on both |
| Permission rules (allow/ask/deny, Claude Code format, project allow needs approval), repeat check, destructive commands always asked, notifications (PLAN.md "Safety and awareness") | e3e86a6, b6e08d7 | 279 tests; Gemma -p check; notifications not tried live |
| Agent Skills (SKILL.md in .kurtkode/.claude/.agents skills, `skill` tool, read-only skill folders, `/name` and `/skills`); `ask_user` tool with an app card and CLI prompt (PLAN.md "Skills and questions to the user") | b34a418 | 286 tests; Gemma live in CLI and app |
| Cost tracking phase 1: a cost entry for every billed request (list price by component, raw usage, request ids, purpose, run and agent), in session files, child sessions, replays and eval results (COST_TRACKING_DESIGN.md "Status") | 06fb0ec | 334 tests; 86 recorded paid responses re-priced; Gemma CLI and app runs |
| Cost tracking phase 2: a record per agent run (setup, build, machine, task, totals by component, outcome, children, delegation sizes, empty judgment), input mix per request, `kurtkode runs` export (COST_TRACKING_DESIGN.md "Status") | 4270809 | 337 tests; Gemma CLI and app runs |
| Round 3 of the functional tests: plan, results, 29 findings, unit probes (`Round3Tests.swift`, bugs as `withKnownIssue`) | 3e39d04 | FUNCTIONAL_TEST_RESULTS.md "Round 3" |
| Round 3 fixes, serious: rule and danger-check bypasses (`ShellSplit`), crash on an empty allow rule, grep leaks of denied and withheld files | 4994d95 | Gemma live: `bash -c 'git reset --hard'` refused |
| Round 3 fixes, wrong behavior: Claude/Gemini overflow, overloaded and paused turns, declined calls, usage of cut turns, repeated ids; ask_user/skill read cache, repeat count, Ctrl-C at CLI prompts; CRLF/BOM front matter, path rules, withheld folders, fd hosts | 6073507 | 323 tests then; Gemma live |
| Cost tracking phase 3: OpenRouter per-request reconciliation (re-checked at launch and by `cost reconcile`), `kurtkode cost check`, `kurtkode cost calibrate`; calibration 2026-10-16 on Haiku 5.5, Opus 5.5, Gemini 3 Flash, Haiku 4.5 via OpenRouter ($0.1124 in all); Claude via OpenRouter caches (COST_TRACKING_DESIGN.md "Status") | 0674922, afcf191, f24a88c, 3654a9c | 343 tests; comparison with the Anthropic and Google consoles still to do |
| Cost displays read the cost records (`CostEntry.spent`, `CostSummary`): toolbar total and tooltip, limits, Debug window (per turn, details, stats), Journal caption, Agents tab, CLI run line, JSON `cost_usd`/`list_price_usd`, `inspect`; summaries and retried attempts count; older sessions show none | 85b2c95 | 345 tests; checked in the app and `inspect` on the Opus calibration session (no spending) |
| Round 4 of the functional tests: plan (FUNCTIONAL_TESTS.md §18), six code reviews, probes (`Round4Tests.swift`), `spike/functest/pmock.py`, results and 29 findings | 0df1bd9 | FUNCTIONAL_TEST_RESULTS.md "Round 4" |
| Round 4 A fixes: atomic appends (`JSONLines`), command splitter fails closed (opaque commands), hook block, git Discard on conflicts, non-UTF-8 edits refused, quoted text calls ignored | fdeb4c6 | live: concurrent writers lose nothing; `bash -o pipefail -c 'git reset --hard'` refused |
| Round 4 B fixes: the limit reads cost records; loop (read cache, subagent errors, Stop); model replies (wall clock, stream errors, Gemini dropped calls, images); CRLF edits, slash templates; fork/subagent/replay costs, `DayFormat`; undo index, `-r` prefixes, repeated call ids | ce6dba1 | 382 tests; live: limit stops at $2.41; muse-glimmer regression passes |
| System prompt templates (session 11): the prompt's wording in `Prompts/*.md` (intro, mode, style-detailed, style-lean; a Mustache subset), overridden in `~/.kurtkode/prompts/` or a project's `.kurtkode/prompts/`; styles are names; Settings → Prompts (edit, Reset to Default, New Style); `kurtkode prompts`; eval `--prompt-dir` (SYSTEM_PROMPT.md) | b2faaa9 | 390 tests; defaults render the old prompt byte for byte (288 combinations); app tab checked in a test instance |
| Subagent routing P1, judging (session 11): task card on `task`; grounded checks (citations in 3 forms, changes, verify exit, hard failures) shown to the parent; `judgment` records (every one kept); `rate_task` plus an end-of-run rating side loop that is not part of the conversation; `checkedConfirmed`; grader for importance high (Settings); Agents tab Rate menu; `kurtkode judge`, `kurtkode judgments`, `runs` columns (SUBAGENT_ROUTING_DESIGN.md "P1 as built") | 054cae1 | 400 tests; live on bang's qwen3.5-9b: 3 of 4 "I checked" ratings were unconfirmed |
| Subagent routing P2 (session 11): `delegation.md` in the styles when subagents are on (prompt key `|sub`); `tool-task.md`, `tool-rate-task.md`; loop advice to delegate broad reading (`note-delegate.md`, Settings toggle); `ratingSideLoop` shared with the eval; task bank (16 tasks, gold checks validated by `TaskBankTests`); `kurtkode-eval --bank --judges --judge-paths --degrade`, calibration table; `--subagents on|off|both`; `survey` scenario (meeting notes); results in `eval-results/*-2026-10-24*` | ba06208 | 408 tests; bank on bang's qwen3.5-9b 16/16; it never delegated in 6 survey runs; degraded copies: grader caught 54%, parent 44%, no false alarms |
| After P2: the rating side loop may run a task's `verify` exactly; each task's check re-runs at the end of the parent's run as a grounded `recheck` judgment (a failure is a hard failure); tighter rubric (SUBAGENT_ROUTING_DESIGN.md "After P2", "Then"); results in `eval-results/bank-degrade-{verify,recheck}-*` | 1c4db7a | 413 tests; degraded bank: parent caught 82% of known failures (was 40–44%), 7% false alarms |
| Evaluation (EVAL_PLAN.md, EVAL_RESULTS.md): record once, judge many (`--record`, `--judge`, `--report`, `--regold`, `--sample`, `--rejudge-missing`, `--parallel`); 34-task bank with gold tested on right, idle, wrong and stray outcomes; 7 degradations; Wilson CIs and kappa; delegation scenarios (`--scenarios delegation`); fixes from the runs: three gold bugs, missing-verdict causes (rate-now nudge, grader 8k tokens, Gemma 4 text calls), reasons kept for no-verdict judgments | 04a992e | 420 tests; ~$30 of Gemini at list price; run store `eval-results/runs/bank1` (59 MB, on disk only: gitignored) |
| Cost-floor testing (COST_FLOOR_PLAN.md, COST_FLOOR_RESULTS.md, session 11): hard tier of 14 tasks (`--bank hard`, `TaskBankHard.swift`, gold tested on right/idle/trap/stray); OpenRouter `data_collection: deny` + `require_parameters` (`--no-train`), `#off` reasoning configurations, `--models-file`, `--models-at-once`, `--stop-after-failures`, infra failures classified and retried, `--subagent-model`/`--force-delegation`, `--own-cost`, `--key-limit`; frontier and floor tables in reports; 8 gold bugs found by real runs and fixed with regression tests; `spike/costfloor_*.py`, `spike/regold_by_task.sh` | this commit (after 04a992e) | $83.22 of $185 on OpenRouter; ~26,000 runs in `eval-results/runs/cf*` (gitignored); paid runs used the release binary in `AgentCore/.build-cf/` (Keychain allowed for it) |
| Built-in skills (session 12): the skill library (skilllib/: 30 tested skills, research, taxonomy, harness) ships as the `BuiltinSkills` resource, the last skill folder (project and user skills replace them by name); `Prompts/skills.md` tells the model to check them first when the skill tool is offered; Settings → Generation → Agent → "Built-in skills", `--no-builtin-skills`; `/skills` marks them (built-in) | this commit (after 75cb5ec) | 429 tests (5 new in BuiltinSkillTests); Flash trigger recall 90% with nothing installed (66% before), Qwen 3.5 9B 10% (skilllib/RESULTS.md) |
| Skill router (session 12): `SkillRouter` asks the session's model which skill fits each new request (template `router-skill.md`, no tools, no thinking, cost purpose `routing`) and sends that skill's instructions in a context note; Settings → Generation → Agent → "Skill router" (auto = OpenAI-compatible servers), `--skill-router`; `skilllib/eval/router_experiment.py`, `cache_check.py` | this commit (after 75cb5ec) | 436 tests (SkillRouterTests, a CLI test); Qwen 3.5 9B trigger recall 10% → 94%, tasks 2/31 → 10/31 (skilllib/RESULTS.md) |
| Phase 0 of GAP_ANALYSIS.md (session 13, Opus 5.5): output budget scaled to context, cut-off calls refused with the reason, overflow retry reset, parallel reads, saved bash output readable, `.git` write guard, compound allow rules, OpenAI `max_completion_tokens`, Claude Code agent tool names and model aliases, router skips acknowledgements, price-table age warning, session lock; cut command output lists the hidden error lines | this commit | 455 tests; CLI live on a mock and on Gemma 4 26B (GAP_ANALYSIS.md "Phase 0 as built") |
| Phase 1 B4 (session 14): grep runs a bundled ripgrep 15.2.0 (`Bin/rg` resource; `KURTKODE_RG`), withheld and denied files filtered before it; `output_mode` content/files_with_matches/count, context lines, multiline, `type`, `head_limit`/`offset`; built-in engine with the same modes as the fallback; glob newest first; eval scenario `warn-count` (GAP_ANALYSIS.md "Phase 1 as built") | this commit | 467 tests; Gemma used count mode unprompted; warn-count 1/6 (5 fell for the trap) |
| Phase 1 B5 (session 14): `edit_file` `edits` array (all or none), loose second pass (trailing whitespace, then indentation, re-indented, only when unique), read before edit (`FileReads`, seeded per run from the history), `apply_patch` (V4A and unified diffs) offered by profile to GPT/Codex/gpt-oss (GAP_ANALYSIS.md "Phase 1 as built") | this commit | 476 tests; Gemma 3/3 on a rename-and-guard task; a path-inside-edits bug found live and fixed |
| Phase 1 B2 (session 14): `run_in_background` on bash with `bash_output` (wait) and `kill_shell`, jobs per session in `ShellState`; exported variables replayed after the login profile on later calls; timeout note says how to finish; `fix-build-and-ci` uses `tee` (GAP_ANALYSIS.md "Phase 1 as built") | this commit | 483 tests; Gemma ran a 150 s build in the background and waited with bash_output |
| Phase 1 B1 (session 14): `present_plan` with an app card and a CLI prompt (approve as Accept Edits or Full Auto switches the mode mid-run, revise, reject); a plan written as an answer is presented anyway; Plan mode runs read-only bash in a read-only sandbox (GAP_ANALYSIS.md "Phase 1 as built") | this commit | 493 tests; Gemma planned and carried out a change in the app and the CLI (via the fallback: it never called present_plan) |
| Phase 1 B6 (session 14): instruction files from `~/.claude/CLAUDE.md`, parent folders, `.claude/CLAUDE.md`, `CLAUDE.local.md`, `@imports` (5 deep), duplicates once, 32 KB each / 96 KB in all; subfolders' AGENTS.md/CLAUDE.md sent with the first result that touches their folder; project memory (`remember` tool, `# note`, `/memory`); eval scenario `nested-rules` (GAP_ANALYSIS.md "Phase 1 as built") | this commit | 497 tests; Gemma: nested rule followed, memory recalled in a new session; nested-rules 3/3 |
| Phase 1 B7 (session 14): sectioned compaction summary sized to the context; last test/build command and exit code in `SessionFacts`; normalized paths (GAP_ANALYSIS.md "Phase 1 as built") | this commit | 501 tests; long-doc on Gemma 2/2 with the new summaries |
| Phase 1 measured (session 14): bank + hard tier on Gemma before/after, 89/96 → 85/96 (noise; no tool errors), +740 input tokens a request | 85bae90 | GAP_ANALYSIS.md "Phase 1 on the task bank" |
| Round 5 of the functional tests (session 14): three reviews of Phase 1, 35 findings (10 A: Plan-mode escapes and sandbox, grep and @import secret leaks, apply_patch crash and partial writes, `.GIT`, silent remember), all probed (`Round5Tests.swift`) and fixed; reasoning-loop guard; eval `--skills builtin` | 1e10277, 2dc8550, 2c2a2dd, this commit | 537 tests; 19B.0–19B.11 pass |
| F7 leftovers: inspector tabs, `/compact` nothing new, `-p` refusals, hook line once, header model, Debug tabs, Git accessibility, slots | 45a17f6, fefe7c3, e58e01a, 7169756, c1919f0, 8bfc0c0, a151225, 671f4bc | done |

382 unit tests pass with 11 known issues (`make test`); the app and the CLI build with no warnings. Each feature's details,
measurements, and what testing found are in PLAN.md (sections named in this table's spirit: "Shared run setup", "Lost
replies: retry elsewhere", "Command line: line editing", "Extra folders and tools in chats", "Debugging tool use",
"The context journal", "Journal search and filters", "The model browser", "Compactions that don't shrink the prompt",
"Summaries without thinking", "Compaction leftovers", "Subagent management, phase 1" … "phase 5", "Debugging layers 3
and 4").

## What the product does now (one line each; details in PLAN.md)

- **Reaching outside**: `web_fetch` (any model; HTML as Markdown, PDFs as text, marked as data). Public addresses only,
  whatever a name resolves to; a redirect to another host stops and says so; asked about like a command, and in Full Auto
  when the sandbox's network is off, so it's no way around that setting; "always allow" is per domain, and rules take
  `WebFetch(domain:x)`. `read_file` reads PDFs (`pages`) and, for vision models, images, which follow the turn's results
  in a note of their own. `/btw` asks on the side, from a text transcript, with no tools, and isn't kept.
- **Agent**: read/list/glob/grep (grep on a bundled ripgrep, with count and files modes, context lines and paging;
  glob newest first), edit/write (several edits per call, a loose second pass, a file must be read before it's
  edited; `apply_patch` for GPT families), bash (exported variables carry over; `run_in_background` with
  `bash_output` and `kill_shell`), Plan mode (read-only bash; the plan is presented for approval, which switches the
  mode and carries on) (diff approvals, undo), bash (own process group, timeouts), todo list,
  compaction with tracked progress (planned first: it runs only if it saves a tenth of the limit, else answered tool
  outputs are trimmed, oldest first, until a quarter of the limit below the threshold, and not again until there's
  room or the session has grown a tenth of the limit (`trimForHeadroom`, `TrimGate`); the reply gets a note; Settings → Generation → Summaries "Let the model think" on by default), per-model history shaping and text-call recovery. A reply the server lost (empty,
  with output tokens) goes to another OpenRouter provider (`provider.ignore`), then the fallback model (Settings →
  Generation → Lost replies), then the nudge. Each reply records its provider. A stream cut mid-reply (no finish
  reason, no `[DONE]`) fails the turn with its partial text; its tool calls never run. A run that leaves its own todo
  list unfinished is asked once whether it's done.
- **Native APIs** (session 8): endpoint kinds Anthropic and Google Gemini (presets; saved as `kind: "openai"` + `api`
  so older builds keep the list). Each reply's content as returned (`ChatMessage.native`) goes back verbatim while it
  matches and the same model is asked: Claude's signed thinking blocks, Gemini's thought signatures. Claude 4.7+:
  adaptive thinking with summarized display, effort from `reasoning_effort`, `block_binding: drop_block` (history
  kurtkode rewrites), `fallbacks: "default"`, automatic `cache_control` (Settings → Generation → Prompt cache: an hour
  instead of five minutes). Usage records cache reads/writes and thinking tokens; cost at list price (`PriceList`,
  dated 2026-10-14) as "≈$… (list price)". Context from the model list, capped at 200k unless the profile says.
- **A session keeps its system prompt** across processes (recorded with the session; the date and git status, which
  come last in it, go in a `contextNote` message after the user's when they changed), so a resumed session reads
  its prefix from the server's cache.
- **Shared sessions**: the app and the CLI notice when the other appended to a session they have open
  (`SessionStore.changedElsewhere`) and reload it before the next message (the app also when a session is shown again,
  when it becomes active, and on the Debug window's Reload). Quitting the app or ending the CLI stops running commands'
  process groups (`RunningCommands.stopAll`) and MCP servers.
- **Folders**: a project, or a plain chat's working folder (Settings → Generation → Chats, default `~/kurtkode`, made when
  first needed), plus extra folders per session, read-only or read and write (the toolbar's folder button; new ones
  start read-only; CLI `--add-dir` / `--read-dir`). Accept Edits auto-approves edits in read-and-write folders too
  (the user chose that).
- **Permission modes**: Ask, Accept Edits, Plan (read-only), Full Auto. **Full Auto runs commands in a sandbox**
  (`sandbox-exec`: writes only in the project, temp dirs, and read-and-write folders; read-only folders denied even in
  /tmp; every writable root's `.git/hooks` and `.git/config` read-only; network off by default; blocked writes reported).
- **Composer**: slash commands (built-in, and Markdown in `.kurtkode/commands` or `.claude/commands`), `@path` mentions,
  `!command`, queued input that steers the running agent, images for vision models. Esc stops a run (a card that's
  asking keeps Esc for itself; the find bar too); ↑/↓ at the text's edge walk earlier prompts (`Session.prompts`,
  `PromptRecall`), and ↑ on an empty draft takes back what's queued. A paste of 800 characters or 12 lines becomes a
  token with a chip (`PastedText`; expanded when sent). `/` and `!` can be queued: messages go in at the next step,
  commands after the run, in order; `SlashCommands.answersWhileRunning` (help, context, agents, skills, memory) answer
  at once. What's being typed survives a queue draining.
- **Transcript**: replies that only read fold into one row (`TranscriptRow`, `ToolGroupRow`; "Read 3 files, searched 2
  times"); running tools show elapsed time, and a run of several turns its total; a todo strip above the composer while
  work is left; ⌘F find in the chat (`TranscriptSearch`, `FindMark`, ⌘G/⇧⌘G), tool output counting for its reply; a
  message's hover buttons and context menu: Copy, Fork, Rewind (`SessionStore.fork(_:before:title:)`: the request waits
  in the new chat's composer; files stay as they are). A session that stopped mid-run with no run record gets a banner
  with Continue (`Session.wasInterrupted`, not while the lock says it runs elsewhere). A long chat opens at its true
  end: see `ChatView`'s settling `.task`.
- **Sidebar**: waiting, running and unread badges (`SessionBadge`), search (⇧⌘F) by title and conversation
  (`SessionStore.search`, with a snippet), Fork in the row's menu. A chat whose first line doesn't make a title gets one
  from its own model after the first reply (`ChatTitle`; cost purpose `title`; Settings → Generation → Chats).
- **Models**: Models window (LM Studio server, memory, load/unload/reload with memory checks), endpoint presets and a
  test message in Settings, per-model profiles (with OpenRouter provider order / ignore / allow others).
- **Rendering**: prose by Textual; fenced code by our `CodeBlockView` (highlighted off the main thread). A reply's
  Markdown is cut into pieces (code blocks, prose before each heading), each piece a row of the transcript's lazy stack
  (`MarkdownPieces`; streaming replies split again only from their last piece, `MarkdownSplitCache`). Streaming updates
  at 10 Hz, slowing to 4 Hz as a reply grows from 8 KB to 32 KB; live output batched; the transcript follows the bottom
  by edge (`ScrollPosition`). `HangMonitor` logs main-thread stalls (Release ≥500 ms, Debug ≥250 ms). Accessibility
  names on the composer, toolbar readouts (buttons: context → inspector's Context tab, memory → Models window), Models
  and Agents rows, Journal controls.
- **Git panel** in the inspector: status, diffs, stage/unstage, discard, commit, the branch menu (switch, new), push and
  pull (`--ff-only`), a Pull Request link on GitHub and GitLab, stashes (new files too), Write Message (the chat's model,
  from the staged diff), and in a worktree Merge into the main checkout's branch (undone if it isn't clean).
- **Worktrees** (`Git/GitWorktrees.swift`): `<repo>/.worktrees/<name>` on `kk/<name>`, excluded in `.git/info/exclude`. App:
  the sidebar's branch button; a worktree's section menu removes it, saying what that would lose. CLI: `-w NAME`,
  `/worktrees`, `kurtkode worktree list|remove`. Subagents: `isolation: worktree` (task argument, or agent file): a
  worktree from the last commit, so it can write alongside others and run in the background; what it did is committed
  on `kk/task-…`, the worktree goes, and the report names the branch; nothing is merged.
- **Reasoning views** (session 8): a turn's **Steps** tab (thinking, text, calls, server events in server order; hidden
  thinking shown as such), shown vs billed reasoning (Steps, Timeline rows, stats strip), the Journal's dropped-thinking
  and why-not-sent statuses, the budget chart's cache line and cost caption, and effort sweeps (Replay sheet →
  "Compare effort levels", the Replays tab's table, `kurtkode replay --reasoning a,b,c|all`).
- **Debug window** (Window → Debug, ⌥⌘D), following the session selected in a main window (or a chosen one, read from
  its file without starting its MCP servers):
  - **Timeline**: turns with their tool calls, badges (lost, recovered, nudged, error, bad arguments), filters; a turn's
    Overview, Reasoning, Request (exact JSON sent), Response (raw stream), Diff (vs the previous request: why a prompt
    cache missed); a call's arguments, schema check, approval (who decided, how long it waited), notes, result.
  - **Journal**: the session as one blended stream (user turns, reasoning, tool uses, the system prompt where it changes,
    attachments, loop notes, compactions, model/mode/folder changes); a **context lens** on any turn (in the request /
    shortened / not sent and why / this turn / later); each entry's lifetime in the context; a per-turn budget chart
    (click to set the lens); "where did these values come from?" for tool calls; search (⌘F, ⌘G) and filters (kinds,
    tool, lens, turn range).
  - **Turn actions**: Replay… (same or another endpoint/model; temperature, reasoning, system prompt; list-price
    estimate from the server's public `/models`, read without the key; the reply streams, then a side-by-side
    comparison; saved in `<wire>/replays/`, listed in a Replays tab), Copy as cURL (key as `$KURTKODE_API_KEY`, remote
    only), Fork ▸ Before/After This Turn (opens the fork in the main window). A compaction lists its summary requests.
  - Recording (the wire log, on unless Settings → Generation → Debugging turns it off): each request and its raw
    response (compaction summary requests too, since 715e9dc), and an index of what each request's context held.
    Sessions from before 264a9b7 / 0f6d69b lack them.
- **MCP**: stdio and Streamable HTTP servers (bearer token in the Keychain), Claude Code's config format; project servers
  need approval once per exact command/URL. Server instructions reach the model once, marked as the server's; resources
  through `mcp_list_resources` and `mcp_read_resource`; Stop ends a call at once and tells the server; `readOnlyHint` only
  offers a tool in Plan mode, where it still asks, since it's the server's word.
- **Subagents**: a `task` tool; built-in `explore` and `general`; custom agents in `.kurtkode/agents` or `.claude/agents`
  (`model: endpoint|model` puts one on another server). Each run is a **child session** in `<session>.subagents/`
  (its own wire log, system prompt, end record), linked from the task result. **Parallel**: several task calls in one
  reply run at once within each model's slots (LM Studio: the loaded model's `--parallel`; other servers: Settings →
  Generation → Subagents, default 4); runs that can change things go one at a time; results in call order.
  **Background**: `background: true` (read-only agents only) returns at once; the report arrives later as a marked
  message and the loop waits for it before finishing. **Control**: the inspector's Agents tab (state incl. waiting
  for approval / for a slot, Stop one, Open in Debug), `/agents`; in the CLI the first Ctrl-C during a subagent
  stops only it. **Debug window**: a task call's Subagent section and "Open Subagent" (the run's own Timeline and
  Journal under a breadcrumb, followed live), subagent totals in the stats strip.
- **Hooks**: Claude Code's format (PreToolUse, PostToolUse, UserPromptSubmit, Stop, SessionStart, SubagentStop, PreCompact,
  Notification); project hooks need approval.
- **Safety**: permission rules from settings files in Claude Code's format (deny > ask > allow; a project's allow rules
  need approval once), matched through `ShellSplit` (quotes, escapes, comments, heredocs, `$( )`, backticks, `sh -c`,
  wrappers and paths); destructive commands asked in every mode (only an allow rule naming the danger skips it);
  three identical changing calls in a row are asked; macOS notifications when a run ends or waits. Since round 4 the
  splitter reads Unicode scalars, `$'…'`, `(( ))`, zsh precommands, `env -S`, shell options with values, here-string and
  heredoc scripts, `find -exec` bodies and git `-c alias`/command config; what it can't read (a computed command name,
  a shell on piped input, nesting past depth 4) is an **opaque** command: asked about in every mode, and it turns any
  deny/ask rule into a question. PreToolUse `decision: block` / `continue: false` deny the call.
- **Skills and questions**: SKILL.md folders (`.kurtkode/skills`, `.claude/skills`, `.agents/skills`, project first,
  then kurtkode's 30 built-in skills from `skilllib/`) loaded on demand by the `skill` tool, also `/name`; `/skills`.
  The system prompt says to check them before a task (`Prompts/skills.md`); Settings can turn built-ins off. `ask_user` (several questions at once since 2026-10-31, see "Start here"): a card in the app, a numbered prompt in
  the CLI, not offered to `-p` runs or subagents.
- **Cost tracking** (COST_TRACKING_DESIGN.md): a `cost` record per billed request (list price by component from the
  server's tokens, the charge where known, raw usage, request ids, purpose, run and agent, timing, input mix), a `run`
  record per agent run (setup, build, machine, task, totals, outcome, children, an empty `judgment`); subagents' in
  their child sessions, replays' in their replay records. CLI: `kurtkode runs [--csv|--json]`, `kurtkode cost check
  --day D`, `cost reconcile`, `cost calibrate -m E:M [--max-output N] [--yes]`. **Every cost shown reads the records**
  (`CostEntry.spent`: charge where known, else list price; `CostSummary`): toolbar, limits, Debug, Journal, Agents tab,
  CLI run line, JSON, `inspect`, so summaries and retried attempts count; older sessions show none. **The spending
  limit adds the same records** (since ce6dba1; before, only server-reported costs counted). `-p` JSON's `cost_usd`
  includes subagents (`subagents_cost_usd` apart); a fork's copied subagent runs aren't the fork's spending; a replay's
  checked cost goes back into its replay record.
- **Command line** `kurtkode`: `-p` one-shot (text/json/stream-json); interactive sessions on a live screen (a composer
  and status line drawn in place at the bottom, output scrolling above into the terminal's own scrollback; no alternate
  screen): type at any time, Enter queues during a run (messages at the next step, commands when it's done, ↑ takes one
  back), Esc stops, Shift-Tab changes the mode (after the run, if one is going), Ctrl-O shows the last tool's output,
  Ctrl-R searches history, Ctrl-V attaches a clipboard image, Tab and a list complete /commands and @paths, Ctrl-J,
  Alt-Enter or `\` start a line, Esc twice lists rewind points; rendered Markdown, an edit's diff, a command's last
  lines. `--plain`, or no terminal: libedit, line by line, as before. Shares the app's data and sessions; records the
  wire log too. `kurtkode endpoint list|add|remove`, `kurtkode doctor`. `kurtkode inspect | replay | export` read recorded sessions (below).

## How to build, test, run

```
cd ~/git/kurtkode
make test          # AgentCore, EvalKit, KurtkodeCLI tests (382, 11 known issues): cd AgentCore && swift test
make build         # xcodegen + xcodebuild Debug → build/DerivedData/Build/Products/Debug/kurtkode.app
make run           # build and open the app
make release       # optimized app without the debug hooks → build/DerivedData/Build/Products/Release/kurtkode.app
make install       # release, then copied to /Applications (refuses while kurtkode is running)
make cli           # release CLI → AgentCore/.build/release/kurtkode
make install-cli   # copies it to ~/.local/bin
```
The user runs `make install` / `make install-cli` themselves (quit the app first). Data, keys, and settings live
outside the app; each new build asks once more for Keychain access (ad-hoc signature).

- The `.xcodeproj` is generated from `project.yml` (XcodeGen) and is gitignored. Textual is pinned to 0.5.0.
- Tests spawn `/usr/bin/python3` for mock MCP servers and run real `sandbox-exec`; nothing else to install.
- Redirect `swift test` to a file and grep it: `swift test | head` gets SIGPIPE (signal 13) and looks like a crash.
- A Debug build keeps its code in `kurtkode.app/Contents/MacOS/kurtkode.debug.dylib`; the `kurtkode` stub's date
  doesn't change on rebuilds, so check the dylib to see whether a build took.

### Where things live

- App data `~/Library/Application Support/kurtkode/`: `endpoints.json`, `profiles.json`, `mcp-approvals.json`,
  `hook-approvals.json`, `cli-history.jsonl`, `sessions/<project>-<hash>/<uuid>.jsonl` (plain chats under `_chats/`)
  plus `<uuid>.checkpoints/` (undo), `<uuid>.outputs/` (full bash output; old subagent JSON transcripts), `<uuid>.images/`,
  `<uuid>.wire/<reply id>.json` (a request and its raw response) and `<uuid>.wire/index.jsonl` (each request's context),
  and `<uuid>.subagents/<run>.jsonl` with `<run>.wire/`, `<run>.outputs/` (subagent runs; never listed as sessions:
  listings look one level deep).
- Session records: header (a run's has `parent`, `parentCallID`, `agent`), message, title, model, retract,
  permissionMode, compaction, folders, subagentEnd, systemPrompt (runs only); each appended record has `at` (time).
  Unreadable lines are skipped, so new record types are safe for older builds. A user message delivering a
  background report has `subagentReport` (the run id).
- Preferences: defaults domain `org.mlcommons.kurt.kurtkode` (the CLI reads it too; `RunSettings` holds the run keys).
- Keychain: endpoint keys (service `org.mlcommons.kurt.kurtkode.endpoint`, account = endpoint UUID); MCP tokens
  (service `org.mlcommons.kurt.kurtkode.mcp`, account `server@host`).
- User config (none exists yet): `~/.kurtkode/AGENTS.md`, `mcp.json`, `settings.json` (hooks), `commands/`, `agents/`;
  Claude Code's `~/.claude/CLAUDE.md` is read too; project memory in `~/.kurtkode/memory/<project-key>/MEMORY.md` (B6).
- Project config: `AGENTS.md`/`CLAUDE.md`/`.claude/CLAUDE.md`/`CLAUDE.local.md` (and parent folders' AGENTS.md/CLAUDE.md;
  subfolders' are sent when first touched), `.mcp.json`, `.kurtkode/{settings.json,commands/,agents/}`, `.claude/…`.
- Logs: `log show --last 5m --predicate 'subsystem == "org.mlcommons.kurt.kurtkode"'` (category "hang" for stalls).

### Command line

```
kurtkode                                   # interactive, in the current folder (-C DIR for another)
kurtkode -p "prompt" [--output json]       # once; stdin is appended when piped
kurtkode -c | -r ID | --list-sessions      # continue, resume, list this project's sessions
kurtkode -m lmstudio:qwen/qwen3-coder-30b --mode auto --sandbox always --no-mcp --no-subagents
kurtkode --add-dir ~/notes --read-dir ~/refs   # extra folders (kept with the session)
kurtkode --endpoint mock=http://127.0.0.1:18090/v1 -m mock:mock   # a one-run endpoint (no key, not saved)
```
Ctrl-C stops a reply or a `!command` (during a subagent, the first Ctrl-C stops only the subagent; another within 2 s
stops everything); twice at an empty prompt quits (130). `/agents` lists the session's subagent runs; stream-json has
`subagent_started`, `subagent_finished`, `subagent_report`, `status`. Another server for one run:
`--endpoint lan=http://192.168.1.20:1234/v1`, and an agent file with `model: lan|qwen/qwen3.5-9b` (the user's saved
endpoint for that server is named "bang": `-m bang:qwen/qwen3.5-9b`).

```
kurtkode inspect [SESSION] [--run N] [--turn N] [--json]     # turns table, or one turn in full
kurtkode replay [SESSION] --turn N [-m ENDPOINT:MODEL] [--temperature T] [--reasoning none|low|medium|high|default] \
                [--system-file F] [--json]                    # send it again and compare; saved for the Debug window
kurtkode export [SESSION] [--format markdown|json] [-o FILE]
```
SESSION: an id prefix in any project, or "last" (default: the newest session in the folder, which may be a fork). Under `-p` actions needing approval are
refused with a note to the model; `--mode auto` lets it act. A pty test harness must keep reading the output, or
SIGINT arrives before readline has the line (PLAN.md "Command line: line editing").

### Driving the app without clicks (Debug builds only)

Accessibility isn't granted. **Run test instances beside the user's app with `open -n`**, and stop only instances whose
path contains `/build/` (`for p in $(pgrep -x kurtkode); do ps -o comm= -p $p | grep -q '/build/' && kill $p; done`).
Never kill `/Applications/kurtkode.app`. Find a test instance's windows by its pid (script below).

```
open -n --env KURTKODE_WORKSPACE=/path/to/project \     # omit for a plain chat
     --env KURTKODE_MODE=fullAuto \              # ask | acceptEdits | plan | fullAuto
     --env KURTKODE_AUTOSEND='the request' \     # also works for /commands and !commands
     [--env KURTKODE_AUTOAPPROVE=3] [--env KURTKODE_REWIND_AFTER=5] \
     [--env 'KURTKODE_MODEL=This Mac (LM Studio)|google/gemma-4-26b-a4b-qat'] \   # loads it if local and not loaded
     [--env 'KURTKODE_THEN_MODEL=…' --env 'KURTKODE_THEN_SEND=…'] [--env KURTKODE_IMAGE=/path.png] \
     [--env KURTKODE_CONTEXT_LIMIT=9000] \       # a small budget forces compactions
     [--env 'KURTKODE_DRAFT=/re'] [--env 'KURTKODE_QUEUE=more' --env KURTKODE_QUEUE_AFTER=2] \
     [--env KURTKODE_OPEN_WINDOW=models|settings|debug] [--env KURTKODE_SETTINGS_TAB=prompts|endpoints|sandbox|pool|mcp] \
     [--env KURTKODE_POOL_EDIT=new|2] \         # with the pool tab: open the entry editor on a new entry or entry 2
     [--env KURTKODE_MCP_APPROVE=1] [--env KURTKODE_EXTRA_ENDPOINT=Mock=http://127.0.0.1:18090/v1] \
     [--env KURTKODE_OPEN_SESSION=<uuid>] \      # show that session (and send AUTOSEND into it, if set)
     [--env KURTKODE_MD=textual|plain] \
     [--env KURTKODE_NO_KEYCHAIN=1] \          # read no API keys (no Keychain prompts; keyed endpoints fail)
     [--env KURTKODE_NO_NOTIFY=1] \            # post no notifications (test instances run in the background)
     [--env KURTKODE_KEYS=/path] \             # play keys at the composer (ComposerTextView, KeyScript); path.out has the draft
     [--env KURTKODE_PASTE_FILE=/path] \       # paste a file's text as ⌘V does, from a private pasteboard
     [--env KURTKODE_FORK=1] \                 # after the run, fork at its last request
     [--env KURTKODE_AUTOANSWER=2] \           # answer the model's ask_user card (option number or text)
     [--env KURTKODE_AUTOPLAN=edits] \         # decide on a plan card: edits | auto | reject | feedback text
     [--env KURTKODE_OPEN_SHEET=browser|profile|folders] \   # needs a session open; the panel activates the app
     [--env KURTKODE_FOLDERS=/path:rw,/path2:ro] \
     [--env KURTKODE_DEBUG_TURN=3 --env KURTKODE_DEBUG_TAB=overview|steps|request|response|diff] \   # Timeline
     [--env KURTKODE_DEBUG_MODE=journal --env KURTKODE_DEBUG_LENS=20 --env KURTKODE_DEBUG_SELECT=19] \    # Journal
     [--env KURTKODE_DEBUG_SEARCH=text --env KURTKODE_DEBUG_GROUPS=reasoning,tool] \
     [--env KURTKODE_DEBUG_SUBAGENT=1] [--env KURTKODE_DEBUG_CALL=1] \   # open the Nth run; select turn N's first call
     [--env KURTKODE_STOP_SUBAGENT_AFTER=10] \   # stop each subagent that long after it starts (as the Stop button)
     [--env 'KURTKODE_DEBUG_REPLAY=bang|qwen/qwen3.5-9b'] [--env KURTKODE_DEBUG_CURL=/path] \   # with DEBUG_TURN
     [--env KURTKODE_DEBUG_FORK=before|after] [--env 'KURTKODE_DEBUG_REPLAY_SHEET=Openrouter|model'] \   # once per launch
     build/DerivedData/Build/Products/Debug/kurtkode.app
```

- A plain-chat test changes `chatFolder` with `defaults write org.mlcommons.kurt.kurtkode chatFolder <scratch>`;
  delete it afterwards (the user's app shares the defaults).
- Screenshots: `screencapture -x -o -l <window id> out.png`; a popover is its own window (or part of the main one's
  capture once the app is active). Crop with PIL. The session JSONL is the best progress signal (the path has a space).
- Test sessions go to the Trash afterwards (`~/.Trash/kurtkode-test-*`), with their `.wire`/`.checkpoints` folders.
- **A fresh Debug build reading a key from the Keychain puts a prompt on the user's screen** (ad-hoc signature; seen
  in session 5). Don't make test builds read keys: use endpoints without keys (LM Studio, the LAN server), and keep
  key reads out of anything a test triggers. If a prompt appears, tell the user to click Deny; never touch it.
- Debug-window hooks that act (fork, replay) run once per launch: a fork opens the new session, the window follows
  it, and an every-load hook would fork again (session 5 made five nested forks that way).
- The inspector's tab and visibility are shared defaults (`showInspector`, `inspectorTab`): to screenshot the Agents tab,
  read their values, `defaults write` them for the test, and restore them after (session 5 did; the user's were
  `showInspector` false and no `inspectorTab`).
- Learned in session 6 (the functional test run):
  - **Find a launched instance by diffing PIDs before and after `open -n`.** PIDs wrap: "the highest kurtkode pid"
    once named another test's instance, which was then stopped by mistake. Never stop "every /build/ instance" while a
    long run is going; stop by PID.
  - Don't rebuild the Debug app while a test instance of it is waiting (on a Keychain prompt, say).
  - Wait for a run by matching its prompt text in the session file, not "the newest session": any other chat that
    finishes (another test, the user) ends the wait early.
  - `KURTKODE_DEBUG_GROUPS` takes each group's first word, lowercased: `tool`, `system`, `reasoning`, `loop`.
  - Inspector tab values are capitalized (`Todos`, `Changes`, `Agents`, `Git`, `Context`). The filesystem ignores case:
    `rm shots/x-todos.png` deletes `x-Todos.png`.
  - A test build that reads an endpoint key (OpenRouter) puts a Keychain prompt up, once per build; the user clicks Allow.
  - **Computer use works** (session 6, with the user's approval): the `app_*` tools act on `org.mlcommons.kurt.kurtkode`
    in the background (the installed and Debug apps share that bundle id). Pop-up and context menus (Fork, the Git
    tab's Discard) need full-screen control, which asks the user each time it's taken. Typing Return into the composer
    through accessibility inserts a newline; press the send button. The Git tab's per-file +/− isn't an accessible
    button (a press opens the row); Stage All / Unstage All are.

  - **Contact sheets of screenshots need borders between tiles**, and covered windows aren't fully redrawn by macOS:
    judge rendering from single frames of a visible window (F17 was a misreading of borderless sheets).
  - **Learned in session 7**: the background computer-use tools reach **one process per bundle id** (the Debug,
    PerfDD and installed apps share `org.mlcommons.kurt.kurtkode`): with two instances running they picked the other
    one, so drive one instance at a time. An instance launched with `open -n` takes focus and can catch the user's
    keystrokes: `kk.sh` now uses `open -n -g` (a hidden app's window needs `app_bring_to_current_space` before
    `app_screenshot`). Quit an instance by pid with `spike/functest/quitpid` (a real Quit). Sampling every stall feeds
    itself (each `sample` stalls the app): sample once per burst. `defaults import` merges: delete keys a test added.

- **`HOME` does not move kurtkode's data** (2026-10-30, found the hard way): Foundation's Application Support and home
  folders ignore it, so a test with only `HOME` set writes to the real sessions, snapshots, `cli-history.jsonl`,
  `endpoints.json` and `~/.kurtkode`. Use `CFFIXED_USER_HOME=/scratch`, and check it took (`kurtkode endpoint list`
  shows only This Mac). `spike/functest/cli/drive.py` refuses to start otherwise.
- **A test build with its own bundle id** (2026-10-30): build with `PRODUCT_BUNDLE_IDENTIFIER=org.mlcommons.kurt.kurtkode.friction`
  (or any other) and the background computer-use tools reach only it, beside the user's running app; preferences are its
  own too (delete them after: `defaults delete <id>`). Sessions are still the shared ones. Background keys go through
  accessibility (Return inserts a newline, Esc may not reach `keyDown`): use `KURTKODE_KEYS` for those. The skill router
  takes a request on OpenAI-compatible servers, so a scripted mock's first step answers it.

- **`KURTKODE_TRACE_BODIES=1`** (Debug builds; launch with `open --stdout FILE`): the main views print
  `Self._printChanges()` on each body run, to see what re-renders. The app's CPU time for one fixed mock stream
  (`ps -o cputime=`) is a far steadier measure than counting stalls (session 7: `soak.sh` logs it).

### Eval suite

```
cd ~/git/kurtkode/AgentCore && swift build -c release --product kurtkode-eval
AgentCore/.build/release/kurtkode-eval --list
AgentCore/.build/release/kurtkode-eval --models lmstudio:qwen/qwen3-coder-30b --scenarios all --trials 1 \
    --out eval-results/NAME.json --transcripts eval-results/NAME-transcripts [--max-cost 2] [--sandbox never]
AgentCore/.build/release/kurtkode-eval --switch 'lmstudio:A>openrouter:B' --scenarios fix-tests --switch-after 3
KURTKODE_SUMMARY_THINKING=0 AgentCore/.build/release/kurtkode-eval --no-load ...   # summaries without thinking
AgentCore/.build/release/kurtkode-eval --endpoint proxy=http://127.0.0.1:18080/v1 [--key-from openrouter] \
    --models proxy:MODEL [--fallback lmstudio:MODEL] [--providers-ignore A,B]
```

- Scenarios: `explain-repo`, `find-definition`, `fix-tests`, `long-doc` (16k context, forces compaction; a pass is
  13/14 files right), `deny-feedback`. Model specs are `endpointName:modelID`; `lmstudio` = this Mac.
- `spike/functest/pmock.py PORT SCRIPT.json LOG` (round 4): a **priced** mock. Reach it as `http://0.0.0.0:PORT/v1`
  (not 127.0.0.1): it then counts as a remote server and its replies are priced from its `/models` (OpenRouter format),
  so cost tracking and spending limits can be tested with no key. Script steps: `text`, `bash`, `tool`+`args`, `calls`,
  `usage`, `status`, `drop`, `sleep` (README in `spike/functest/`).
- `spike/fault_proxy.py`: drops large write calls. Imitated providers: `--providers Flaky,Solid --faulty Flaky`. In
  front of OpenRouter: `--upstream https://openrouter.ai/api/v1 --faulty <real provider names>` with the eval's
  `--key-from openrouter` (the eval reads the key; it never appears in commands). Run scripts in `eval-results/run-*.sh`.
- Keys: `KURTKODE_API_KEY_<ENDPOINT>`, else the app's Keychain entry. **Never take or pass keys as arguments.** Each
  rebuild of a binary changes its signature, so the user is asked again for Keychain access: batch paid runs.

## Architecture map

```
AgentCore/Sources/AgentCore/
  LLM/        ChatTypes (ChatMessage: meta incl. provider/notes/rawContent/retryRequests, toolResult incl. approval/
              argumentProblems/notes, userCommand, images), WireFormat (provider routing, reasoning, cost), ChatClient
              (SSE, retries, optional WireTap; per-API path, headers, encoder, StreamDecoder), Turn (limits, repetition),
              TextToolCalls, Images, AnthropicWire, GeminiWire (native requests and stream decoders), PriceList
              (per-component rates, version), CostEntry (CostEntry, CostBreakdown, PriceLookup, RemotePrices, CostScope,
              CostSink, Reconciliation, CostReconciler, CostSummary), RateLimits
  Agent/      AgentLoop (loop, approvals with records, hooks, queued input, lost replies retried elsewhere, nudges,
              turn notes, wire log and context index), SessionRun (RunSettings, ModelRef, TurnKey, FrozenSystemPrompt:
              shared by app and CLI), Context (budget, compaction, facts), Permissions, SystemPrompt (folders, chat
              variant), Subagents (TaskTool with background, runSubagent, SubagentRecorder/Control/Limiter,
              BackgroundRuns, SubagentInfo/Progress), ProgressRelay, PermissionRules (settings files, approvals),
              DangerousCommands, ShellSplit (commands in a shell line, unwrapped), Skills (SKILL.md, SkillTool),
              AskUser (UserQuestion, AskUserTool), RunRecord (AgentRunRecord, BuildInfo, MachineInfo, LocalModelInfo,
              RunTracker), CostMeter (limits)
  Models/     ModelProfile (incl. ProviderRouting), HistoryShape, family table, HistoryShaper
  Tools/      read/list/glob/grep, edit/write, bash, todo, Workspace (root + ExtraFolder list, canonical paths), Sandbox
  Commands/   SlashCommands, Mentions, UserShell;  MCP/  config, clients, transports, hub;  Hooks/;  Git/
  Session/    SessionStore (JSONL records with times; Session.folders, .events, .costs, .runs; costEntries(),
              runRecords()), Fork, Checkpoints
  LMStudio/, Endpoints/
  Debug/      WireLog (WireTap, WireRecord, ContextRef/ContextSnapshot index, ApprovalRecord, ArgumentCheck),
              SessionTimeline (items, stats, WireDiff), SessionJournal (entries, lens statuses, lifetimes, budget,
              provenance, Filter/search), SubagentRuns (SubagentRunSummary, subagent totals), Replay (options, run,
              compare, curl, saved replays, effort levels and sweeps), Export (Markdown, JSON), ReplySteps (steps in
              server order, ReasoningShown)
AgentCore/Sources/EvalKit/, kurtkode-eval/main.swift
AgentCore/Sources/KurtkodeCLI/    AppSettings, CLIOptions, CLISession, Renderer, LineEditor (libedit), DebugCommands
                                  (inspect, replay, export, runs, cost check/reconcile/calibrate)
AgentCore/Sources/CEditLine/      module map + C shim for libedit;   AgentCore/Sources/kurtkode/main.swift
App/Sources/Model/   AppModel (endpoints, catalogs, profiles, loading, MCP hubs, lastSelectedSession, existingController),
                     ChatController (one session; folders; chat working folder), HangMonitor, ModelCatalog, Preferences
App/Sources/Views/   RootView, ChatView (FoldersButton/FoldersPanel), MessageView, ToolViews, ApprovalViews, InspectorView,
                     ModelsView, StatusViews (model picker, ModelBrowser, ProfileEditor), SettingsView (Generation incl.
                     Chats/Debugging/Lost replies/Subagents), DebugView (Timeline, drill-in), JournalView, MarkdownView,
                     CodeHighlighter, ComposerTextView, SubagentViews (Subagent section, Agents tab, report card,
                     DebugFocus, chatSessionID), ReplayViews (ReplaySheet, ReplayComparisonView, ReplaysList,
                     EffortTableView), ReplyStepsView (the Steps tab)
spike/               fault_proxy.py, mock_stream_server.py, Phase 0 probes
```

Both `ChatController.generate` and `CLISession.run` build runs with `SessionRun`: put new run settings there.

### Measuring freezes

`spike/mock_stream_server.py --text reply.md --tps 110 [--bash CMD]` streams a fixed reply with no model loaded (point
the app at it with KURTKODE_EXTRA_ENDPOINT and `KURTKODE_MODEL=Mock|mock`). Optimized with hooks: `xcodebuild -project
kurtkode.xcodeproj -scheme kurtkode -configuration Release SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG -derivedDataPath
build/PerfDD -quiet build`. Stalls: `HangMonitor` (category "hang"); `sample` shows where time goes (it inflates stalls).

## Hard-won facts (don't relearn these)

**LM Studio**
- Listens on **127.0.0.1 only**. **Silently substitutes models** for unknown ids (the app warns).
- Load explicitly (`lms load <id> --context-length N --parallel 1 -y`); an on-demand load gets a small context (8k) and
  4 slots. **The user loads models themselves too** (seen: Gemma 4 26B at 262k / 4 slots / 1 h TTL): check `lms ps`.
- **Prompt cache**: 24k tokens re-processed took 122 s, cached 0.5 s (the Journal/Timeline show first-token times).
  The server log's "Prompt cache restore: cached_tokens=…" line says whether a request hit it.
- **`reasoning_effort: "none"`** turns Gemma 4's thinking off (the only switch of six that worked), but **with tools in
  the request it loses the whole prompt cache** (the template renders the prompt's start differently). Gemma 4 26B
  thinks ~45 tokens/s and can spend a whole 1,500-token summary budget thinking.
- **The eval loads and unloads models itself unless `--no-load`**; with a model the user loaded, always pass it.
  A local model's context is the loaded one (`min(loaded, scenario cap)`; long-doc caps at 16k).
- MLX memory grows at inference; reloading frees it. Server logs: `~/.cache/lm-studio/server-logs/<yyyy-mm>/*.log`.
- Its server once stopped cleanly mid-run ("Server stopped.", cause unknown); don't restart it without asking.

**OpenRouter**
- `/models` and `/models/<id>/endpoints` are public (providers, prices, tools); `/key` gives usage; chunks carry
  `provider`; streamed usage has `cost` (can be several times list price).
- Providers drop tool calls (empty reply with output tokens) in ways no nudge fixes; `provider.ignore` is honored
  (gpt-oss-120b moved AkashML → DeepInfra → Crusoe). A listed provider can be dead: qwen3-coder-30b-a3b's Amazon
  Bedrock answers HTTP 500 whenever SiliconFlow is ignored. `:free` models are rate-limited.

**Sandbox (`sandbox-exec`)**
- Paths must be realpath-resolved (`/private/var/folders`); `URL.resolvingSymlinksInPath` drops `/private` (and only for
  paths that exist: `Workspace.canonical` spells /tmp, /var, /etc the short way for new files too).
- Temp dirs are always writable; read-only folders need explicit deny rules. Tag denies `(with message "tag")`.
- Sandboxes don't nest (`swift build` needs `--disable-sandbox` inside one). `(deny network*)` blocks Unix sockets too.

**MCP / hooks / CLI**
- A Finder-started app lacks the shell's PATH: servers and hooks run with `zsh -ilc`'s PATH. The first request must
  wait for a project's MCP hub. Test HTTP servers must read a request's body before refusing it.
- `-p` must not wait on an open, silent stdin (0.5 s poll). Qwen3-Coder re-sends a subagent task unless told it's final.
- Small local models garble long absolute paths (Qwen dropped the leading "/" of a /private/tmp/… path).

**Rendering and SwiftUI**
- Code blocks are ours (`CodeBlockView`, highlighted off-main); throttle transcript updates (10 Hz, batched output).
- **No `.searchable` in a sheet** (focus loop with the input method over XPC; 61 s stalls). A stall full of
  "activating connection: … (anonymous)" pairs is XPC inside a layout loop; `sample` shows the view.
- `List`/`ForEach` ids must be unique. Long text belongs in an NSTextView (`PlainTextView`), not `Text`.
- The type checker gives up on big Chart/Grid builders ("unable to type-check… in reasonable time"): build rows/segments
  in helpers. View builders can't hold `var` statements. A popover in an inactive app closes at once.
- libedit's readline moves a prompt's escape sequences: keep the CLI prompt plain.

**Swift, tests, macOS**
- Ad-hoc signing: each rebuild re-prompts for Keychain access. Never read the Keychain in a view body.
- Timing-dependent tests that fail now and then under a full parallel run, and pass alone: `cancellationKeepsPartialOutput`,
  `aServerThatExitsIsMarkedFailedUntilRestarted` (stderr captured after the exit is seen). Rerun before suspecting a change.
- Swift Testing: `#expect` can't call mutating methods, and `#require` can't nest; take values out first. Raw strings
  containing `"#` need `##"…"##`. Python edits of Swift with `"""` need `'''`; heredocs with `\u{…}` need `<<'EOF'`.
- Generated `Codable` doesn't apply default values for missing keys (`SandboxPolicy` is never decoded, so it's fine).
- Actor `let` properties used from outside need `nonisolated`.
- `URLSession.AsyncBytes.lines` drops blank lines (SSE events end per `data:` line).

**Subagents (measured)**
- `lms ps --json` gives each loaded model's `parallel` slots. With one slot, two parallel runs take turns (the
  limiter holds the second; otherwise LM Studio would queue it and its time limit could trip).
- Gemma 4 26B makes two `task` calls in one reply when asked, and uses `background: true`; while waiting for a
  background report it sometimes does the same search itself.
- Events from parallel subagents arrive concurrently: anything that records them needs a lock (the first parallel
  tests were flaky until they did).
- Small models read "record count" as a file's line count when the main agent's task prompt is vague.

**Agent behavior (measured)**
- Step limit 100. Models describe unread files from their names (the prompt forbids it). One turn may return ≤35% of the
  context. "grep first" cut a lookup from 11 calls to 3. In an 8k context with ~2.4k-token file reads every read crosses
  the threshold: one compaction per file, and Gemma garbles more (PLAN.md "Compactions that don't shrink the prompt").

**Anthropic and Gemini (session 8, measured)**
- A pasted key can carry a line break: URLSession then drops the header and Anthropic answers 401 "x-api-key header is
  required" with a key stored (keys are trimmed now). Keyless requests are a free check of paths and headers.
- Claude's thinking is bound to its conversation: any change before a block (compaction, a trimmed output, another
  system prompt) and the server drops it (`input_transformations`, `prefix_binding_mismatch`, recorded as a note).
  Another model never reads it. Opus 5.5 at default effort often doesn't think at all on easy turns.
- Effort isn't monotonic on one sample (Haiku: high thought less than medium); every level answered the cobalt count
  right; Opus max cost 3× low for the same answer.
- Prompt caching works as documented: each turn reads the whole previous prompt, writes only the new part (5-minute
  and 1-hour writes both seen). Gemini's implicit cache is best effort (hit on 2 of 4 eligible turns) and needs 4,096
  prompt tokens on 3.x; kurtkode's own prompt is ~2.1k. A different effort level voids Claude's cached history.
- A rebuilt binary reading a Keychain key puts a prompt on the user's screen (one per key per build); test instances
  use `KURTKODE_NO_KEYCHAIN=1`, and tests run on LM Studio unless a keyed run is needed (ask, batch them).

**Round 4** (session 10)
- **An interactive CLI start reads Keychain keys** (the launch-time OpenRouter reconciler): on a freshly built binary
  that puts a prompt on the user's screen (it happened in 18B.10). Test the CLI with `-p` (no reconciler), or not at
  all on a new build; the CLI has no `KURTKODE_NO_KEYCHAIN` yet.
- **Shared JSON Lines files take `JSONLines.append`** (`flock` + `O_APPEND`) or `JSONLines.rewrite` (in place, same
  lock): a seek to the end and a write lost records whenever two writers met (two CLI runs, app and CLI, the
  reconciler beside a turn; one CLI process had two stores). Session files, the wire index and the checkpoint index
  use them.
- **Swift Characters aren't shell bytes**: `"\r\n"` and a quote followed by a combining mark are one Character each;
  parse shell text by Unicode scalars, count lines by UTF-8 bytes.
- **Probes that would hang or crash the runner** go behind `.timeLimit` or a smaller size, and a "known issue" block
  must hold only expectations that fail (a passing one inside it is "Known issue was not recorded").
- **Separate commits that each pass**: build the earlier one in a temporary `git worktree` (its own `.build`, a few
  minutes), then `git update-ref refs/heads/main NEW OLD` and `git reset` in the checkout.
- The code reviews were six parallel read-only subagents, one per area, asked for traced candidates with a probe each;
  about half of what they reported was confirmed by a probe, the rest is listed as traced-not-probed.

**Costs and providers** (session 9)
- **OpenRouter's generation records lag by minutes**: none was there within 10 s of the reply; one of three after ten
  minutes, the rest later. The end-of-run lookup is a first try; `CostReconciler` (launch, `cost reconcile`) gets them.
- **Claude through OpenRouter caches only what's marked**: `cache_control` on content parts (system prompt, last user
  or tool message). Unmarked, every repeat paid full input ($0.0095 vs $0.0010 for a 9.5k-token prompt).
- **Token estimates are rough**: bytes/3.3 said 9.3k for a prompt Claude counts as 13.4k and Gemini as 7.2k. Costs use
  the servers' counts; only estimates (like `calibrate`'s) are off.
- **List price is the comparison basis** (the user's decision), not what an account was charged (free tiers, credits,
  OpenRouter's provider choice). Local models are timed, never priced. **Displays** show `CostEntry.spent` (the
  charge where known, else list price with ≈): one rule for every number on screen.
- **Checking an install**: `make install` copies with `ditto`, which keeps the build product's dates, so file dates
  say when it was built, not installed. Grep the installed executable for a string the newest code added (Swift keeps
  literals over 15 bytes as plain UTF-8; shorter ones are inline and can't be found that way).
- **`Renderer.apply` runs under the renderer's lock**: don't take it again inside (a nested `withLock` hung the suite).
- **Round 3's pattern**: a test that exposes a bug is written as `withKnownIssue` and becomes a plain test with the fix;
  a test that would trap is `.disabled` until fixed.
- **Ctrl-C at a libedit prompt**: SIGINT is ignored there (a dispatch source handles it) and `readline` keeps
  blocking; ending the read needs a newline pushed into the terminal (`TIOCSTI`, `kk_push_newline`).

**Phase 3** (session 16)
- **Shadow snapshots** (`Session/Snapshots.swift`): a bare repository with `GIT_DIR` + `GIT_WORK_TREE` and one
  `GIT_INDEX_FILE` per session works for any folder. Its `info/attributes` must turn the project's filters off
  (`* -text -filter -ident -eol`) or LFS/eol conversions run on the way in only; **not `-diff`**, which makes every
  file "binary" in diffs. Keep the user's config out (`GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`).
  `update-index` removals before additions (a file that became a folder otherwise breaks the session's index). The
  default APFS volume is case-insensitive: delete before writing when restoring a case-only rename. A snapshot takes
  ~0.2 s after the first (1–2 s).
- **"Surely hosted" vs "surely local"**: `Endpoint.isCloudAPI` (a list of known hosted APIs) and `!isThirdParty`
  (this Mac or a recognizable LAN name) are different tests; anything between (Azure, a cloud VM, `studio`) is
  unknown. Privacy rules use `!isThirdParty` for local; hosted-only features use `isCloudAPI`.
- **Forcing a tool call**: OpenRouter and OpenAI take OpenAI's named `tool_choice`; Gemini takes
  `functionCallingConfig` mode `ANY` with allowed names; Claude refuses a forced choice with thinking on (the newest
  models can't turn it off), and an assistant turn with a tool call but no thinking block breaks its next request.
  **LM Studio rejects a named `tool_choice`** ("none, auto, required" only), and with "required" qwen3-coder-30b still
  answered in text.
- **The turn's tool-output budget is 35% of the context** (`turnBudget`); in a test context under ~1,800 tokens every
  call is refused ("not run: … as much as fits"). Use 4,000+ in tests that need calls to run.
- **`-m` needs a name the CLI knows** (`lmstudio:` or a saved endpoint's name; "This Mac" now works): an unknown
  prefix falls through to the default endpoint, here Anthropic, and reads its key. `KURTKODE_NO_KEYCHAIN=1` now works
  in the CLI too; the interactive CLI with it reads no key.
- **Local judges are slow on long tasks**: qwen3-coder-30b's parent-path judgments of the hard tier's log tasks took
  minutes each (88 of 140 runs in 3 hours, sharing the one slot). Budget local judge runs by task, or stop and use the
  judged subset (`--trigger-sim` scores a judge only over the runs it judged).
- **Three independent read-only review agents** (one per area: snapshots/rewind; review/escalation; delegation and
  integration) found 37 issues in Phase 3, most verified; the withheld-files leak was found by all three.
- See COST_ARCHITECTURE.md "Lessons" for what was learned about cost (detectors, cascades, delegation, benchmarks).

**The real task set** (session 17, the cost audit's P2)
- `--bank real` reads `eval-results/real-fixtures/tasks.json` (fixtures are `.tgz` snapshots of responsedigger at the
  commit before a feature, with the feature's tests); the tests need `~/.pyenv/versions/airr/bin/python` and
  `PYTHONPATH=src`; gold = the suite passes, no test line removed, only `src/`, `tests/`, docs changed.
- **The sandbox breaks tests that signal child processes** (responsedigger's four Ctrl-C/stop tests): models see them
  fail, gold (unsandboxed `shell()`) sees them pass, and the after-run re-check inherits the failures. The real fixtures
  now carry a root `conftest.py` that skips those four; with it the re-check agreed with gold on all 12 P2b runs.
- **OpenRouter replies are capped at 4,096 output tokens in bank runs** (`TurnLimits` in `recordBank`); a reply cut
  mid-call three times ends the run as "truncated". Real-sized edits hit it (12 of 72 runs); at `--max-tokens 16384`
  none of the 12 re-runs was truncated (3 passed).
- `--max-cost` is checked before a run starts: with `--parallel-remote 3` and $1.9 Sonnet runs, a $4.50 cap ended at
  $7.80. Size caps for the dearest model's run, or run it with `--parallel-remote 1`.
- `--regold SET` re-runs every task's check sequentially (72 runs ≈ 45 min here) and rewrites only runs whose gold
  changed; it prints nothing until the end.
- The eval priced deepseek-v4-flash-0731 at ≈3× its charge all evening (the stale listing of COST_AUDIT.md F5); read
  `runRecord.totals.charged` for it.

## Working conventions with this user

- **Commit only when asked**; when asked for separate commits, make each build and pass tests on its own (a temporary
  worktree on a branch, then move `main` with `git update-ref` and `git reset` — the working tree must match).
- End each piece with a plain report (tables welcome) and a question; frame decisions as options with a recommendation.
- **The user uses the installed app and LM Studio while you work.**
  - Stop only `/build/` app instances; launch tests with `open -n`. (Session 4 once quit their app by accident.)
  - **Never `lms unload --all`.** Check `lms ps`; unload only models you loaded, by name. (Session 4 cut off their Gemma
    reply that way; LM Studio reloaded it on demand at 8k / 4 slots.) When they say a model is loaded for you, use it as
    it is: no load, no unload. Prefer the model they name (they asked for Gemma 4 26B over Qwen3-Coder for tests).
  - If LM Studio's server stops, they may have stopped it: ask before restarting.
- **Watch free RAM** with models loaded (alert below 25%; it hit 22% once when builds ran beside an eval: don't).
- **Ask before downloading** anything, and before spending on OpenRouter, Anthropic or Gemini (models, trials, estimate,
  cap); a change of model is a new ask, and a cap covers the runs it was given for, not later checks. Spent so far:
  about $0.68 on OpenRouter, $1.07 on Anthropic and Gemini (session 9: $0.1124 of calibration, a $0.15 cap; the user's
  existing keys, which they approved for calibration instead of dedicated ones).
- **Cost data decisions** (COST_TRACKING_DESIGN.md "Decisions"): models are compared on list price; local models are
  timed, not priced; delegation (writing the task, reading the report) is the parent's cost; both the run and the
  session are units; no work on sessions from before the records existed. Read deny rules cover the file tools only
  (the user declined covering bash).
- **Test on the local LM Studio** (or recorded sessions, mocks) rather than keyed APIs: each rebuilt binary that reads
  a Keychain key prompts the user. Debug test instances get `KURTKODE_NO_KEYCHAIN=1`.
- **Never handle API keys or tokens**; they enter them in Settings (Keychain).
- They report problems tersely; measure first (hang log, CPU, sample, a replay), report before/after numbers.
- Keep waits short and fail fast; background long runs and report partial results.
- `make install` / `make install-cli` are theirs (quit the app first). Other Claude sessions may touch this repo:
  read uncommitted changes you didn't make before acting.

## Scratch tools (the session-6 set is saved in `spike/functest/`; recreate others as needed)

- Windows of one process, for screenshots (`swift winnames.swift <pid>`):
  ```swift
  import CoreGraphics
  let pid = Int(CommandLine.arguments[1])!
  let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
  for w in l where (w[kCGWindowOwnerPID as String] as? Int) == pid { print(w[kCGWindowNumber as String]!, w[kCGWindowName as String] ?? "-") }
  ```
- Waiting for a run: poll the newest session JSONL until the last assistant message has text and no tool calls.
- Demo projects: make them in the scratchpad (git init; small files with unguessable facts). The journal test used 8
  Python files with a class and a "keeps N records" docstring each, `KURTKODE_CONTEXT_LIMIT=9000`, Full Auto.
- pty driving of the CLI: Python `pty.fork`, write keys, keep reading (`select`), check `waitpid`.

## Starting Phase 3 (written at the end of session 15)

- **What Phase 3 is** (GAP_ANALYSIS.md Part 3, row 3; Theme A A4, A6, A7 and Theme C C1, C3): C1 a git-based net diff
  of a task with revert; A6 cross-vendor review (`/review`, automatic for `importance: high`); A4 a cheap-first cascade
  for the main agent, **advisory first** (decision 2: a one-click "Escalate to X for ≈$Y" card; automatic only after
  trigger precision is measured); A7 kurtkode-initiated delegation; C3 rewind options. Measure: cheap-first against
  frontier-alone on the bank, hard tier and delegation scenarios (cost per success, wall time, escalation precision);
  the reviewer's catch rate on the degraded-run store (`eval-results/runs/bank1`, with `--degrade` copies).
- **What Phase 2 found that shapes it**: hard failures barely detect cheap models' failures (the retry replay: 1 of
  ling's 9 bank failures), so A4's escalation triggers should lean on the card's `verify` check, the re-run check, the
  judges' verdicts, and A3's signals (last check failed, unfinished todos), not on hard failures. Measure triggers
  offline first, as `kurtkode-eval --retry-sim` did: stored runs carry their checks, fixtures and transcripts.
  Delegation through the pool halves a run's cost at the same pass rate (12/15 both; Haiku parent), so A7 has room.
- **Building blocks already there**: `ModelPool` (tiers, roles incl. `reviewer`, `pick`, `next`), `SubagentRouting`
  (hosted-only rule, `Endpoint.isCloudAPI`), `Spending.whatIf`, `RunSignals`, `MainRunJudgments`, the grader path
  (`JudgeCalibration.grade`), `CheckpointStore` (per-turn undo), `kurtkode-eval --subagent-pool [both]`,
  `--force-delegation`, `--retry-sim`, `kurtkode cost report --eval`.
- **Ways of working the user set**: one item at a time, unit tests, full suite, a live check on Gemma 4 26B in LM Studio
  (load at 32k, `--parallel 1`, only if nothing is loaded; unload after; never touch a model the user loaded); ask before
  downloading anything and before any paid API run, with a cost estimate and a `--max-cost`; **warn before a Keychain
  prompt** (the user must click Allow; nothing runs until then) and use one process per paid run so there's one prompt;
  commit each item separately; keep GAP_ANALYSIS.md and HANDOFF.md current; end the phase with a functional-test round
  (three independent reviews, probes as tests, FUNCTIONAL_TESTS.md §21 / Round 7). Don't propose trimming skills or tool
  descriptions for prompt size (the user's call, 2026-10-26). Test sessions go to `~/.Trash/kurtkode-test-*`; pmock runs
  record fake spending in the user's session store, so trash them.

## Next steps

- **After 2026-11-06**: the three newest "Start here" paragraphs at the top have the state and what's open. Cost:
  COST_AUDIT.md section 12's open list, each the user's call. Product: P4 of BUG_HUNT_2026-11-02.md, the default
  model picker and pool editor seen on screen, a current install (the installed app is from 2026-09-27).
- **After session 18** (2026-10-27): `cost-audit-improvements` is merged into main (fast-forward, not pushed; P1, P3,
  decision 4 and improvement 7 are done: COST_AUDIT.md section 9). Optional paid follow-ups: P3 on real1's real-sized
  failures (≈$0.70–1.00) and P5 (judge precision at real base rates, ≈$0.30). 11b is built (2026-10-27). Not built:
  11c's charged prices for stale-listed models, B9's calibration and escalation purposes, B11 (latent). Improvement 10
  (20–30 real-sized tasks) has 10; `REAL_TASKS_PLAN.md` plans the next 20; the user decided (its last section): only responsedigger
  and kurtkode go to hosted models, groups B and E (11 tasks) first, a ≈$1 pilot before any other spend. The
  SwiftPM-in-sandbox check passed (2026-10-27; `--disable-sandbox` needed, 19 tests skipped, serial suite 105 s; the
  plan's last section). The harness changes are built (multi-set
  `--bank real:<set>`, hidden tests, write-tests and lookup checks; REAL_TASKS_PLAN.md "Harness changes"). The 11
  tasks are built and validated (sets `rdh`, `kk`, `kkq`; REAL_TASKS_PLAN.md "The first 11, built"). The kk and kkq
  fixtures are gitignored: run `sh spike/real-set-2/build_kk.sh` after a clone. The pilot ($0.55) and Main ($3.23, 99
  runs in `eval-results/runs/real2`) are done; no task is broken, rdh03 failed all 9 runs (too big for 60 steps), and
  one ling pass was a dropped connection that gold doesn't count against (REAL_TASKS_PLAN.md "Main"). Next, each the
  user's call: the Frontier, Cascade and P3 rows (≈$16, ≈$5, ≈$2), building groups C and D, splitting rdh03.
- **After the cost audit** (session 17, 2026-10-26; `COST_AUDIT.md`, P2 run the same evening): the user's decisions on
  its section 7 come first (P2b is done, 2026-10-27; most decisions implemented in session 18, above). Recommended order: the subagent default for real-sized
  work (improvement 11a: Haiku for edit tasks over a real repository); improvement 1 (a stable prompt prefix: move the
  Environment facts after the instruction files or into the first user message, then P1 ≈$0.02); the grader default;
  the price and accounting fixes as a Round 8 (COST_AUDIT.md improvements 2, 5, 8, 9, each with a test); the
  escalation card's strong-review action after P3 (≈$0.30); P3 router shelved. The audit's findings decide what comes
  before Phase 4 (compatibility) in GAP_ANALYSIS.md Part 3.
- **Phase 3 leftovers** (TODO.md "Phase 3"): Round 7's noted items; a token-based delegation threshold (A7 never
  trips for hosted models); opening a file at a line in the user's editor; the rewind dialog's three buttons and the
  checkpoint list clicked through by hand; the Anthropic key's credit (the pool's Haiku and Opus fail there).

0. **Phase 2 of GAP_ANALYSIS.md (cost in sessions) is done** (session 15; GAP_ANALYSIS.md "Phase 2 plan", "Phase 2
   as built" A1, A2, A3, A5, and "Phase 2 measured"; Round 6 in FUNCTIONAL_TEST_RESULTS.md). Commits 4a33341 (A1 pool,
   listed capabilities, reasoning setting), 08e84e0 (A2 defaults and retry), ff8343c (A3 signals and thumbs), 2a1a56b
   (A5 spending), 386060e (Round 6: 30 review findings fixed, incl. a privacy hole: LAN names counted as remote), and
   the measurement commit after it. **Main finding**: the D3 retry ladder catches almost nothing (1 of ling's 9 bank
   failures) because cheap models fail by being wrong, not by failing outright; Phase 3's cascade needs the `verify`
   check and judges as its failure detector. **Measured, paid** ($0.198, user approved): on the delegation scenarios with a forced-delegating Haiku parent, subagents on the pool passed as often as on Haiku itself (12/15 each) at half the cost a run (GAP_ANALYSIS.md "Phase 2 measured"). **Defaults changed**:
   with the subagent and grader settings never set (as on this Mac), hosted sessions now send subagent tasks to
   ling-3.0-flash on OpenRouter and important ones' grading to Haiku. Phase 2 leftovers: (a) retry counts in the eval's results (its subagent store is thrown away);
   (b) the not-fixed C items at the end of Round 6; (c) Ollama and vLLM listings only unit-tested; (d) Phase 1's
   leftovers below still stand. **Then Phase 3** (Part 3: C1 task diff + revert, A6 cross-vendor review, A4
   cheap-first cascade advisory, A7 kurtkode-initiated delegation, C3 rewind options).
   Phase 1 (session 14), for reference: **Phase 1 of GAP_ANALYSIS.md (agentic core) is done** (session 14; GAP_ANALYSIS.md "Phase 1 as built" has each
   item, its live results and what wasn't checked). Its functional-test round (Round 5) and the before/after bank
   measurement are done. **Phase 1 leftovers**: (a) ~~the cost-floor shortlist re-run~~: done ($1.69; COST_FLOOR_RESULTS.md "Re-run after Phase 1"): all three still clear 95%, ling-3.0-flash still cheapest; **no model loaded a skill in 1,439 runs** while the listing and Phase 1's tool definitions raised prompt tokens 32–103%, but the user chose to keep it (small models have large contexts); deepseek-v4-flash-0731 cost 2.4 times as much a run (doubled tokens, and OpenRouter routing more of it to dearer providers; its listed price didn't change). It hung 5 hours on `Process.waitUntilExit()` in grep (fixed in 28e9843 with `startWithExitSignal`/`waitForExit`); the same call remains in LMSCLI, RunRecord, MCPConfig, Hooks, GitRepo, EvalKit's Fixtures/Scenarios and kurtkode-eval, worth moving over; (b) eval scenarios still missing from Part 3's list: plan-then-execute (the eval would need a `presentPlan` that
   approves) and a long build in the background; (c) `apply_patch` was tried once on OpenRouter's gpt-oss-120b
   ($0.0024 in all, with the user's OK): it works, but gpt-oss uses it only when told to (it prefers `edit_file`); (d) Revise and Reject on the plan card, and `lastCheck`, only
   unit-tested; (e) Gemma 4 never calls `present_plan` itself (0 of 4): the answer-as-plan fallback carries it, so
   see whether other local models do. **Then Phase 2** (GAP_ANALYSIS.md Part 3: A1 pool, A2 defaults and retry, A3
   main-run quality signals, A5 cost report). What session 14 did, in order:
   - ~~**B4 grep on ripgrep**~~: done in session 14 (rg 15.2.0 downloaded with the user's approval and committed).
   - ~~**B5 edit tooling**~~: done in session 14. `apply_patch` hasn't met a real GPT-family model yet.
   - ~~**B2 background commands and shell**~~: done in session 14 (tools `bash_output`, `kill_shell`).
   - ~~**B1 plan workflow**~~: done in session 14.
   - ~~**B6 instruction files and memory**~~: done in session 14.
   - ~~**B7 compaction template**~~: done in session 14.
   Measure each on a real local model as Phase 0 was (below), and add eval scenarios where Part 3 lists them.
   Phase 0's open finding (the router's `fix-build-and-ci` pick leading Gemma to redirect output unread) was handled
   in B2 by the skill's wording (`tee`).

   **How Phase 0 was tested live (repeat for Phase 1)**: check `lms ps` and free memory (`vm_stat`); if nothing is
   loaded, load `google/gemma-4-26b-a4b-qat --context-length 32768 --parallel 1 -y` (15.6 GB) and **unload it when
   done**; if the user has a model loaded or generating, don't touch it. Make a scratch project in the session
   scratchpad, run `AgentCore/.build/debug/kurtkode -p "…" --mode auto -m lmstudio:google/gemma-4-26b-a4b-qat
   --no-mcp --no-subagents --output json` one task at a time in the background (`swift build --product kurtkode`
   first: `swift test` doesn't always rebuild the CLI), read the session JSONL in `sessions/proj-*/`, and move test
   sessions to `~/.Trash/kurtkode-test-*` after. For loop mechanics a scripted mock is faster (session 13's
   `p0mock.py` can send raw/cut tool calls; not kept in the repo; `spike/functest/pmock.py` is the nearest).
   **The machine is often loaded** (other Python jobs, an IDrive backup; load average 10–20): wall-clock tests
   (`stopAllEndsRunningCommandsAndTheirChildren`, `cancellationStopsTheCommand`, `theWallClockLimitHoldsWhileOnlyPingsArrive`,
   …) then fail by fractions of a second; rerun them alone before suspecting a change. `reportsACrashWithTheServersOwnMessage`
   can kill the test process with SIGPIPE (round 4's known dead-MCP-server issue).

   Older open threads: (a) **round 4's leftovers**: R4-29
   (every `-p` run on a `gen-` id server waits ~10 s at the end) and the traced-but-not-probed list in
   FUNCTIONAL_TEST_RESULTS.md "Round 4" (SIGPIPE on a dead MCP server, MCPHub double start, HTTP MCP streams never
   closed, compaction trimming unseen results, Claude rebuilt turns without thinking, …); probe each before fixing; (b)
   a `KURTKODE_NO_KEYCHAIN` for the CLI (and skip the reconciler for `--endpoint` runs); (c) the opaque-command rule
   asks about `"$PY" -m pytest`-style commands even in Full Auto: watch whether that bothers the user; (d) **cost
   calibration**: compare `kurtkode cost check --day 2026-10-16 --endpoint "Anthropic"` (and `"Google Gemini"`, with the
   console's `--tz`) with the consoles; (e) **cost tracking's purpose**: judging runs (fill `AgentRunRecord.judgment`)
   and choosing subagent models by cost against quality; (f) round 3's minor items (R3-7, -9, -12, -13, -14); (g) **the
   opencode study** (the list was recovered from session 9's transcript; it isn't in the repo): #6 background commands,
   #7 format after edits / a check command, #8 cache-aware pruning, #9 secret scrubbing, #10 project scripts as commands
   and instruction globs, #11 worktrees, #12 plan review, #13 server/ACP, #14 cross-session search; (h) session 8
   candidates (Claude's append-only tools, a per-model effort setting, the eval on Claude/Gemini, price table upkeep:
   introductory Gemini prices end 2026-11-30 and 2026-12-31). (i) **cost-floor follow-ups** (COST_FLOOR_RESULTS.md): a count mode for
   grep (cheap models ask for it and then miscount), parents checking subagents' list answers, the whole-store regold
   that missed changes on cf2 (use `spike/regold_by_task.sh` until found), and the router (P3) taking the results as
   priors with OpenRouter models in the pool.
1. **TODO.md**: trace values into subagent runs (provenance across a task result); wake on queued input while the
   loop waits for a background report.
2. **A look at repeated searches**: in a session-5 test Gemma 4 26B ran the same grep three times (turns 3, 4, 6, 7:
   "not run" each time, the duplicate guard told it so) before reading the file. Replaying turn 4 on Qwen with
   reasoning off chose a different search. Worth checking whether the guard's wording or the result's placement
   could steer it sooner (the replay tools are made for this).
3. **Debugging extras, if wanted**: replay a whole run from a turn on (not just one request); replays of subagent
   turns from the parent's view; diff two replays; export from the Debug window (the core does it; the CLI has it).
4. **Subagent follow-ups, if wanted**: background runs for agents that write (needs a lock on files both edit);
   `/stop N` in the CLI (needs input while a run goes); an eval scenario for subagents (and for hooks).
5. **Journal extensions, if wanted**: notes and bookmarks (the user skipped them for now), "visible to this turn via …"
   in provenance (today it finds the first appearance anywhere).
6. **Other freezes**: the user hasn't reported more; long streams are fixed (F14). Known leftovers: ~0.3–0.7 s at
   launch; code blocks nested in lists use Textual's highlighter; `MessageView` takes closures (every visible message
   re-renders per update); the inspector's `todos`/`changedFiles` rescan all messages per render; `ChatView`'s body
   re-runs every 3 s for the memory readout; a long reasoning section is one `Text`.
7. **MCP OAuth** when the user wants a hosted server that needs it; hook events SessionStart and Notification.
8. CLI: per-project history, Tab completion of /model names. Eval: more trials for flipped cells. Nice to have: SSE
   resumption, a **stable signing identity** (ends Keychain prompts; more useful now that two keyed endpoints exist).

Machine state (2026-10-17, end of session 10): LM Studio is up with the user's meta/muse-glimmer (131k context, 4
slots), which they loaded for this session's live tests (it reads prompts at ~117 tokens/s: a 9k-budget compaction run
of the parts demo took 58 min). The LAN LM Studio "bang" (192.168.1.20) wasn't used. Saved endpoints: This Mac,
Openrouter, bang, Anthropic, Google Gemini (keys in the Keychain). No kurtkode test instances or mock servers running.
Test sessions are in the Trash (`kurtkode-test-r4*`); the five "Cost calibration: …" chats are kept in
`sessions/_chats`. Scratch projects are in the session scratchpad. Nothing is untracked in the repo (the icon exports
are committed as `assets/` and `favicon.ico`).
