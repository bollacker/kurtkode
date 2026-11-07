# Evaluation plan: subagents and their judges

**Run 2026-10-24 and 25; results and what changed from this plan are in EVAL_RESULTS.md.**

Written 2026-10-24, approved the same day by the user ("use local LM Studio, bang, … and any of the models from the
Google service without restriction"). It builds on SUBAGENT_ROUTING_DESIGN.md (P1 judging, P2 bank and calibration,
and the re-run check) and replaces its ad-hoc bank runs with a deliberate design. Results go to EVAL_RESULTS.md.

## Why: what the first runs couldn't tell us

- **Too few runs.** One bank run was 16 tasks × 1 trial, with 12–13 known failures, so a difference of 5–10 points
  (54% against 46%) was noise. Nothing reported an interval.
- **Variance mixed with the comparison.** Every judge comparison re-ran the subagent, so the subagent's own
  run-to-run variation (16/16, then 14/16, then 15/16) was mixed into the judges' numbers.
- **One model in every role.** qwen3.5-9b was the subagent, the parent and the grader. Its mistakes are correlated
  across roles, and self-preference can't be told from anything else.
- **Unrealistic failures.** The only failures were copies with their digits changed, plus change tasks reset. Real
  subagents fail differently: partial work, the wrong file, an invented function, edits outside the task.
- **Weak gold.** One gold check was simply wrong (the docstring bug). Some change tasks can be undone and still pass
  their check (a deleted new test file, a reverted rename).
- **Delegation unmeasured.** There's one delegation scenario, and the only model tried never delegates.

## Principles

1. **Record once, judge many.** A subagent run is recorded once: the fixture as the run left it, the report, the
   transcript, the checks, gold, cost and time. Judges, rubrics and prompts are compared on the same recorded runs,
   so differences between judges aren't differences between runs. The production data will have the same shape
   (recorded runs, judged later).
2. **Known failures from two sources.** Real failures from weaker models (the most realistic), and typed degradations
   of good runs (controlled, and labeled by type).
3. **Every number has an interval.** Pass rates and judge rates get 95% Wilson intervals; judge agreement also gets
   Cohen's kappa. Comparisons go by task kind and by failure type, not only overall.
4. **Roles crossed.** Several subagent models and several judge models, so a judge rates other models' work, and
   self-judging can be measured separately.
5. **Gold is tested against both sides.** Each gold check must pass a right outcome, fail an idle one, and fail at
   least one plausible wrong one.

## E1. Record once, judge many

- **The run store.** `eval-results/runs/<set>/<run id>/` holds:
  - `run.json`: task, card, model, trial, prompt, report, transcript, checks, the re-run check, gold, cost, tokens,
    time, and for a degraded copy its type and parent run.
  - `fixture.tgz`: the project as the run left it, `.git` included, so gold, reads and the check can be redone.
  - `judgments.jsonl`: one line per judge and path, appended, never rewritten.
- **`kurtkode-eval --bank IDS --models … --trials N --record SET`** runs and records; no judges. `--degrade` also
  writes the degraded copies of each passing run as runs of their own.
- **`kurtkode-eval --judge SET --judges … [--judge-paths …] [--sample …]`** restores each run's fixture into a
  temporary folder and judges it. A run already judged by that judge and path is skipped, so judging can be resumed
  or extended.
- **`kurtkode-eval --report SET [-o FILE.md]`** reads runs and judgments and writes the tables:
  - pass rates by model and kind
  - cost and time
  - judges against gold, with intervals and kappa, by kind and by failure type
  - self-judging against cross-judging
  - the checks' row

## E2. Realistic failures

- **Real failures.** Weaker subagent models on the whole bank: gemma-4-e4b (7.5B) and the ternary bonsai 3.6B
  locally, and gemini-2.5-flash. Their failed runs are labeled failures exactly as they happened.
- **Typed degradations.** Each is applied to a copy of a passing run and kept only if gold then fails:

  | Type | What it does | Applies to |
  |---|---|---|
  | `digits` | Changes every multi-digit number in the report (lines, amounts, times, names like Heron42) | reports with numbers |
  | `wrong-file` | Replaces each cited path with another file in the project with the same extension | reports that cite files |
  | `drop-half` | Removes every other answer line (lines with a path or a name) | list answers |
  | `undo-half` | Reverse-applies the first hunk of the run's changes | change tasks with 2+ hunks |
  | `undo-all` | Resets the project to the fixture; the report still claims success | change tasks |
  | `vanish` | Deletes the files the run created | runs that add files |
  | `stray-edit` | Adds an unrelated edit outside the task (to README.md) | every task |

- Gold gains a general rule: **no file outside the task's allowed set changes** (nothing at all for explore tasks).
  That's what makes `stray-edit` a failure, and it's right in general.

