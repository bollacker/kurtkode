# Evaluation results: subagents and their judges

Run 2026-10-24 and 25 by EVAL_PLAN.md. The full generated tables are in `eval-results/bank1-report.md`; the run store
is `eval-results/runs/bank1/` (1,071 runs, 59 MB); the logs are `eval-results/*bank1*`, `judge*`, `delegation-*`
and `regold*`. The total spend was about **$30 at list price**, all on Gemini: $6.11 recording, $22.18 judging,
$1.79 delegation.

## Answers in brief

1. **Subagent models.** Every Gemini model passed all 102 runs (95% interval 96–100%). The local models passed
   81–89%. **The bank is too easy to rank frontier models**: it separates local models from Gemini, not Gemini
   models from each other.
2. **Judges.**
   - On the 262 runs every judge rated, **gemini-4-argon by the parent path was best**: agreement 86%, kappa 0.71.
     It caught 69% of the failures and failed none of the good runs.
   - The grader path catches less than the parent path for every Gemini judge (52–53% against 66–69%).
   - qwen3.5-9b as a grader wrongly failed 14% of good runs.
   - No judge favored its own model's runs.
3. **Grounded checks.**
   - The checks at the run's end catch 14% of failures; with the re-run check, 35%. Each falsely fails 1 good run
     in 190.
   - **They catch all of the undone work** (51/51, 18/18, 12/12) and none of the dropped list items or stray edits.
   - Combined with argon's parent rating they catch 76%.
   - What nothing catches is stray edits outside the task: 0 of 63, for every judge and check.
4. **Delegation.** **No model delegates on its own.** Across 4 parents, 3 scenarios where delegating helps and 3
   trials each, they delegated in 3 of 36 runs, and in 0 of 24 where it doesn't help.
   - Delegating didn't improve any outcome where it happened (gemma-4-26b still failed the survey both times).
   - The Gemini parents solved all five scenarios without delegating.
5. **Gold.**
   - Real runs exposed **three gold bugs**, which were fixed and re-scored with no model re-run (18 runs went from
     fail to pass).
   - Two candidate weak models couldn't be loaded at all, and their runs were removed as infrastructure failures.

## What ran, against the plan

| | Planned | Done |
|---|---|---|
| Bank | 34 tasks | 34 tasks; every gold check passes a right outcome and fails an idle, a plausibly wrong, and a stray-edit one (`TaskBankTests`) |
| Strong subagents | gemma-4-26b, qwen3.5-9b, gemini-3-flash, gemini-3.8-flash | gemma-4-26b, qwen3.5-9b, **gemini-3.6-flash**, gemini-3.8-flash, **gemini-4-argon**, 3 trials each. gemini-3-flash doesn't exist on this key |
| Weak subagents | gemma-4-e4b, bonsai 3.6B, gemini-2.5-flash | **gemma-4-e4b only**. Both ternary bonsai models fail to load in LM Studio (unsupported format); llama-3.2-3b, tried instead on bang, failed to load there too; gemini-2.5-flash is retired, and no "lite" Gemini id exists |
| Degraded copies | trial 1's passing runs | 332 kept (gold fails), plus 127 stray-edit copies of read-only tasks that the report leaves out (an explore agent can't edit) |
| Judges | 4 judges × 2 paths on trial 1's runs and copies | Gemini judges on all 536; **local judges on a fixed, balanced sample of 300** (`--sample`): the full set would have taken 5+ hours each |
| Delegation | 5 scenarios × 4 parents × 3 trials, with off-baselines | Done, with off-baselines for all five scenarios |

## 1. Subagent models

| model | pass rate (95% CI) | mean s | mean steps | tokens in/out | list $ per run |
|---|---|---|---|---|---|
| gemini-4-argon | 100% (96–100%) 102/102 | 19 | 3.6 | 8,180/513 | 0.0207 |
| gemini-3.8-flash | 100% (96–100%) 102/102 | 17 | 7.3 | 19,845/1,197 | 0.0195 |
| gemini-3.6-flash | 100% (96–100%) 102/102 | 12 | 7.3 | 19,850/1,322 | 0.0197 |
| gemma-4-26b (this Mac) | 89% (82–94%) 91/102 | 58 | 5.6 | 11,942/1,189 | – |
| qwen3.5-9b (bang) | 88% (81–93%) 90/102 | 32 | 5.7 | 16,422/971 | – |
| gemma-4-e4b (this Mac) | 81% (73–88%) 83/102 | 80 | 5.0 | 11,525/1,878 | – |

- **Where the local models fail**: research (gemma-4-26b and gemma-4-e4b each 6 of 9), review (gemma-4-26b 6/9),
  writing tests (both gemmas 4/6), and search (18/21). gemma-4-e4b also fails half of the edit tasks (3/6).
- **argon does the same work in half the steps and a third of the tokens** of the flash models, at about the same
  list price per run. For the router, cost per run and steps differ more than pass rates among strong models.
- **The bank needs harder tasks** before it can rank strong models, for example multi-file changes, longer
  investigations, and tasks with traps.

