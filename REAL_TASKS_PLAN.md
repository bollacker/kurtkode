# Real-sized tasks: plan for the next 20

COST_AUDIT.md improvement 10. Written 2026-10-27, after 11b was built. Nothing here is run yet; the paid steps need the
user's approval, each with `--max-cost`. **The user's decisions are at the end and override the set and order below**:
only responsedigger and kurtkode go to hosted models; groups B and E (11 tasks) come first; then a ≈$1 pilot.

## Why more

The real set (`--bank real`, `eval-results/real-fixtures/`) is ten tasks. It overturned the bank's conclusions (ling
98% → 10%; Haiku the cheapest success), but it is narrow in five ways that now limit what it can decide:

1. **One repository** (responsedigger, Python, 4,200 lines), one author's style, one domain.
2. **One task shape**: a feature commit with its tests already in `tests/`, so every task is "make the failing tests
   pass". Real sessions also fix bugs nobody wrote a test for, write tests, refactor, and ask questions.
3. **No lookups at real size.** Improvement 11a keeps ling for lookups on the strength of the small bank only.
4. **Too few failures** to label: 27 strict failures over 72 runs. The router stays shelved until about 100 labeled
   real failures exist (decision 5).
5. **Every repository context fits easily**, so delegation (improvement 7's 30k-token trigger) never comes up.

What the larger set should decide, in order: whether 11a's routing holds beyond one repository; how precise 11b's
after-run test trigger is, and whether a live Haiku → Sonnet cascade on it really costs about a quarter of always-Sonnet
(P2 modeled −75%); what the review-first card costs and catches on real diffs (P3 on real sizes); whether ling can keep
real-sized lookups; and enough labeled failures to revisit the router.

## The set: 30 tasks

| Group | Count | Source | Shape | Verifier |
|---|---|---|---|---|
| A. Kept | 10 | responsedigger, the ten tasks now in the set | feature, tests given | the suite |
| B. Hidden tests | 8 | hazard-response-classifier (4), responsedigger (2, from its five unused candidates), kurtkode (2) | feature or fix from a commit; the commit's new tests are withheld and added only to check | the suite with the hidden tests (fail before, pass at gold) |
| C. Second language | 4 | kurtkode (Swift) | fix or small feature across 2–5 files | `swift test --filter` on the touched suites, under a time limit |
| D. Write tests | 3 | fix commits in responsedigger and hazard-response-classifier | "add tests that would have caught this bug" | the new tests pass on the fixed code and fail on the buggy version, which the harness keeps outside the fixture |
| E. Real-sized lookups | 3 | sugar and kurtkode | a question needing 30k+ tokens of reading ("which paths can set X, and where is each checked") | a JSON answer checked by script against facts derived from the code |
| F. Large public monorepo | 2 | sugar or modelplane-flights, commits after 2026-06-01 only | feature or fix, hidden tests | as B |

Mined on 2026-10-27, commits that change both source and tests (20–150 source lines, 1–7 files): responsedigger 15 (10
used), hazard-response-classifier 12, kurtkode 27, sugar 30 (of 194 commits since 2026-06-01), modelplane-flights 26 (of
171 since then).
There are enough candidates; the binding constraints are validation and the user's time to review prompts.

Selection rules: the solution is 20–150 source lines over 1–7 files (P2's were 25–119); the suite runs in under 5
minutes; Sonnet needs 10–40 steps (P2's Sonnet averaged 26; checked in the Frontier row). Also:

- **Not in training data**: private repositories, or public commits after 2026-06-01 (the newest model cutoff in the
  pool); the repository's visibility is recorded per task.
- **Implementation-agnostic checks** (the DeepSWE pattern): hidden tests may use only interfaces the prompt names. A test
  that pins a private helper's name is rewritten or dropped.
- **Spread of difficulty**: after the pilot, at least 5 tasks Haiku fails and at least 5 that ling passes, so the set
  separates the tiers instead of saturating them.

## Harness changes: built 2026-10-27

`TaskBankReal` read one set with one interpreter and one test command. Now (`EvalKit/TaskBankReal.swift`, tests in
`TaskBankRealTests.swift`; P2's set loads and checks as before):

1. **Several sets.** `eval-results/real-fixtures/tasks.json` is P2's set (named `real`); each subfolder with a
   `tasks.json` is another, named by its folder (or its `name`). `--bank real` runs all of them, `--bank real:<set>`
   one. Task ids must be unique across sets (loading fails otherwise), so a run's task id also names its set. Per set:
   `testCommand` (`{python}` replaced by `python`), `testsPath` (default `tests`, for "existing tests kept"),
   `mayChange`, `checkTimeout` (default 900 s), `prepareCommand` (run in each fixture after it's unpacked, outside the
   sandbox and before the run's clock starts: the kurtkode set's cold `swift build`), and `gitignore` (lines added to
   the fixture's own `.gitignore`; without it, P2's behavior: replaced by Python's caches).
2. **Per-task fields.** `kind` is `TaskCard.Kind`'s raw value (edit by default, search for a lookup), so 11a routes the
   card as the product would; read-only kinds run on the explore agent with nothing allowed to change. Also
   `testCommand` and `mayChange` overrides, `hiddenTests` and `buggy` (`.tgz` overlays beside `tasks.json`, never in
   the fixture), and `answer`.
3. **Checkers.** Edit: the suite passes (with the hidden tests laid over the run's tree, if any) and no existing test
   line changed. Write-tests: also the run added tests, and the suite fails with the `buggy` files laid over its tree.
   Lookup: each fact in `answer` matches the report (`anyOf` regexes, any case) and none of its `noneOf` does; this
   replaces the JSON block the plan first named, since facts matched in prose don't depend on the model following a
   format. Every overlay is put back afterwards (files it replaced restored, files it added removed): the eval runs
   gold first, then the re-run check and the judges on the same tree, and those must see what the run left.
4. **Not built: writing `testCommand` into the fixtures.** Bank tasks run as subagent tasks (the `general` agent, the
   test command as the card's check), and 11b fires only on main runs. The eval already runs the card's check again
   after every run, sandboxed, and stores it (`recheckExit`): that is 11b's detector, measured as P2b measured it. The
   live cascade (the Measurement table's "Cascade, live" row) needs a main-run mode in the eval, built only if that
   row is approved.
5. **Store.** Unchanged: one store per measurement (`--record real2`); each record already has its task id (hence its
   set) and the card's kind.

The card's check is shown to the model in the task text. For the kurtkode set it is `sh run-tests.sh`, a script in
the fixture, so the flag is not in the task text: a model that runs the check gets a working build, and one that runs
plain `swift build` meets the error and the bash tool's hint. The pilot can therefore see whether models act on the
hint. The kurtkode set's settings:
`testCommand` runs a script in the fixture holding the serial suite with the skip list (the 19 names are too long for
a card), `testsPath` `AgentCore/Tests`, `prepareCommand` `cd AgentCore && swift build --disable-sandbox --build-tests`,
`gitignore` `[".build/", ".swiftpm/"]`, and `mayChange` `AgentCore/Sources/`, `AgentCore/Tests/`, `App/` and the
top-level docs.

## Building each task (free, local)

A script per step, under `spike/real-set-2/`, so the set can grow later without this plan:

1. **Mine**: list candidate commits by the selection rules (the 2026-10-27 counts above came from such a script).
2. **Fixture**: the repository at the parent commit, with no history, hidden tests withheld; plus a `conftest.py` or
   test filter that skips tests the sandbox breaks (found by running the suite at gold inside and outside kurtkode's
   sandbox; in P2 four such tests made the after-run check fail on every run until P2b skipped them).
3. **Validate**: fail before, pass at gold, under the sandbox, three times (flake check), under 5 minutes.
4. **Prompt**: drafted from the commit message and diff by a subagent, naming the interfaces the checks use and nothing
   of the solution; then a leak check (no line of the solution in the prompt). **The user reviews the prompts** of the
   new repositories: they know what the commits meant. About 30 minutes for 20 prompts.
5. **Environment**: one pinned environment per repository (pyenv env or SwiftPM resolved), its versions written into the
   set's `tasks.json`.

Kurtkode as a Swift source: its suite takes minutes to build; the C tasks filter to the touched suites, and the fixture
carries a pre-built `.build` so a run's first `swift test` isn't a cold build. Whether SwiftPM builds inside the
sandbox at all is the first thing to check; if it doesn't, group C is dropped and its four tasks go to B.

## Measurement (paid; estimates from real1's costs per run)

| Step | What | Runs | Estimate |
|---|---|---|---|
| Pilot | Haiku, one trial per new task; drop broken or trivial ones (passed in under 8 steps) | 20 | ≈$1 |
| Main | Haiku, deepseek-off, ling, three trials each, on the 20 new tasks | 180 | ≈$7 |
| Frontier | Sonnet, one trial on the 20 new tasks | 20 | ≈$16 (median $0.52 a run; long runs to $1.9) |
| Cascade, live | Haiku on all 30; where 11b's suite trigger fires, Sonnet takes it over through the product's hand-over | 30 + the escalations | ≈$5 |
| P3 at real size | Sonnet review of each cheap failure in real1 and real2 (`--review-sim`) | about 60 | ≈$2 |

About $31 in all, each process capped. Two cheaper paths: skip the Frontier row and use Sonnet only where Haiku fails
(≈$6 instead of $16, but then Sonnet's own failure rate on the new tasks is unknown), or stop after the Pilot and Main
rows (≈$8) if the routing question is the only one that matters now.

Labeled failures this yields, at real1's rates (ling ~90%, deepseek ~25%, Haiku ~17%): about 80 of the 180 cheap runs
on the new tasks (ling ~54, deepseek ~15, Haiku ~10), about 107 with real1's 27; but two thirds are ling's, and a router learned mostly from
ling's failures would just learn "not ling". The real-session labels (P4) remain the better source for the router.

## Order of work

1. **The user's decisions** (below).
2. Harness changes 1–5, with tests; no paid calls.
3. Group B from hazard-response-classifier first (second repository, same language, the cheapest proof the pipeline
   generalizes), then D, E, C, F.
4. The prompt review by the user.
5. Pilot, then Main and the rest in the order of the table, each after the user's approval.
6. Write-up in COST_AUDIT.md (a section 10) and the decisions it changes: 11a's routing, 11b's precision, the escalation
   card's review price, ling's role.

## Decisions (the user's, 2026-10-27)

1. **Repositories sent to hosted models: responsedigger (as in P2) and kurtkode only.** hazard-response-classifier,
   sugar and modelplane-flights stay out. All four candidates are private (github.com answers 404 for each), so
   training-data contamination is no concern for any of them; the question was only whether their code may go to
   OpenRouter's providers.
2. **Scope: groups B and E first** (11 tasks), measured before anything else is built.
3. **Budget: the pilot first** (≈$1). The rest of the measurement is decided afterwards, with the pilot's costs.

### What the first decision changes

- **Group B** loses its four hazard-response-classifier tasks. It becomes **3 responsedigger tasks** (from its five
  unused candidates; the hidden-test shape on a known repository) and **5 kurtkode tasks** (Swift, 53k lines). kurtkode
  is now the only test of whether 11a's routing transfers to a second repository, and it changes the language at the
  same time, so a drop in pass rates there can't be split between "another repository" and "another language".
- **Group E** takes all three lookups from kurtkode. responsedigger, at 4,200 lines, is too small to need 30k tokens of
  reading.
- **Group C** merges into B for now: B's kurtkode tasks are the Swift ones. **Group D** (write-tests) comes from
  responsedigger only. **Group F** is dropped, since its only sources were sugar and modelplane-flights.
- **The SwiftPM check becomes the gate.** If `swift build` and `swift test` don't work inside kurtkode's sandbox, or a
  filtered suite can't finish in under 5 minutes, the first scope shrinks to the 5 responsedigger candidates plus
  lookups. The transfer question then has no source left. Asking again about hazard-response-classifier, or running its
  tasks on local models only, would be the way back.
- **kurtkode fixtures** include only the tracked source, without `eval-results/` and `spike/`: 21 MB against the
  repository's transcripts and stores, which would show models' earlier attempts. A pre-built `.build` is 547 MB, so it
  is shared read-only between runs rather than copied into each fixture, if the sandbox allows that. Otherwise each run
  pays a cold build, and the pilot measures how long that takes.
- **Unchanged:** the harness changes, the per-task building steps, and the selection rules.

### First scope, as decided

| Group | Tasks | Source | Verifier |
|---|---|---|---|
| B | 3 | responsedigger, unused candidates | the suite with the hidden tests |
| B | 5 | kurtkode (Swift) | `swift test --filter` on the touched suites, with the hidden tests |
| E | 3 | kurtkode lookups | the JSON answer checked by script |

Pilot: Haiku, one trial each, on these 11 tasks. Estimate ≈$1. The cost per run on kurtkode's larger context is unknown;
real1's Haiku averaged $0.047, so even at twice that, 11 runs stay near $1. Run with `--max-cost 2`.

### SwiftPM in the sandbox: checked 2026-10-27, it works

kurtkode's tracked source (without `eval-results/` and `spike/`), built and tested under the eval's own command sandbox
(`SandboxPolicy()`: writes only in the project, temp and the per-user cache folder; no network), reproduced exactly by
`spike/real-set-2/insandbox.sh`. Swift 6.1.2, this Mac. The kurtkode half of the first scope stays.

- **`--disable-sandbox` is required.** Plain `swift build` fails at once: SwiftPM compiles the manifest in a sandbox of
  its own, and macOS refuses to start a sandbox inside one (`sandbox_apply: Operation not permitted`, then "Invalid
  manifest"). `--disable-sandbox` turns off only SwiftPM's inner sandbox; kurtkode's still applies. No package
  dependencies, so no network is needed. The user-level SwiftPM caches in `~/Library` aren't writable, which SwiftPM
  only warns about.
- **Times:** cold `swift build --build-tests` 57 s; a rebuild after a one-file change 6 s; the whole suite 15 s in
  parallel, 105 s serially; a filtered set of five suites 3.4 s.
- **19 tests fail inside the sandbox** (`spike/real-set-2/kurtkode-sandbox-skip.txt`): tests that start a sandbox of
  their own (the same nested-sandbox refusal), the MCP HTTP tests (local sockets count as network), two that signal
  process groups, and four CLI-session tests. All pass outside the sandbox, so they are skipped in the fixtures, as
  P2b skipped responsedigger's four.
- **In parallel, the rest is flaky under the sandbox's load.** 1–6 timing tests failed in each of three runs, a
  different set each time. Serially (`--no-parallel`) with the skip list, all 647 tests pass, in 105 s. So the
  verifier is the serial suite with the skip list plus the hidden tests,
  `swift test --disable-sandbox --no-parallel --skip '<the 19>'`. That is also each fixture's `testCommand` for 11b.
- **No shared pre-built `.build`.** An APFS clone of a built fixture at another path fails (`missing required module
  'SwiftShims'`), because the build is bound to its folder. Each fixture is built in place when it is prepared, before
  the run's clock starts: about a minute of harness time a run, none of the model's.
- **The model is told about `--disable-sandbox`.** A model in the sandbox that runs plain `swift build` gets the
  "Invalid manifest" error. kurtkode's bash tool has added a note for this since Phase 5: when a failed command's
  output contains `sandbox_apply: Operation not permitted`, it names the cause and SwiftPM's flag
  (`BashTool.sandboxNote`; tested since 2026-10-27 by `aToolStartingItsOwnSandboxGetsTheHint`). The card's check is
  `sh run-tests.sh` and no prompt names the flag (Harness changes, above), so the pilot sees whether models act on
  the hint.

### Order of work, as decided

1. ~~The SwiftPM-in-sandbox check~~: done (above); it works with `--disable-sandbox`.
2. ~~Harness changes 1–5~~: done (2026-10-27; 4 not needed, see above).
3. ~~Build and validate the 11 tasks~~: done (below); next, the user reviews the 8 kurtkode and responsedigger
   prompts and the 3 lookups.
4. ~~Pilot~~: done 2026-10-27, $0.55 (below).
4b. ~~Main~~ on the 11: done 2026-10-27, $3.23 (below).
4c. ~~Frontier, P3 at real size, P5, Cascade~~: done 2026-10-28, $20.33 in all (below; $1.81 of it on runs set aside).
5. The user decides the rest of the budget and whether to build groups C and D with the pilot's results in hand.
   Group C stays merged into B (the kk tasks are the Swift ones). ~~Build group D~~: done 2026-10-28, no paid calls
   (the set `rdw`, below); prompts reviewed, and Haiku's pilot passed all three ($0.05, 2026-10-29).

### The first 11, built (2026-10-27)

Three sets under `eval-results/real-fixtures/`, run with `--bank real:rdh`, `real:kk` or `real:kkq` (all three, and
P2's set, with `--bank real`):

| Set | Tasks | What gold checks | Fixtures |
|---|---|---|---|
| `rdh` (responsedigger) | rdh01 8d67125 fix, rdh02 c89f074 edit, rdh03 e748e3d edit | the suite with the commit's tests laid over | committed (1.8 MB); P2b's `conftest.py` skips the 4 tests the sandbox breaks |
| `kk` (kurtkode) | kk01 f684795 fix, kk02 2cbf82d fix, kk03 40b78d5 edit, kk04 b1212ff edit, kk05 ef71941 edit | the serial suite with the skip list (`sh run-tests.sh`) and the commit's tests laid over | gitignored (33 MB); `spike/real-set-2/build_kk.sh` rebuilds them |
| `kkq` (kurtkode lookups) | kkq01 search (what a project configures, 12 facts), kkq02 explain (escalation reasons, 12), kkq03 explain (spending limits, 8) | the facts in the report, nothing changed | gitignored (36 MB, the tree at eb19878); `build_kk.sh` |

Built with `spike/real-set-2/build_task.py` (the parent's tracked tree, the commit's test files as the hidden overlay,
the rest of the commit as the gold diff) and checked with `validate_task.py`: the visible suite passes at the parent
(sandboxed), the hidden tests fail there, and with the gold diff the suite passes twice unsandboxed and twice in the
eval's sandbox. All 8 hidden-test tasks are valid. Notes:

- **rdh03**: three of its four hidden tests fail before the fix; the fourth (Ctrl-C) is one of the four sandbox-broken
  tests the conftest skips, so that part of the prompt is specified but not graded.
- **kk01–kk04 carry a later fix.** Their commits predate 28e9843, the fix for a process wait (`waitUntilExit`) that
  sometimes never returns; kk02's suite hung on it in 7 of 8 runs (a grep test, stuck at the 900 s limit, with the
  test process left behind). `build_kk.sh` applies that fix to the fixtures of commits before it
  (`hangfix-28e9843.diff` and `ProcessExit.swift`); `build_task.py --patch` refuses a patch that touches the
  commit's own files. kk01–kk04 were validated again after it.
- **The lookups' facts** are regular expressions checked against reference answers (all facts found, under both
  Python's and Foundation's regex engines) and against weak answers (missing or wrong facts fail).
- **Prompts** were drafted from each commit without its solution, and all 8 were checked against their hidden tests:
  every interface a test calls is named in the prompt (type, function and argument names, the strings a test
  matches). Some asked-for parts have no hidden test, like rdh03's Ctrl-C: rdh01's fourth `splitlines()` site
  (`config.py`) and kk01's `WireLog` index fix.

### Pilot (2026-10-27, paid, approved): Haiku on the 11

`kurtkode-eval --bank rdh01,…,kkq03 --models openrouter:anthropic/claude-haiku-5.5 --trials 1 --record real2
--context 32768 --max-tokens 16384 --skills builtin --no-train --max-cost 2 --parallel-remote 2` (P2's settings). Store
`eval-results/runs/real2`, log `spike/real-set-2/pilot.log`. **$0.55** charged (equal to list), 7 of 11 passed, about
40 minutes.

| task | result | steps | s | $ | why it failed |
|---|---|---|---|---|---|
| rdh01 | pass | 13 | 92 | 0.011 | |
| rdh02 | fail | 35 | 283 | 0.061 | handled a changed limit but not changed items: the hidden test's "superseded (the items changed)" line is missing |
| rdh03 | fail | 60 (cap) | 505 | 0.116 | 2 of the hidden check tests fail (a forced recheck, reusing `check`'s passes) |
| kk01 | pass | 20 | 178 | 0.023 | |
| kk02 | pass | 37 | 588 | 0.049 | |
| kk03 | pass | 30 | 237 | 0.043 | |
| kk04 | fail | 60 (cap) | 483 | 0.110 | never wrote `RateLimits.retryDelay(fromBody:)`, which the prompt names; it also changed lines of a test helper (`MockServer`) to send headers |
| kk05 | pass | 45 | 819 | 0.105 | |
| kkq01 | fail | 5 | 66 | 0.014 | 11 of 12 facts; the report leaves out `testCommand` |
| kkq02 | pass | 7 | 65 | 0.012 | |
| kkq03 | pass | 6 | 37 | 0.006 | |

Each failure was checked by hand: the run's own tree with the hidden tests (kk04 compiled cold, since a saved
`.build` doesn't build at another path), or the report against the facts. **No task is broken**; every failure is the
model's. What it shows:

- **Cost.** kurtkode's tasks cost about what responsedigger's did ($0.023–0.11 a run, $0.066 on average for kk; P2's
  Haiku averaged $0.047), so the Main row's ≈$7 stands.
- **Difficulty.** Haiku passed 4 of 5 kk, 1 of 3 rdh, 2 of 3 lookups. No edit task is trivial (fewest steps: 13). The
  lookups take 5–7 steps by nature, under the 8-step bar meant for edit tasks; keep them, since kkq01 failed.
- **The re-run check misses hidden-test failures.** The visible suite passed again after every failed run
  (`recheckExit` 0 on rdh02, rdh03, kk04), so a cascade triggered by 11b's suite would not have caught these
  failures; the step limit (rdh03, kk04) would have caught two.
- **The sandbox hint.** Haiku mostly ran the card's `sh run-tests.sh`. One run (kk03) ran plain `swift build`, met
  `sandbox_apply: Operation not permitted`, then added the flag and passed; it had read `run-tests.sh` (which has the
  flag) earlier, so whether the hint or the script taught it is open.


### Main (2026-10-27, paid, approved): Haiku, deepseek-off, ling on the 11

`kurtkode-eval --bank rdh01,…,kkq03 --models openrouter:anthropic/claude-haiku-5.5,openrouter:deepseek/deepseek-v4-flash-0731#off,openrouter:inclusionai/ling-3.0-flash
--trials 3 --record real2` with the pilot's settings, `--max-cost 8 --models-at-once 3 --parallel-remote 1`. Log
`spike/real-set-2/main.log`. 88 new runs (Haiku's first trial is the pilot's), about 3½ hours. **$3.23** charged
(list $3.24): Haiku $1.06 for 22 runs, deepseek $1.73, ling $0.44.

| task | Haiku | deepseek-off | ling |
|---|---|---|---|
| rdh01 fix | 3/3 | 3/3 | 3/3 |
| rdh02 edit | 2/3 | 0/3 | 0/3 |
| rdh03 edit | 0/3 | 0/3 | 0/3 |
| kk01 fix | 3/3 | 2/3 | 3/3 |
| kk02 fix | 2/3 | 0/3 | 0/3 |
| kk03 edit | 3/3 | 0/3 | 0/3 |
| kk04 edit | 2/3 | 0/3 | 0/3 |
| kk05 edit | 2/3 | 3/3 | 0/3 |
| kkq01 search | 1/3 | 0/3 | 0/3 |
| kkq02 explain | 2/3 | 3/3 | 2/3 |
| kkq03 explain | 2/3 | 3/3 | 3/3 |
| **all 33** | **22 (67%, CI 50–80%)** | **14 (42%, 27–59%)** | **11 (33%, 20–50%)** |
| $ a run / a success | 0.049 / 0.073 | 0.053 / 0.124 | 0.013 / 0.040 |

The failures were checked like the pilot's. **No task is broken**, but two need a note:

- **rdh03 failed all 9 runs**, every one at the 60-step cap, always on the same two hidden check tests. Those were
  re-run on two runs' trees: Haiku never added `--recheck` to `run`, and `check` didn't journal results that `run`
  reuses. deepseek never accepted the `[sources]` table (`load_run_config` rejects it as an unknown key). Both are
  asked for by name in the prompt. Its gold diff is 538 lines, 3½ times the next largest (kk05, 155), so the task is
  valid but too big for 60 steps at these models' pace. Either keep it as the set's ceiling or split it in two
  (checks; `[sources]`). *Later (Cascade, 2026-10-28): at 200k context Sonnet passed it 3 of 3; the 32k cap was the
  limit, so it stays whole.*
- **kkq01's `testCommand` fact** was missed by 8 of the 9 runs that answered. None of those reports mentions a test
  command at all, so the matcher isn't too strict. It's the hardest fact, a settings key rather than a file. Haiku's
  one pass found it.
- **One pass was an infrastructure fault.** ling's rdh01 #3 lost its connection to the provider (Novita: "The network
  connection was lost.") at step 4. The run stopped as failed with no report, but its three edits already passed the
  hidden tests, so gold counts it a pass. Gold ignores the run's own hard failures ("no report", "stopped early").
  Without it, ling is 10 of 33. The dropped request wasn't retried.
- The other failures are the models': an API the hidden tests call was missing or had a different shape (kk03, kk04,
  kk05, rdh03), behavior was missing (rdh02's "superseded" line, kk02's patch paths), existing tests were edited
  (Haiku kk02 #3 and kk04 #1, deepseek kk04 ×2), or files were left outside the task (deepseek kk01 #3 left
  `baseline*.txt`, rdh03 #3 left `_shims/rich/`). No suite timed out, and the kk02 hang didn't come back.

What it shows:

- **The models separate on edits.** On the five kk tasks Haiku passed 12 of 15, deepseek 5 and ling 3 (kk01 only). On
  the two harder rdh edits, Haiku passed 2 of 6 and the others 0. The lookups and rdh01 are easy for all three. ling
  is the cheapest per success ($0.040) only because it passes the easy tasks; it passed none of the 21 runs on kk02–05,
  rdh02 and rdh03.
- **Failures for the router: 52**, now spread across the models (Haiku 11, deepseek 19, ling 22), not two thirds
  ling's as the plan feared. Their failure rates (33%, 58%, 67%) are two to three times real1's for Haiku and
  deepseek (~17%, ~25%) and lower than real1's for ling (~90%): these tasks are harder for the stronger models.
- **The cheap signals catch about two thirds.** A run that hit the step cap or didn't complete, or whose visible suite
  failed on the re-run, flags 34 of the 52 failures (Haiku 5 of 11, deepseek 10 of 19, ling 19 of 22), with 5 false
  alarms among the 47 passes. The re-run check alone flags 10 of the 40 runs whose hidden tests failed. The visible
  suite passes after most real failures, so 11b's suite trigger sees only a quarter of them.
- **Cost** matched the estimate: $3.23 for 88 runs ($0.037 a run), against ≈$7 for 180.

### Grading corrections (2026-10-28)

Checking the Frontier row's failures found three grading faults and one harness fault. All are fixed, with tests, and
the stored runs were re-graded (`--regold`, no model calls):

- **Edited tests (the user's decision).** "Existing tests kept" failed any run that changed an existing test line.
  Three runs that passed every hidden test failed on it alone, for additive edits: Sonnet kk03 gave the `reply()`
  helper a parameter, Sonnet kk04 let `MockServer` send headers, Haiku kk02 #3 added a deny rule to a test's setup (the
  real commits only added tests). Now, when a run changed existing test lines, its code must pass the original tests
  folder with the hidden tests, its own new tests set aside (they may need its helper changes). A weakened test over
  wrong code still fails. All three now pass; Haiku kk04 #1 and deepseek kk04 #2–3 still fail (their code fails the
  hidden tests).
- **Lookup facts matched too narrowly.** Sonnet's kkq03 named all four limits as "**Run:**", "**Session:**",
  "**Day:**", "**Project per day:**" and said local models cost 0 "so they never hit a limit"; the patterns wanted
  "per-run" and the like. Haiku's kkq03 #3 ("Project, daily") and kkq02 #2 ("Project tests failing", "the lowest-tier
  main model … above the current one") likewise. Six patterns in `kkq/tasks.json` were widened; every kkq run was
  re-graded. The other lookup failures really leave the fact out (kkq01's `testCommand`; ling's kkq02 #3).
- **P3's diff (harness).** `--review-sim` rebuilt a run's change against a fresh fixture, so real1's runs, recorded
  before P2b added `conftest.py`, all showed it deleted, and every review flagged it (22 of 22 passes). For kurtkode
  fixtures it would also have rebuilt each fixture cold and diffed `.build`. The diff is now against the run's own first
  commit, ignored files left out (`ReviewSim.ownDiff`); the first real1 pass ($1.05) is kept aside as
  `real1-rows-baddiff.jsonl`.
- **Re-grading kurtkode runs (harness).** A restored fixture's `.build` is bound to its first folder ("missing required
  module 'SwiftShims'"). A task now carries `rebuild` (its set's `prepareCommand`), run after `git clean -X` in a
  restored copy; a tree that doesn't build is graded, not skipped.

Main, corrected (Haiku's three trials include the pilot's):

| | Haiku | deepseek-off | ling |
|---|---|---|---|
| passed | **25/33 (76%, CI 59–87%)** | 14/33 (42%, 27–59%) | 11/33 (33%, 20–50%) |
| $ a run / a success | 0.049 / 0.064 | 0.053 / 0.124 | 0.013 / 0.040 |

Haiku's changes: kk02 3/3, kkq02 3/3, kkq03 3/3. The others' rows are unchanged.

### Frontier (2026-10-28, paid): Sonnet on the 11

`--models openrouter:anthropic/claude-sonnet-5.5 --trials 1 --record real2`, the Main row's settings (32k context),
`--own-cost --max-cost 15`. Log `spike/real-set-2/frontier.log`. **$7.17** charged, about 25 minutes.

**10 of 11 passed** (CI 62–98%); the one failure is rdh03 (60-step cap, $2.19, the same two hidden check tests every
model fails). $0.65 a run, $0.72 a success: 13× Haiku's run, 11× its cost per success. Steps: 5–34 apart from rdh03.

- Sonnet passes every kk task, where deepseek and ling pass none of kk02–kk04; Haiku is 8 of 9 there. The gap between
  Haiku and Sonnet on these tasks is narrow (76% against 91% on one trial each); between the cheap tier and both, wide.
- rdh03: 0 of 10 runs over four models at 32k; at 200k, Sonnet finished it after Haiku 3 times of 3 (Cascade, below).
  Not too big, then, but too big for 32k.

### P3 at real size (2026-10-28, paid): Sonnet reviews the real failures

`--review-sim real1|real2 --reviewers openrouter:anthropic/claude-sonnet-5.5 --per-group 12` with the fixed diff: every
real failure that changed code, and 24 passing runs a store. Rows in `eval-results/review-sim/real{1,2}-rows.jsonl`.
**$2.49** ($0.015–0.026 a review, 8–13 s), plus the invalid first real1 pass ($1.05).

| verdict counted as a problem | real failures flagged | passes flagged |
|---|---|---|
| any ("has problems" or "wrong") | 66/68 (97%) | 28/47 (60%) |
| "wrong" only | 50/68 (74%) | **1/47 (2%)** |

At real size a review almost always finds something to say: "has problems" flags most good runs too (often a report
that misstates the test results, which real1's runs did around the four sandbox-broken tests). Only the "wrong" verdict
separates: 74% of real failures, 1 false alarm in 47. The escalation card (decision 4) offers escalation after any
verdict but "looks right"; at real size it should do so only on "wrong" (and say "has problems" as findings to fix).
A review costs $0.015–0.026, against $0.65 for a Sonnet run.

### P5 (2026-10-28, paid): cheap judges at real base rates

Haiku and deepseek-off as judges, parent path, on bank1: every real failure (42) and passes and degraded copies
(`--judge bank1 --judge-paths parent --sample 242 --judge-trials all`). Logs `eval-results/runs/p5-judges*.log`.
**$0.59.**

| judge | real failures caught | all failures (with degraded copies) | passes failed | kappa |
|---|---|---|---|---|
| Haiku | 24/42 (57%) | 73/124 (59%) | 0/180 | 0.63 |
| deepseek-off | 24/41 (59%) | 73/121 (60%) | 0/176 | 0.64 |
| grounded checks alone | 7/42 | | | |

Neither raised a false alarm, so a cheap judge's "fail" is trustworthy; each misses about four failures in ten.
deepseek does as well as Haiku, at about the same price here ($0.0010 a judgment against Haiku's $0.0008:
the list prices of 304 judgments each, $0.30 and $0.23).

### Cascade, live (2026-10-28, paid): Haiku main runs, Sonnet on the product's escalation

New eval mode `--cascade` (`EvalKit/Cascade.swift`). Each task runs as a **main run in a real CLI session**, the way
the product runs one: the main agent and its prompt, built-in skills, and the project's `testCommand` in
`.kurtkode/settings.json` (so 11b runs the project's tests after a run that changed files). Subagents and MCP are off.
When the session offers escalation (`CLISession.escalationOffer`, the product's grounded reasons), the offer is taken
(`decide(accept: true)`) and the stronger model picks the request up through the product's hand-over message, in the
same conversation and tree. Gold is checked after each stage. The session's data folder is a throwaway in the Trash,
with a pool of just Haiku (standard tier) and Sonnet (frontier) on OpenRouter. **The shipped pool escalates Haiku to
Opus**; Sonnet was used here, as this plan says, to compare with the Frontier row.

`--bank real --models openrouter:anthropic/claude-haiku-5.5 --cascade openrouter:anthropic/claude-sonnet-5.5 --record
cascade2 --trials 3 --context 200000 --max-tokens 16384 --skills builtin --no-train --max-cost 20`: all 21 real tasks
(real1's 10 and these 11), three trials. Log `spike/real-set-2/cascade.log`. **$8.27** charged, about 3½ hours.

**At 32k context first, then 200k (the user's decision).** The first 11 runs at the eval's usual 32k (kept in
`eval-results/runs/cascade1-32k`, $0.76) compacted 19–40 times a run: a main run's prompt and skill list leave little
room, and reads come back cut. Three of the 11 gave up without editing and wrote handoff notes (the built-in
`handoff-notes` skill says to use it when "running low on context"); a run that changed nothing gets no offer. The row
was restarted at the models' real 200k context.

| | runs | Haiku alone | after escalation | offers | $ a run |
|---|---|---|---|---|---|
| real1's 10 | 30 | 24 | **30** | 6 | 0.176 |
| these 11 | 33 | 29 | **32** | 3 | 0.092 |
| **all** | 63 | **53 (84%)** | **62 (98%)** | 9 | **0.132** |

- **Every offer was right, and every escalation fixed it**: 9 offers, all on gold failures, none on a pass; Sonnet
  passed all 9 in 7–19 steps for $0.39–1.31 ($0.72 on average). The one failure left is a lookup (kkq02 #2: two facts
  missing), which changes no files and so can earn no offer.
- **What triggered the offers**: 8 of 9 were "its reply was cut off at the output limit": Haiku spent all 16,384 output
  tokens on reasoning, with no text or tool call, after 7–12 steps (rd04, rd10, all three of rd12 and of rdh03). One
  was the project's tests failing after the run (11b), one also had unfinished todos. The step limit never fired at
  200k. A retry on Haiku itself (about $0.02) might settle the runaway-reasoning cases more cheaply than Sonnet; not
  measured.
- **rdh03 is solvable**: 0 of 10 at 32k over four models, 3 of 3 here (Haiku's reasoning ran away, Sonnet finished in
  8–16 steps). The 32k context of the Main and Frontier rows, not the task's size, made it the ceiling; it need not be
  split.
- **Cost**: $0.13 a run for 98%, against Sonnet alone at $0.65 a run (Frontier, the 11 only, 32k) for 91%: about a
  fifth of the price. Haiku's own runs averaged $0.029 (median 15 steps); the escalations are 78% of the bill.
- **Haiku as a main run at 200k (84%) did better than as a subagent at 32k (76% on the 11)**, the same direction as
  rdh03.

**A third grading fault, found here.** All three kk04 runs first failed with `'RateLimitTests' has no member
'aMissingModelSaysWhatToDo'`: Haiku put its tests in a new `RateLimitTests.swift` declaring `struct RateLimitTests`,
the name the hidden `RetryTests.swift` gives its suite, and Swift won't compile both. Gold now sets aside a new test
file of the run's that declares a type the hidden tests declare, and runs the suite again (the same principle as the
edited-tests rule; `clashingNewTests`). The three runs pass; no real2 run had such a clash. Cascade runs keep no
fixture, so `--regold-cascade SET` re-grades a failed run from its saved diff on a fresh fixture.

### Group D, built (2026-10-28, free): write tests for a fixed bug

Set `rdw` under `eval-results/real-fixtures/` (`--bank real:rdw`; `--bank real` now has 24 tasks), three tasks from
responsedigger fix commits. The harness's write-tests check existed since the harness changes (3, above); nothing in
the product or EvalKit changed. Each fixture is the repository **at** the fix commit with `tests/` as it was at the
parent, plus P2b's `conftest.py`; the prompt describes the bug and the fix and asks for tests that pass now and
would have failed before it. Gold: the suite passes, tests were added and the existing ones kept, nothing outside
`tests/` changed (each task's `mayChange`), and the suite fails with `<id>-buggy.tgz` (the commit's changed `src/`
files at the parent) laid over the run's tree.

| task | commit | the bug | fix | the commit's own tests |
|---|---|---|---|---|
| rdw01 | 89804ff | `redo` skipped a SUT whose earlier redo job was unfinished instead of resuming it | 16 lines, cli.py and plan.py | one end-to-end test extended |
| rdw02 | 717971a | HTTP 451 and a reply with `content: None` counted as errors against the SUT | 30 lines, job.py | two tests, and two new modes in `tests/fakes.py` |
| rdw03 | 8d67125 | JSONL readers split on U+2028 and called an intact record corrupt | 23 lines over 4 files | one unit test |

Built with `build_task.py --write-tests` (the fixture, the buggy overlay, and `<id>-reference.tgz`: the commit's own
tests, kept only for validation) and checked with `validate_task.py`'s write-tests path, twice each step: the
fixture's suite passes with the fixed code and with the buggy code (the old tests miss the bug), and the commit's
own tests pass on the fixed code and fail on the buggy code, both unsandboxed and in the eval's sandbox (suite
about 28 s). Then the harness's own gold, run on each prepared fixture by a throwaway test: with no new tests it fails
("tests added", "the tests fail on the code before the fix"); with the commit's tests laid in it passes, including
rdw01's and rdw02's edits to existing test files ("with the originals the suite passes"). No prompt quotes a line of
the reference tests.

Notes:

- **4d1a2e1 was tried first and dropped**: the outage fix changed what six old tests relied on (a dropped connection
  stood for a failing model), so the old suite fails on the fixed code, and the task would become "repair the tests".
  A write-tests commit must leave the old tests passing; validation checks this (`visible@fixed`).
- **rdw01 and rdw02 reuse no earlier task's commit; rdw03 is rdh01's commit** (8d67125) the other way round: rdh01
  asks for the fix with the tests hidden, rdw03 gives the fix and asks for the tests. Its prompt is shorter than
  rdh01's and names no function. responsedigger's only unused fix commit was 89804ff; the rest are features.
- **Gold is lenient in two ways.** A run's tests need catch only one part of a fix with several (rdw02's two causes,
  rdw03's four readers), since there is one buggy overlay. And a test that imports a helper the fix added fails on the
  old code at import (rdw02's `call_allowing_blank`; one of the commit's own two tests fails that way), so it counts
  as catching the bug without exercising it. A review or judge would see both; gold doesn't.
- **Prompts reviewed** by the user (2026-10-29) and kept as written.

### Group D pilot (2026-10-29): Haiku passes all three

`kurtkode-eval --bank real:rdw --models openrouter:anthropic/claude-haiku-5.5 --trials 1 --record rdw-pilot --context
200000 --max-tokens 16384 --skills builtin --no-train --max-cost 1`, on a release build of 9d30b8b. Log
`spike/real-set-2/rdw-pilot.log`. **$0.05** charged, about 9 minutes.

| task | gold | steps | s | $ | what it added |
|---|---|---|---|---|---|
| rdw01 | pass | 17 | 181 | 0.023 | `tests/test_redo_resume.py`, 7 tests (planned, interrupted and failed redo jobs resume; the log line) |
| rdw02 | pass | 19 | 268 | 0.018 | `tests/test_refusals.py`, 16 tests (451 refusals, blank replies, end to end through a job) |
| rdw03 | pass | 9 | 80 | 0.009 | `tests/test_jsonl_separators.py`, 6 tests (journal, results, export, config lookup) |

Each run's tests were rerun by hand on the fixed and the buggy code. rdw01's fail on the buggy code by assertion.
rdw02's and rdw03's fail there at import (`call_allowing_blank`, `json_lines`: helpers the fix added), the leniency
above; with those imports and the helper tests taken out, their behaviour tests still fail on the buggy code (6 of
rdw02's, all 4 of rdw03's), so all three runs earned their pass. Each run also covered every part of its fix, not one.

**What it says**: as built, group D is easy for Haiku; at 3/3 and under 2¢ a run it can't separate models. It still
measures what it was built for (does the agent write tests that pin a bug), and a model that fails it is telling us
something. Harder variants would hide where the fix is (no function names) or ask for tests of a fix that spans
modules. Not decided; the set stays as it is until the user says otherwise.

### Opus as the escalation target (2026-10-29): Sonnet is better value

The shipped pool escalates Haiku to Opus; the live cascade above used Sonnet. Same command with `--cascade
openrouter:anthropic/claude-opus-5.5 --record cascade3-opus --max-cost 20`, all 24 real tasks (now with `rdw`), three
trials, release build of 9d30b8b (so with 3b02e0b's escalation changes). Log `spike/real-set-2/cascade-opus.log`.
**$15.98** charged (estimate was $15, $11–21), about 1¾ hours. Opus's list price is exactly twice Sonnet's on every
token rate.

| | Sonnet (cascade2, 21 tasks) | Opus (cascade3-opus, 24 tasks) |
|---|---|---|
| Haiku alone | 53/63 (84%) | 60/72 (83%) |
| after escalation | 62/63 (98%) | 67/72 (93%) |
| escalations | 9 | 11 (8 on a failed run, 3 on a passed one) |
| rescues of a failed run | 9/9, $0.72 each | 7/8, $1.57 each |
| total | $8.31 | $15.98 |

Per task, on the runs both escalated (all "reply cut off at the output limit"): rd10 Opus $0.58 vs Sonnet $0.39; rd12
$1.39 vs $1.02 a run; rdh03 $1.93 vs $0.69, with more steps (16–26 vs 8–16). rd04 #1's Opus run hit the per-run
cost limit ($2) at 23 steps and failed; rdh03 #3's hit it too but had already passed. Opus rescued no run Sonnet
couldn't, so on this set it costs 2.2× as much per rescue for a slightly lower rescue rate. **Decided (the user,
2026-10-30): the shipped pool's frontier entry is now Sonnet** (`ModelPool.shipped`, main and reviewer).

The lower final rate is mostly Haiku's misses on kkq02 and kkq03 (4 failed runs, none escalated: lookups, which change
no files, so neither the project's tests nor "changed nothing" can fire on them), against 1 such miss in cascade2.

The three escalations of a passed run, all from the 11b suite trigger:

- **kk01 #3, a harness bug** (exit 127). The after-run check (`AgentLoop.runCheck`) runs the test command through the
  run's persistent shell, which the model had left in `AgentCore/` with a `cd`; `sh run-tests.sh` lives at the root.
  Opus found it and changed nothing ($0.30). Fixed 2026-10-30: the check runs from the project's root.
- **rdw02 #3, a real catch.** Haiku's new test was flaky (three errors in a row stop a job, and whether they come in a
  row depends on which concurrent request finishes first); gold's single run passed by luck. Opus fixed the test
  ($0.33).
- **rd05 #1, not reproduced.** Opus ran the suite four times, all green, and changed nothing ($0.50).

3b02e0b's changes didn't come up: no run escalated after a review, and none stopped having changed no files.

### Public repositories (2026-10-30, free): sets `pkg` and `sqg`

The user's decisions: tasks from a public third-party repository, to test transfer beyond the user's own code and to
add router labels; about $12 for the round; third-party code runs only inside the eval's sandbox. Shortlisted from
eight active pure-Python projects; mined (source and tests changed, 20–150 source lines, 1–7 files, after
2026-06-01) click 26, packaging 28, sqlglot 225. click was left out (22 of its 26 by one author, with reverts).

| set | tasks | repository | suite |
|---|---|---|---|
| `pkg` | pkg01 78d8673 `VersionRange.relation`, pkg02 ffced26 `__replace__`, pkg03 ba0188d `SpecifierSet` relations, pkg04 959bb79 dependency-group errors, pkg05 23669b1 `Pylock.select` checks, pkg06 2068340 `from_email` errors, pkg07 4c362e3 `parse_tag` limit, pkg08 e7f0351 post-release boundaries | pypa/packaging (7 authors in the window) | 62k tests, about 30 s |
| `sqg` | sqg01 d17c768 BigQuery transpiles, sqg02 5b949bd Oracle physical/storage properties, sqg03 ad8764a `replace_placeholders` grouping, sqg04 1a0fc42 MySQL `ALTER` order | tobymao/sqlglot (59 authors) | 1,200 tests and 16k subtests, about 30 s, without the optimizer, executor and C-build tests (they need duckdb, pandas, setuptools) |

- **Environment**: a new pyenv virtualenv `pubtasks` (Python 3.13.14) with pytest, hypothesis, pretend, tomli_w,
  python-dateutil, pytz and typing_extensions; airr is untouched. sqlglot's test command puts the env's `bin` first on
  PATH (one test spawns `python`). packaging's adds `-W ignore::pytest.PytestRemovedIn10Warning` (pkg08's parent
  passes an iterator to parametrize, which pytest 9.2 refuses under the repository's `filterwarnings = error`) and
  `--hypothesis-seed=0`.
- **Validated sandbox-only** (`validate_task.py --sandbox-only`, the user's rule for third-party code), twice each
  step: all 12 valid. In pkg04, pkg06, sqg01 and sqg03 the old suite fails at gold, because the commit also changed old
  tests that expected the old behavior; the failing tests are all in the hidden files, and those prompts ask for the
  old tests to be updated. A run that doesn't update them still passes gold but may get a false escalation from 11b.
- **Hidden-test change**: pkg04's spy on the private `_resolve` asserted its new arity; the hidden copy now checks the
  call by its first two arguments only (implementation-agnostic, as the selection rules ask).
- **Left out**: sqlglot commits tagged [CLAUDE], [CODEX] or GPT (sqg01 was first 54005bf, tagged [CLAUDE] past the
  mining script's truncated subject). Two packaging commits say they were AI-assisted (pkg04, pkg06).
- **Fixtures**: `pkg` committed (2.8 MB); `sqg`'s are 6 MB each, gitignored, rebuilt by `build_sqg.sh` (a shallow
  clone from github.com).
- **Next**: the user reviews the 12 prompts (`spike/real-set-2/PROMPTS_FOR_REVIEW.md`); then the pilot (Haiku, one
  trial each, 200k context, ≈$0.5), Main (ling, deepseek-off, Haiku, three trials, ≈$4–5) and the Haiku→Sonnet cascade
  (≈$5), each asked first.

### Public-repository pilot (2026-10-30, paid, approved): Haiku on `pkg` and `sqg`

`kurtkode-eval --bank pkg01,…,sqg04 --models openrouter:anthropic/claude-haiku-5.5 --trials 1 --record real3 --context
200000 --max-tokens 16384 --skills builtin --no-train --max-cost 1 --parallel-remote 2`. Log
`spike/real-set-2/pub-pilot.log`. **$0.42** (list), about 25 minutes. **11 of 12 passed** after the two fixes below.

| task | steps | $ | | task | steps | $ |
|---|---|---|---|---|---|---|
| pkg01 | 36 | 0.068 | | pkg07 | 10 | 0.008 |
| pkg02 | 15 | 0.017 | | pkg08 | 15 | 0.020 |
| pkg03 | 10 | 0.012 | | sqg01 | 7 | 0.020 (fail: reply cut off at the output limit, no report; 34 hidden subtests fail) |
| pkg04 | 12 | 0.012 | | sqg02 | 37 | 0.074 |
| pkg05 | 9 | 0.005 | | sqg03 | 49 | 0.153 |
| pkg06 | 13 | 0.014 | | sqg04 | 16 | 0.014 |

- **Gold ran the suite outside the sandbox** (`TaskBank.suite`, plain zsh), against the user's rule for third-party
  code: the pilot's 12 gold checks of packaging's and sqlglot's suites, with Haiku's changes, ran unsandboxed. Fixed: a
  set's `gradeInSandbox` runs gold's suite under `SandboxPolicy()` (`aSandboxedSuiteCanWriteOnlyInTheFixture`); `pkg`
  and `sqg` set it, and the pilot was re-graded that way (`--regold real3`, log `pub-pilot-regold.log`).
- **pkg06's hidden `test_from_email_keeps_non_metadata_validation_errors` dropped**: it replaces `Metadata.from_raw`
  to see `from_email` call it, so a correct fix that validates through a private helper fails it (Haiku's did). It
  pins how the fix is written, which the selection rules exclude. Re-graded, pkg06 passes.
- **What it says**: Haiku passes these more easily than the user's own repositories (11/12, $0.035 a run, against 7/11
  in the first pilot at 32k). The spread rule (at least 5 tasks Haiku fails) isn't met by Haiku alone; Main's cheap
  models decide whether the sets separate the tiers. The one failure is runaway reasoning on the biggest prompt.

### Public-repository Main (2026-10-30, paid, approved): three models on `pkg` and `sqg`

The pilot's command with `--models` Haiku, deepseek-off and ling, `--trials 3 --max-cost 6 --models-at-once 3
--parallel-remote 1`. Log `spike/real-set-2/pub-main.log`, runs in `eval-results/runs/real3`. 96 new runs (Haiku's
first trial is the pilot's), **$3.16** (list), under 3 hours. All gold checks ran in the sandbox. With the pilot, this
round has spent $3.58 of its $12.

| task | Haiku | deepseek-off | ling | | task | Haiku | deepseek-off | ling |
|---|---|---|---|---|---|---|---|---|
| pkg01 | 3/3 | 1/3 | 0/3 | | pkg07 | 3/3 | 3/3 | 3/3 |
| pkg02 | 3/3 | 3/3 | 1/3 | | pkg08 | 2/3 | 2/3 | 0/3 |
| pkg03 | 3/3 | 3/3 | 3/3 | | sqg01 | 0/3 | 0/3 | 0/3 |
| pkg04 | 3/3 | 3/3 | 0/3 | | sqg02 | 2/3 | 1/3 | 0/3 |
| pkg05 | 3/3 | 3/3 | 3/3 | | sqg03 | 3/3 | 0/3 | 0/3 |
| pkg06 | 3/3 | 2/3 | 0/3 | | sqg04 | 3/3 | 3/3 | 1/3 |

| model | `pkg` | `sqg` | all | $ a run | $ a success |
|---|---|---|---|---|---|
| Haiku | 23/24 | 8/12 | 31/36 (86%) | 0.031 | 0.036 |
| deepseek-off | 20/24 | 4/12 | 24/36 (67%) | 0.060 | 0.090 |
| ling | 10/24 | 1/12 | 11/36 (31%) | 0.008 | 0.027 |

All 42 failures were checked against the stored runs (changed files, failing tests, last steps, gold's notes). All 66
passes changed source, and none left a stray file. None of the failures is a grading fault:

- **31 of the 42 changed no files.** The tools worked; the models never got to an edit. How the 42 ended:

  | ended by | Haiku | deepseek-off | ling |
  |---|---|---|---|
  | reply cut off at the output limit | 5 | 2 | 8 |
  | 60-step limit | 0 | 9 | 14 |
  | repetition stop | 0 | 0 | 2 |
  | finished, wrong | 0 | 1 | 1 |

- **All 5 of Haiku's failures are cut-off replies with no files changed**: runaway reasoning again, the mechanism of
  the cascade rows. So the cascade should catch all of them, and a same-model retry would be tried on all of them.
- **ling and deepseek's 60-step failures are mostly exploring.** ling made no edit in 12 of its 14; on sqlglot it spent
  all 60 steps on `grep` and `sed`. deepseek also passes slowly (up to 60 steps on packaging), so a higher limit might
  help it; not tested.
- **One failure is correct code by the rule's letter**: pkg01 deepseek #1's suite passes, but it left its scratch file
  `apply_edits.py` at the root, outside `mayChange`, and hit the step limit before cleaning up. Left as a failure, as
  in the other rows. sqg03 deepseek #3 left one too, but its tests also fail.
- **"Existing tests kept" adds nothing here.** It failed on pkg06 (2 runs) and sqg03 (1), both tasks where the prompt
  asks for tests to be updated, but each of those runs also fails the suite with the hidden tests.
- **sqg01 is 0/9, unproven below gold.** It validates, and it has the biggest prompt and diff of the `sqg` tasks (204
  lines). The nearest was deepseek #2, 10 of 34 fixed. The cascade will show whether Sonnet can do it.

What it says:

- **Haiku generalizes.** A new author's repositories give 86% at 200k, against 83–84% on the user's own Python and
  Swift. This is the third-repository check the survey said was missing, though it's one language.
- **sqlglot separates the tiers and packaging doesn't.** On `sqg` Haiku is 8/12, deepseek 4/12, ling 1/12; five `pkg`
  tasks are 3/3 for both Haiku and deepseek. sqlglot is 6.5× the code (84k lines against 13k) and its parser alone is
  10.7k lines. The spread rule (5 tasks Haiku fails) still isn't met: Haiku misses 3 tasks.
- **ling is the cheapest per success here ($0.027), for the first time, but fails 69%**. Failures cost the rerun and the
  user's time, which that figure leaves out. Bounded fixes pass (pkg03, pkg05, pkg07 are 3/3); it doesn't change the
  conclusion that the cheap tier is for small work.
- **Router labels**: 42 more failures take the count from 77 to 119, past the 100 the router waits on. These are at
  200k and the older ones at 32k, so they don't simply add.

### Public-repository cascade (2026-10-30, paid, approved): Haiku main runs, Sonnet on the product's escalation

The cascade command with `--bank pkg01,…,sqg04 --cascade openrouter:anthropic/claude-sonnet-5.5 --record cascade4-pub
--max-cost 8`, three trials. Log `spike/real-set-2/cascade-pub.log`. **$6.27** charged (key usage agrees, $6.28), about
an hour; the estimate was $5, so 25% over and under the cap. That makes this round $9.85 of its $12. The escalations are
$4.99 of it (80%). Built from 2d4acf0 plus `gradeInSandbox`: the runs' `commit` field says 1e61445, which is where main
was, but the binary predates those commits. The model's commands, the after-run suite and gold all ran sandboxed.

| | Haiku alone | after escalation | offers | $ a run |
|---|---|---|---|---|
| `pkg` | 23/24 | 24/24 | 1 | 0.04 |
| `sqg` | 5/12 | 9/12 | 7 | 0.45 |
| all | 28/36 (78%) | 33/36 (92%) | 8 | 0.17 |

| task | Haiku's run | offer | Sonnet |
|---|---|---|---|
| pkg08 #3 | failed, cut off, 5 steps | cut off | passed, $0.29 |
| sqg01 #1 | failed, cut off, 13 steps | cut off | passed, but stopped by the $2 run limit, $2.01 |
| sqg01 #2 | failed, cut off, 9 steps | cut off | **failed**, cut off, 5 steps, no change, $0.72 |
| sqg01 #3 | failed, cut off, 10 steps | cut off | **failed**, cut off, 3 steps, no change, $0.43 |
| sqg02 #1 | **passed**, 49 steps | 1 todo unfinished | passed, added two test checks, $0.41 |
| sqg02 #3 | failed, cut off, 19 steps | cut off | passed, $0.28 |
| sqg03 #1 | failed, cut off, 25 steps | cut off | passed, $0.49 |
| sqg03 #2 | failed, cut off, 25 steps | cut off | passed, $0.35 |
| sqg03 #3 | failed, finished, 39 steps | **none** | not run |

All 36 were checked by hand. All 33 final passes changed source and left no stray file. No run hit a setup fault. The
3 final failures are real:

- **sqg03 #3 is a silent failure.** Haiku's 125-line change passes the visible suite, and it reported success; one
  hidden subtest fails (`x >= ALL(:x)`, a case the prompt names). No grounded signal can see that.
- **sqg01 #2 and #3 are Sonnet cut off too.** Each spent all 16,384 output tokens on reasoning and changed no files.
  It's the first time the escalation target has hit this, and each cost more than a full rescue elsewhere. Earlier
  Sonnet rescues were 9 of 9; here 5 of 7.

What it says:

- **The cascade holds on `pkg` and strains on sqlglot.** Sonnet took `sqg` from 5/12 to 9/12, at about 12× the cost of
  `pkg` a run. The overall 92% is below the 98% on the user's repositories, and sqg01 accounts for 2 of the 3 misses.
- **sqg01 is solvable**: Sonnet's 175-line change passes every hidden test, so the task isn't broken. It's hard: Haiku
  has been cut off on it 6 times out of 6.
- **Runaway reasoning stays the main trigger**: 7 of 8 offers. Those 7 are all of Haiku's cut-offs, and all 7 failed.
- **A same-model retry wouldn't work everywhere.** pkg08, sqg02 and sqg03 cut Haiku off some of the time, so a retry
  could pass. sqg01 cuts it off every time, so a retry there would only add to the bill.
- **A bigger output limit is worth testing for the escalation target.** 16,384 is this eval's setting, and it stopped
  Sonnet twice. Whether more room finishes the work or just spends more isn't known. sqg01 #1 suggests the task can
  need the $2 limit as well.
- **Run mode or noise moved Haiku on `sqg`:** 8/12 as a subagent in Main, 5/12 as a main run here. sqg03 went from 3/3
  to 0/3. Three trials can't separate the two.

## A second language from another author (planned 2026-11-02; built, pilot and Main run)

REAL_TASKS_SURVEY.md's first gap: `pkg` and `sqg` showed Haiku holds up on another author's code (86%), but both are
Python, and kurtkode, the only other language, changes repository and language at once. A public repository in a
third language, by other authors, separates the two. Everything below is free until the paid rows, and nothing is
downloaded until the user says so.

### Language: Go

- **It keeps third-party code inside the sandbox most easily.** Building a Go package runs none of its code: there are
  no build scripts (Rust's `build.rs`) and no install hooks (npm's `postinstall`), and `go generate` runs only when
  asked. Fetching modules only downloads source. Tests run only through `go test`, which runs in the sandbox like
  every other command.
- **It runs offline.** Many active Go libraries depend only on the standard library. When a library does have
  dependencies, `go mod vendor` (a download, run outside the sandbox) puts them in the fixture, and
  `GOFLAGS=-mod=vendor GOPROXY=off` keeps them there. `GOTOOLCHAIN=local` stops a `go.mod` `toolchain` line from
  downloading another Go.
- **The suites are fast**, usually seconds, so validating twice and three trials cost little time.
- **Its style differs from both earlier languages**: typed like Swift, with explicit error values and table-driven
  tests, so a drop here can't be put down to Swift alone.
- **TypeScript is the second choice.** It's closer to what many users write, but the installed Node is 18 (too old
  for most current repositories), `node_modules` would be fetched into each fixture, and install scripts would have to
  be turned off (`--ignore-scripts`) and checked. That set would come after this one.

Go isn't installed. The plan uses the official darwin-arm64 tarball from go.dev, about 70 MB, unpacked into
`~/sdk/go`. That needs no password and changes nothing system-wide. The `.pkg` installer would write to `/usr/local/go`
and need a password; Homebrew would add a formula the user didn't ask for.

### The first check: does a Go command work in kurtkode's sandbox?

This check runs first, because it's likely a product gap and not only an eval one. Go keeps its build cache in
`~/Library/Caches/go-build` (`os.UserCacheDir`). The sandbox lets commands write the workspace, the temporary folder,
the per-user cache folder (`CACHEDIR`, under `/var/folders`) and `/private/tmp`, but not `~/Library/Caches`. So a model
that runs `go test` the way a Go user would probably gets "could not create build cache". npm's `~/.npm` and Cargo's
`~/.cargo` have the same problem.

- **Free check**, with the toolchain installed: `go test ./...` on a standard-library-only repository through
  `spike/real-set-2/insandbox.sh`, once without environment variables and once with `GOCACHE` and `GOMODCACHE` under
  the temporary folder.
- **If it fails**, the fix is in the product, not in the set's test command. Otherwise every real Go user hits it,
  and the eval would hide it. There are two options:
  1. Set `GOCACHE`, `GOMODCACHE`, `npm_config_cache` and `CARGO_HOME` under `CACHEDIR` in the sandboxed shell's
     environment, where the user hasn't set them. This is narrow; the user's own caches stay unwritable.
  2. Let the sandbox write those named cache folders. This is simpler, but a model could then plant something in a
     cache that the user's unsandboxed builds read later.

  I'd take option 1, with a unit test and a Round 8 style probe. It's built and committed before any task.

### Repositories

The same rules as `pkg` and `sqg`: public; at least five authors in the window; commits after 2026-06-01 that change
both source and tests, with 20–150 source lines over 1–7 files; none tagged as AI-written; and a suite that runs in
the sandbox in under five minutes. **Two repositories**, as before: one mid-sized (like packaging, 13k lines) and one
large, parser- or compiler-like (like sqlglot, 84k lines). sqlglot was the one that separated the tiers.

Shortlist to mine, standard-library-only or nearly, as far as known before cloning (activity since June isn't known
from here; mining settles it):

| repository | kind | why it's on the list |
|---|---|---|
| expr-lang/expr | expression language: parser, checker, compiler, VM | sqlglot's shape: grammar plus semantics, many contributors |
| yuin/goldmark | Markdown parser (CommonMark) | spec-driven tests, extension API, no dependencies |
| goccy/go-yaml | YAML parser and encoder | large parser, many edge-case fixes |
| BurntSushi/toml | TOML parser | small and strict; a packaging-sized option |
| pelletier/go-toml (v2) | TOML parser | alternative to the above |
| go-chi/chi | HTTP router | no dependencies; middleware fixes |
| spf13/cobra | CLI library | one dependency (pflag), heavily used |
| itchyny/gojq | jq in Go | compiler-like, but mostly one author, so it may fail the author rule |

Mining is a shallow, blob-less clone of each since 2026-05-01 (`git clone --filter=blob:none --shallow-since`, as in
`build_sqg.sh`), a few MB each. It reads history only and runs nothing.

### Building and measuring

- **Tasks**: 8–12, a set name per repository (e.g. `exp`, `gmk`). Hidden-test shape, with `gradeInSandbox: true` and
  the test command `GOTOOLCHAIN=local GOPROXY=off GOFLAGS=-mod=vendor go test ./...` (`-mod=vendor` only where there
  are dependencies). Built with `build_task.py` and validated with `validate_task.py --sandbox-only`, twice. A
  `build_<set>.sh` rebuilds any fixture too large to commit.
- **Harness**: likely nothing new. `testCommand` is any shell command. `go` must be on the sandboxed shell's PATH; if
  that needs a set-level setting, it's small and gets a test.
- **Prompt review** by the user, as for `pkg` and `sqg` (`PROMPTS_FOR_REVIEW.md`).
- **Paid rows**, the same three as the public round, at 200k context, each with `--max-cost`. The estimates scale from
  that round ($9.85 for 12 tasks); Go fixtures are smaller than sqlglot's, so this may come in under them:

| row | models | trials | estimate |
|---|---|---|---|
| Pilot | Haiku | 1 | ≈$0.5 |
| Main | ling, deepseek-off, Haiku | 3 | ≈$3–5 |
| Cascade | Haiku main runs → Sonnet | 3 | ≈$5–6 |

- **What it decides**: whether Haiku's 83–86% holds in a third language by other authors; whether the cheap tier's
  failure pattern (fine on bounded fixes, failing on large parsers) is about size or about Python; and up to 50 more
  router labels at 200k, which would let the router be judged on 200k rows alone (now 42).

### Order of work

1. **The user's go-ahead for the downloads**: the Go tarball (about 70 MB, go.dev) and the mining clones (a few MB
   each, github.com).
2. The sandbox check, and the product fix if it fails, committed with tests.
3. Mine the shortlist; pick two repositories, then the tasks; build and validate them sandbox-only.
4. The user reviews the prompts.
5. Pilot, Main and cascade, each mentioned before it runs (each under $20), with hand checks of every failure.
6. Write-up here and in REAL_TASKS_SURVEY.md.

### Progress (2026-11-02, free)

- **Go 1.27.3** is in `~/sdk/go`: the official tarball, checksum checked against go.dev's listing.
- **The sandbox check failed, as expected, and is fixed.** A plain `go test` in the sandbox stopped with "failed to
  initialize build cache at ~/Library/Caches/go-build: operation not permitted". `SandboxPolicy.cacheVariables` now
  points `GOCACHE` at `kurtkode/go-build` in the per-user cache folder for sandboxed commands, unless the environment
  sets it. It's used by the bash tool (foreground and background) and by gold's sandboxed suite. The test is
  `goGetsABuildCacheItCanWrite`. `GOMODCACHE` is left alone: writing it only matters when downloading, which the
  sandbox blocks anyway, and redirecting it would hide a user's existing module cache. npm, Cargo and pip weren't
  checked, so they aren't changed. **Not committed.**
- **Second sandbox gap, not fixed (the user's call):** the sandbox's `deny network*` also blocks binding a localhost
  port, so Go's `httptest` servers fail (chi: `listen tcp6 [::1]:0: bind: operation not permitted`). Any project whose
  tests start a local server fails the same way, in any language. Allowing loopback bind and connect would fix it, but
  it would also let commands reach every local service (LM Studio's API, databases), so it's a design decision. Until
  then, tasks avoid packages whose tests listen.
- **Mining** (a scratch script, not kept): 16 repositories cloned without blobs, since 2026-05-01 (goccy/go-yaml had
  no commits in that window).

| repository | commits since June | authors | non-test lines | candidates | notes |
|---|---|---|---|---|---|
| open-policy-agent/opa | 642 | 63 | 183k | 147, none AI-tagged | the large one: Rego parser, compiler (`ast`), evaluator (`topdown`); 126 modules in go.sum; has an AGENTS.md |
| google/cel-go | 42 | 13 | 6.5k in the root module (more in submodules) | 17 | the mid one: CEL parser, checker, interpreter; 2 direct dependencies; 7 candidates from outside authors |
| hashicorp/hcl | 62 | 10 | 32k | 6 | two are "wip" commits |
| bufbuild/protocompile | 37 | 8 | 85k | 13 | |
| go-chi/chi | 35 | 16 | 6k | 4 after AI tags | tests listen on localhost |
| yuin/goldmark, pelletier/go-toml, mvdan/sh, cue-lang/cue | | | | | almost all candidates from one author (go-toml's mostly AI-tagged) |
| expr-lang/expr, spf13/cobra, traefik/yaegi, BurntSushi/toml, goccy/go-yaml | | | | | inactive since June |

- **Choice: OPA (large) and cel-go (mid).** Both are languages with a parser, a type checker and an evaluator, which
  is sqlglot's shape. Both have many authors and fixes that come with tests. OPA's AGENTS.md says AI-assisted commits
  happen there without tags, so its candidates get the same reading for AI-written prose that sqlglot's did.
- **Next needs a download**: their Go modules (`go mod download` into a dedicated `GOMODCACHE`, outside the sandbox;
  it fetches source and runs none). The model's shell and gold then read that cache with `GOPROXY=off`,
  `GOFLAGS=-mod=mod`, set in kurtkode-eval's environment. cel-go is about 11 modules. OPA's go.sum lists 126, likely a
  few hundred MB, fewer if only the `v1/ast` and `v1/topdown` test dependencies are fetched.

### Modules and suites in the sandbox (2026-11-02, free)

- **Modules**: `go mod download` for cel-go (at a492a70) and OPA (at HEAD) went to `~/sdk/gomodcache`, 512 MB in all,
  with `GOPATH` and the host `GOCACHE` under `~/sdk` too, so nothing went into `~/go` or `~/Library/Caches`. Each
  task's parent needs its own `go mod download` when it's built, since its `go.mod` pins older versions. The sandbox
  can read that cache but not write it, so a model can't plant anything there. Leave `GOFLAGS=-mod=mod` out: with it,
  `go` rewrote cel-go's `go.mod`, which a fixture would count as a change.
- **The environment** for the model's shell and gold, set in kurtkode-eval's own environment (the bash tool starts
  from it): `PATH=~/sdk/go/bin:…`, `GOTOOLCHAIN=local`, `GOPROXY=off`, `GOMODCACHE=~/sdk/gomodcache`. `GOCACHE` comes
  from the product fix.
- **cel-go moved** to `cel.dev/cel-go` in September 2026; google/cel-go now only forwards to it. Its candidates
  (June–July) are still usable at their own commits. At a492a70 the whole suite passes in the sandbox in 15 s.
- **OPA**: `go test ./v1/ast/... ./v1/topdown/... ./v1/format/... ./v1/bundle/...` passes in the sandbox in about 6 s
  uncached (19 s with a cold build), with 54 tests skipped (`spike/real-set-2/opa-sandbox-skip.txt`). Those tests open
  a localhost port (`httptest`) or look up DNS. A listening test's panic takes its whole package down, so the skip
  list is needed. It's the localhost gap above, the same kind of list as kurtkode's 19.

### Task shortlist (read, not built)

Fixes with a clear, testable behavior, mostly from outside authors. Each prompt gives the behavior; none names a
private helper.

| set | commit | author | what the fix does |
|---|---|---|---|
| `cel` | af38f75 | pranit more | constant folding of `x in [x]` is wrong for NaN doubles |
| `cel` | 41d9149 | alhuda | `timestamp()` accepts strings that aren't RFC 3339 |
| `cel` | be9dacd | William Yang | ASTs loaded from protos skip the parser's depth limit and can blow the stack in Check/Plan |
| `cel` | 13cff33 | marwan9696 | `lists.range(N)` has no size limit and accepts negatives |
| `cel` | 0175dbb | Tristan Swadell | folding `&&`/`||` can produce a non-bool |
| `opa` | f6e3d5d0 | Oleksii Udovychenko | single- and multi-value rules on disjoint ref heads are rejected as conflicting |
| `opa` | 01eefbab | Manas Choksi | partial evaluation panics on a negated rule whose body has `every` |
| `opa` | 85b62162 | Balachandran | `net.cidr_contains` misses IPv6 subnets ending at `::ffff:ffff:ffff` |
| `opa` | 63f54da4 | Yuzhong Zhang | `some i, x in xs[i]` compiles although the binding is in its domain |
| `opa` | ae4ed955 | Sueun Cho | `semver.is_valid` accepts leading zeroes and empty pre-release or build parts |
| `opa` | 23745504 | Sebastian Spaink | sibling leaves of a general ref are rejected as recursive |

Reserves: cel-go 83eed56 (JSON field `-`), 14f6746 (`indexOf` offsets); OPA cb0081cd (`units.parse` bound),
dc7eb3c9 (parse error position), 09397a34 (checker types).

### The 11, built and validated (2026-11-02, free)

Sets `cel` (cel01–05) and `opa` (opa01–06) in `eval-results/real-fixtures/`, in the shortlist's order. The fixtures
are gitignored (1.7 MB and 5 MB each) and rebuilt by `spike/real-set-2/build_go.sh`. The prompts are in
`PROMPTS_FOR_REVIEW.md`, section "Go sets".

- **Tooling for tests beside the code.** `build_task.py --tests` may repeat and take git pathspec magic (the Go sets
  use `:(glob)**/*_test.go` and `:(glob)**/testdata/**`). `--mod-download` fetches the parent's modules into
  `GOMODCACHE`. In the harness, a set's `testsPath` may be such a pathspec: "existing tests kept" then restores the
  original test files one by one, and a run's new test file that declares a top-level Go function or type that a
  hidden file also declares is set aside like a clashing Swift type. Test:
  `goTestsBesideTheCodeAreKeptAndClashesSetAside`.
- **Suites.** cel: `go test -count=1 -skip '^TestConcurrentEval$' ./...`. That test times out now and then when the
  machine is busy (1 run in 12 on cel01's parent), and no task touches it. opa: `sh run-tests.sh` (from
  `opa-run-tests.sh`), the core packages with the 54 tests that need a port or DNS skipped. The environment
  (`PATH`, `GOTOOLCHAIN=local`, `GOPROXY=off`, `GOMODCACHE`) is kurtkode-eval's own; see "Modules and suites" above.
- **Hidden-test changes** (`go_hidden_fixes.py`, run by `build_go.sh`): cel02 drops a test of a private pattern;
  cel04's test of the private `genRange` becomes the same checks through `lists.range()` and `ListsMaxRangeSize`;
  opa02 drops a test of a private helper the fix renamed.
- **Upstream test fixes laid on older parents**, so their suites run in the sandbox (as kk carries 28e9843's hang
  fix): cel02 and cel03 get 12328e5 (`json.encode` order, which failed ext's TestEncoders now and then); opa05 and
  opa06 get b9a27784 (v1/topdown's test server started at init, which failed the whole package) and 517c5cb3 (the
  cases that use it moved out of TestTopDownPartialEval).
- **Validated sandbox-only**, three gold runs by each route: every task fails before the fix, passes at gold all six
  times, and its parent's own suite passes. The machine's load was 125–187 during the final pass. In cel01, cel05 and
  opa02 the old suite fails at gold: cel01 and cel05 changed old expectations (their prompts ask for those to be
  updated, as pkg04's do), and opa02's old test calls the private helper the fix renamed. A run that renames it and
  doesn't update that test may draw a false offer from 11b.
- **Sizes**: solutions 21–95 lines over 1–4 files; cel03 (new API in two packages) and opa06 (compiler and planner)
  are the largest.

### Pilot (2026-11-03, paid, approved): Haiku on `cel` and `opa`

`kurtkode-eval --bank cel01,…,opa06 --models openrouter:anthropic/claude-haiku-5.5 --trials 1 --record real4 --context
200000 --max-tokens 16384 --skills builtin --no-train --max-cost 1 --parallel-remote 2`, started with `~/sdk/go/bin` on
PATH, `GOTOOLCHAIN=local`, `GOPROXY=off` and `GOMODCACHE=~/sdk/gomodcache`, from a release build of main 75641ac. Log
`spike/real-set-2/go-pilot.log`. **$0.30** (list), about 40 minutes of runs. It first waited 7¾ hours on the Keychain
dialog the rebuilt binary raised, and started when the user allowed it. **11 of 11 passed** after the fix below.

| task | steps | $ | | task | steps | $ |
|---|---|---|---|---|---|---|
| cel01 | 23 | 0.026 | | opa01 | 18 | 0.020 |
| cel02 | 20 | 0.017 | | opa02 | 16 | 0.011 |
| cel03 | 22 | 0.028 | | opa03 | 23 | 0.042 |
| cel04 | 14 | 0.011 | | opa04 | 22 | 0.028 |
| cel05 | 16 | 0.031 | | opa05 | 25 | 0.017 |
| | | | | opa06 | 60 | 0.074 (step limit, no report; passes re-graded) |

- **opa06's hidden `TestCompilerGetRulesDynamic` narrowed too much**: upstream made the recursion check precise by
  narrowing the public `GetRulesDynamic`, so five r6 cases expect `data.c.d.r6.a.foo.bar` and the like to return only
  the matching sibling. The prompt asks for the recursion check and the planner, not the lookup. Haiku fixed the
  check inside `checkRecursion`, and every hidden recursion and planner test passed; only those five cases failed
  (re-run in the sandbox on its saved workspace). They pin how the fix is written, so `go_hidden_fixes.py` drops them
  and keeps the two r6 cases that hold either way. Revalidated sandbox-only (fails before, gold passes twice), and the
  pilot re-graded (`--regold real4`, log `go-pilot-regold.log`, no model calls): opa06 fail → pass.
- **opa06 still ran out of steps**: 60 steps and no report. Its tests were written and checked to fail without the
  fix, and the CHANGELOG entry was next. Gold grades the suite, so it passes; the missing report shows in its checks.
- **`validate_task.py` needs `GOCACHE` set** for Go, because it runs `insandbox.sh` directly, not the product's
  sandbox: `GOCACHE="$(getconf DARWIN_USER_CACHE_DIR)kurtkode/go-build"`.
- **What it says**: Haiku passes the Go sets as easily as `pkg` and `sqg` (11/11, $0.028 a run). The spread rule (at
  least 5 tasks Haiku fails) isn't met by Haiku; Main's cheaper models decide whether the sets separate the tiers.

### Main (2026-11-03, paid, approved): three models on `cel` and `opa`

The pilot's command with `--models` Haiku, deepseek-off and ling, `--trials 3 --max-cost 6 --models-at-once 3
--parallel-remote 1`, in the same environment. Log `spike/real-set-2/go-main.log`, runs in `eval-results/runs/real4`.
88 new runs (Haiku's first trial is the pilot's), **$4.45** (list), about 3¼ hours; no Keychain prompt this time. With
the pilot, the Go round has spent $4.75. All gold checks ran in the sandbox.

| model | passed | $ per run | | `cel` | `opa` |
|---|---|---|---|---|---|
| Haiku | 31/33 (94%) | 0.030 | | 15/15 | 16/18 |
| deepseek-off | 24/33 (73%) | 0.104 | | 10/15 | 14/18 |
| ling | 11/33 (33%) | 0.011 | | 7/15 | 4/18 |

By task (trials 1–3; F is a fail):

| task | Haiku | deepseek-off | ling |
|---|---|---|---|
| cel01 | P P P | P P P | F F P |
| cel02 | P P P | P P F | F F F |
| cel03 | P P P | F F F | F F P |
| cel04 | P P P | P F P | P P P |
| cel05 | P P P | P P F | F P P |
| opa01 | P P P | P P P | F F F |
| opa02 | P P P | P P P | F F F |
| opa03 | P F P | P P P | F F P |
| opa04 | P P P | P P F | F F F |
| opa05 | P P P | P P P | P P P |
| opa06 | P F P | F P F | F F F |

**Every failure was checked by hand**, the 11 that changed code by re-running the hidden tests on the run's saved
workspace in the sandbox. 32 of 33 are real; one was a flake:

- **21 changed no files**: 60 steps used up exploring, a reply cut off at the output limit (Haiku's opa03 #2 at step
  11, the runaway reasoning seen in sqg01), or a repetition stop. Ling has 17 of them.
- **cel02** (deepseek-off #3): the strict check rejects valid timestamps with fractional seconds.
- **cel03** (deepseek-off #1 and #2, ling #1): `env.Program` also rejects deep ASTs built straight through
  `common/ast`, which the prompt says aren't checked; ling #2 exports the limit from every environment's `ToConfig`,
  breaking the existing `TestEnvToConfig`; deepseek-off #3 cut off before writing anything.
- **cel04** (deepseek-off #2): its own `lists.go` doesn't compile (`int64` passed as `types.Int`).
- **opa03** (ling #2): `net.cidr_contains` still gives wrong results on three of the new IPv4-mapped cases.
- **opa06**: deepseek-off #1 and #3 changed only the compiler, so the planner recurses until the stack overflows, as
  the prompt warns; Haiku #2's planner change panics (index out of range) on the `with` mock case.
- **The flake**: ling's cel04 #1 failed gold, but cel's whole suite passes on its workspace six times in a row, and
  re-graded alone (`--regold` on a copy) it passes twice. Its record in `real4` is the re-graded one. Gold's note
  keeps only the last 300 characters of the suite's output, which didn't name the failing test, so which test
  flaked under Main's load is unknown. Keeping the `--- FAIL` lines in gold's note would have shown it.

**What it says**:

- **Haiku's rate holds in Go** (94%, against 86% on `pkg` and `sqg` and 83–86% on the user's own repositories), and
  so does the cheap tier's order: deepseek-off 73% (67% on `pkg`/`sqg`), ling 33% (31%). The sets separate the tiers
  as the Python ones do, so the failure pattern isn't about Python.
- **Size still decides for the cheap tier**: the two-part tasks (cel03's new API in two packages, opa06's compiler and
  planner) are where deepseek-off fails, and ling fails all of `opa`'s compiler work. The bounded fixes (cel04, opa05)
  pass for all three.
- **Spread rule**: Haiku fails only 2 of 33, so it still isn't met by Haiku; the cheap tier meets it.

**Next**: the cascade (Haiku's main runs → Sonnet). With only two Haiku failures here, it would show little: it was
estimated at ≈$5–6 and would cost far less, but would add at most two escalations. Up to 50 router labels at 200k
are the other reason to run it.

**What the rounds decide (2026-11-04):** COST_AUDIT.md section 12. In short, more tasks of this shape would only
re-confirm the tier conclusions; what's open needs analysis, two small targeted runs, or real-sized lookups.

**Grading fixes (2026-11-03, after Main):** BUG_HUNT_2026-11-02.md's P3 items are fixed (its "Status: P3 fixed"
section). Gold now measures a run's change from the fixture's base commit, runs its checks without the user's shell
profile and its suite in a process group of its own, and keeps the failing tests' lines in its note. Runs recorded
before keep their grades: four of `real4`'s Go runs (two passes, two failures) re-graded the same, with notes that now
name the failure. Runs recorded from here on carry their options' fingerprint, and a set won't resume under others.