## E3. Enough data

- **The bank grows from 16 to 34 tasks**, three or four per kind, on the existing fixtures plus a few new ones. One
  review task has **no bug**, to measure false alarms on reviews.
- **Three trials** per model and task.
- **Reports:**
  - 95% Wilson intervals on every rate.
  - Cohen's kappa for judges (pass = verdict ≥ 2, against gold).
  - Per kind and per failure type.
  - For judges, also the combined label: a grounded hard failure is 0, else the parent's verdict.

## E4. Roles crossed

| Role | Models |
|---|---|
| Subagent (strong) | gemma-4-26b-a4b (this Mac), qwen3.5-9b (bang), gemini-3-flash, gemini-3.8-flash |
| Subagent (weak, for real failures) | gemma-4-e4b (this Mac), ternary bonsai 3.6B (this Mac), gemini-2.5-flash |
| Judge (parent and grader paths) | qwen3.5-9b (bang), gemma-4-26b-a4b (this Mac), gemini-3.8-flash, gemini-4-argon (strongest) |

- Self-judging is the cells where the judge's model is the run's model; the report shows it apart.
- Model ids are checked against each server before the runs. A Gemini id that's missing is replaced by the nearest
  one that exists, and the substitution is noted.

## E5. Better gold and checks

- **Each oracle test also has plausible wrong answers that must fail**: the docstring case, a right file with the
  wrong line, a list missing one item, a review that names the wrong line.
- **Task-specific `verify` commands**, so undone work can't pass:
  - rename: tests pass and the old name is gone
  - write-tests: the new file's own tests run (`-p test_pricing.py`), so a deleted file fails
  - add-function: an assertion on the new function
- Gold's "allowed changes" ignore Python's `__pycache__`.

## E6. Delegation decisions

A small scenario set, run with subagents on, each scenario labeled with what a good parent does:

| Scenario | Expected | Why |
|---|---|---|
| `survey` (16 meeting notes, five postponements) | delegate | broad reading, short answer |
| `log-sweep` (a long log, summarize the error kinds) | delegate | one big read, a short conclusion |
| `two-questions` (two independent questions, different parts of a project) | delegate, ideally both at once | parallel |
| `tiny-lookup` (a constant's value) | don't | one grep |
| `small-fix` (a one-line bug, tests given) | don't | the parent has the context |

- **Measured**: whether it delegated (task calls), against what's expected; the outcome (gold); cost, time and peak
  context.
- **Parents**: gemma-4-26b, qwen3.5-9b, gemini-3.8-flash and gemini-4-argon, 3 trials each.
- **Baselines**: the "delegate" scenarios are also run with subagents off, for the paired difference.

## E7. Practical

- **`--parallel N`** runs N tasks of one model at a time, and different models run at the same time (this Mac, bang
  and Google are separate machines). This Mac's models are loaded with 2 slots where memory allows; bang stays as
  the user left it, qwen3.5-9b.
- **Reproducibility**: every run records the model, its quantization and context (from the run record), the
  temperature, kurtkode's commit, and the fixture's seed.
- **Paid runs**: they use the user's Google key from the Keychain. A newly built eval binary asks for Keychain access
  once (the user clicks Allow), so the release binary is built once, before the paid runs.

## The run matrix and estimates

| Run | Size | Time (rough) | Cost (rough, list price) |
|---|---|---|---|
| R1 record: 7 subagent models × 34 tasks × 3 trials | 714 runs | 2–4 h per local model; minutes per Gemini model | Gemini ≈ $3–8 |
| R1 degradations of trial 1's passing runs | ≈ 300 copies | minutes (no model) | – |
| R2 judge: trial 1's runs and all degraded copies (≈ 540) × 4 judges × 2 paths | ≈ 4,300 judgings | 3–5 h per local judge | argon ≈ $15–30, 3.8-flash ≈ $3–6 |
| R3 delegation: 5 scenarios × 4 parents × 3 trials, plus off-baselines for 3 scenarios | ≈ 100 runs | ≈ 2 h | ≈ $3–6 |

The local and bang runs go in parallel with each other and with Google. If something takes far longer than
estimated, trials or judges are cut, and the cut is written down.

## What "done" means

- Every component built, with tests. The full suite passes, and the app and the CLI build with no warnings.
- R1–R3 run, with the run store in `eval-results/runs/` and the raw logs in `eval-results/`.
- EVAL_RESULTS.md answers each question with intervals:
  - How good is each subagent model, by kind?
  - How good is each judge, by failure type, and against itself?
  - Do the grounded checks and the re-run catch what judges miss?
  - Does any parent delegate when it should, and does delegating help?
- SUBAGENT_ROUTING_DESIGN.md and HANDOFF.md updated. Committed when the user asks.