## 2. Judges

Pass means a verdict of 2–3; fail means 0–1. The failures are the real failed runs and the degraded copies. On the 262
runs every judge rated (118 of them failures):

| judge (path) | no verdict | agreement | kappa | failures caught (95% CI) | good runs failed (95% CI) | list $ |
|---|---|---|---|---|---|---|
| gemini-4-argon (parent) | 0 | 86% | **0.71** | 69% (61–77%) 82/118 | 0% (0–3%) 0/144 | 3.94 |
| gemini-3.8-flash (parent) | 2 | 85% | 0.68 | 66% (56–74%) 76/116 | 0% (0–3%) 0/144 | 2.52 |
| gemma-4-26b (parent) | 50 | 82% | 0.63 | 62% (52–71%) 60/97 | 1% (0–5%) 1/115 | – |
| qwen3.5-9b (parent) | 10 | 80% | 0.57 | 58% (48–67%) 63/109 | 3% (2–8%) 5/143 | – |
| gemini-3.8-flash (grader) | 0 | 78% | 0.53 | 53% (44–62%) 63/118 | 2% (1–6%) 3/144 | 0.67 |
| gemini-4-argon (grader) | 0 | 77% | 0.53 | 52% (43–61%) 61/118 | 1% (0–5%) 2/144 | 0.86 |
| gemma-4-26b (grader) | 3 | 77% | 0.51 | 52% (43–61%) 61/118 | 2% (1–6%) 3/141 | – |
| qwen3.5-9b (grader) | 0 | 74% | 0.47 | 60% (51–69%) 71/118 | **14% (9–20%) 20/144** | – |

**By kind of failure** (all runs each judge rated), for gemini-4-argon's parent path, the grounded checks, and the
smallest judge:

| failure | grounded checks | argon (parent) | argon (grader) | qwen3.5-9b (parent) |
|---|---|---|---|---|
| digits (wrong numbers, lines, names) | 28/101 | 94/100 | 87/101 | 30/32 |
| wrong-file | 10/44 | 44/44 | 44/44 | 11/14 |
| drop-half (list missing items) | 0/43 | 33/43 | 17/43 | 4/17 |
| undo-all | **51/51** | 51/51 | 32/51 | 13/13 |
| undo-half | **18/18** | 18/18 | 12/18 | 4/4 |
| vanish (new files deleted) | **12/12** | 12/12 | 5/12 | 6/6 |
| stray-edit (on change tasks) | 0/63 | 0/63 | 0/63 | 0/26 |
| real failures (the models' own) | 2/14 | 10/14 | 5/14 | 4/13 |

What this says:

- **The parent path beats the grader** for every Gemini judge, by about 15 points. The parent can read files and run
  the task's check, and hears the re-run's result; the grader sees only the cited lines. The gap is largest on
  undone work (51/51 against 32/51): the grader can't see that files changed back.
- **Stray edits are invisible to everyone.** The copies change a file the report doesn't mention, and nothing in the
  run's transcript shows it. In a real run the edit would be in the transcript, and the checks' "changed files the
  report doesn't name" would see it, but only as a problem, not a hard failure. A real fix needs the task card to
  name what the task may change (a `scope`), and a grounded check against it.
- **Excluding stray edits, argon's parent path caught 93% of the failures** (262 of 282, on all the runs it rated).
- **Real failures are the hardest.** argon caught 10 of 14, the grounded checks 2. They're also few: 14 real
  failures, almost all from the two gemmas and qwen.
- **Small local judges are noisy.** qwen3.5-9b's parent path claimed checks it never made in 71 judgings, and its
  grader failed 14% of good runs.
- **No self-preference showed.** Each Gemini judge caught as many failures in its own model's runs as in others'
  (argon's parent path: 74% against 76%). For the local judges the samples are small (11–28 failures).

**Missing verdicts.** They were the biggest judging problem, and mostly fixed during the run:

| cause | first pass | fix | after |
|---|---|---|---|
| the parent kept reading until the side loop's 4-request limit | 110 (gemma-4-26b) and most of Gemini's 104 | the last request says to rate now | gemma-4-26b still 56; Gemini 5 |
| the grader's thinking used its 2,000-token limit | 40 (gemma-4-26b) | limit raised to 8,000 | 1 |
| Gemma wrote its call as text in its own format | 4 | text-call recovery parses Gemma 4's format | 0 |

gemma-4-26b still calls a tool on the final request, despite being told to rate. The next step is to offer only
`rate_task` on that last request.

## 3. Grounded checks

| | failures caught (95% CI) | good runs failed |
|---|---|---|
| checks at the run's end | 14% (11–18%) 48/346 | 1/190 |
| checks and the re-run check | 35% (30–40%) 121/346 | 1/190 |
| grounded checks + argon (parent) | 76% (71–80%) 263/346 | 1/190 |
| grounded checks + gemini-3.8-flash (parent) | 74% (69–79%) 257/346 | 1/190 |

- **The re-run check is what catches undone work, without fail**: all 81 copies whose work was undone or deleted. The
  checks at the run's end catch only made-up citations (28 of the digit copies, 10 of the wrong-file copies).
- Combined with a Gemini parent, the grounded checks add almost nothing the parent didn't already catch (263 against
  262), because the parent hears of the re-run in its rating request. The checks' value is that they don't depend on
  the judge: with a weak judge, grounded checks plus qwen3.5-9b's grader caught 71%, against 63% for the grader alone (all the runs it rated).

## 4. Delegation

Runs that delegated, out of 3 trials, with subagents on:

| parent | survey | log-sweep | two-questions | tiny-lookup | small-fix |
|---|---|---|---|---|---|
| (a good parent) | yes | yes | yes | no | no |
| gemini-4-argon | 1 | 0 | 0 | 0 | 0 |
| gemini-3.8-flash | 0 | 0 | 0 | 0 | 0 |
| gemma-4-26b | 2 | 0 | 0 | 0 | 0 |
| qwen3.5-9b | 0 | 0 | 0 | 0 | 0 |

Outcomes, subagents off → on (passes of 3):

| parent | survey | log-sweep | two-questions | tiny-lookup | small-fix |
|---|---|---|---|---|---|
| gemini-4-argon | 3 → 3 | 3 → 3 | 3 → 3 | 3 → 3 | 3 → 3 |
| gemini-3.8-flash | 3 → 3 | 3 → 3 | 3 → 3 | 3 → 3 | 3 → 3 |
| gemma-4-26b | 0 → 0 | 0 → 0 | 3 → 3 | 3 → 3 | 3 → 3 |
| qwen3.5-9b | 0 → 0 | 2 → 0 | 3 → 2 | 3 → 3 | 3 → 3 |

- **The delegation rules, the task tool's description and the advice note don't make any of these models
  delegate.** They're right not to on tiny-lookup and small-fix (0 of 24). On the three scenarios built for
  delegation, they delegated 3 times in 36 runs.
- **The Gemini parents don't need to**: they solve everything directly, within a 16k context.
- **The local parents fail the broad-reading scenarios either way**, and they did slightly worse with the task tool
  offered (qwen3.5-9b's log-sweep 2/3 → 0/3).
- So "when to delegate" can't be left to the model's own judgment with today's prompting. If delegation is wanted,
  for cost or context, the decision has to come from kurtkode: the router choosing to split work, or a much stronger
  nudge. Whether delegating then helps is still unmeasured, because almost no runs delegated. A forced-delegation
  variant of these scenarios would measure it.

## 5. Gold and infrastructure

- **Three gold bugs**, each found by reading a failed real run and confirmed across models. Each was fixed, given a
  regression test from the real report, and the stored runs re-scored with `--regold` (18 runs changed, fail →
  pass):
  1. grow-value rejected models that showed their working ("100 × 1.1 = 110.0" on the way to 121.0).
  2. review-clean took words in a correct analysis for an alarm.
  3. add-median counted added tests for the new function as an edit outside the task.
- **Infrastructure failures aren't model failures.** Unloadable models answered with HTTP errors in 0–12 s, and
  those runs would otherwise have counted as "real failures". 168 such runs were removed (bonsai, llama-3.2-3b, and
  a first gemma-4-e4b run that hit a model still loading).
- **A judge with no verdict now keeps its reason and its last reply.** That's how the causes above were found.

## What to do next

1. **Scope on the task card** (`mayChange`-like paths for the parent to state), with a grounded check against it. It's
   the only kind of failure nothing caught.
2. **The rating side loop's last request offers only `rate_task`**, to end gemma-4-26b's missing verdicts. Re-judge
   with `--rejudge-missing`.
3. **Harder tasks**, so the bank can rank Gemini models and argon can show whether it's worth its price per success.
4. **A forced-delegation variant** of the delegation scenarios, to measure whether delegating helps when it happens,
   before building P4's routing on top of delegation.
5. **For the router (P3/P4)**: use a Gemini-class judge on the parent path plus the grounded checks as the label
   source. Weight a small local judge's labels low (kappa 0.47–0.63), and never use qwen3.5-9b as a grader.

## Reproducing

```
make cli && cd AgentCore && swift build -c release --product kurtkode-eval && cd ..
E=AgentCore/.build/release/kurtkode-eval
$E --bank all --models E:M,… --trials 3 --record bank1 --degrade --parallel 2 --parallel-remote 4 --no-load
$E --regold bank1 --degrade
$E --judge bank1 --judges E:M,… [--sample 300] [--rejudge-missing] --parallel 2 --parallel-remote 4 --no-load
$E --report bank1 --out eval-results/bank1-report.md
$E --scenarios delegation --subagents both --trials 3 --models E:M --no-load
```

Model ids as used: `lmstudio:google/gemma-4-26b-a4b-qat`, `lmstudio:gemma-4-e4b-it`, `bang:qwen/qwen3.5-9b`,
`google-gemini:gemini-3.6-flash`, `google-gemini:gemini-3.8-flash`, `google-gemini:gemini-4-argon`.
