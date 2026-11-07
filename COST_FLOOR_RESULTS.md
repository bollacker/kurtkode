# Cost-floor results: the cheapest model that clears the bar

Run 2026-10-25 by COST_FLOOR_PLAN.md, on every paid tool-capable model on OpenRouter, using only providers that don't
train on prompts. **Spent: $83.22 of the $185 budget**, by the OpenRouter key's own count. Nothing was spent on the
Google key: argon went through OpenRouter too, so one counter covered everything.

The generated tables are in `eval-results/costfloor/`:
- `analysis.md` (finalists, floors, kinds, reasoning off, infrastructure)
- `delegation.md` (stage 4)
- `stage5-report.md` (judges)

The run store is `eval-results/runs/cf1`, `cf2`, `cf3a`, `cf3b` and `cf5` (about 26,000 runs, gitignored). The logs
are `eval-results/costfloor/*.log`.

## Answers in brief

1. **Cheapest above a 95% floor: `inclusionai/ling-3.0-flash`.**
   - 474 of 480 runs pass (99%; 95% interval 97–99%): 335/340 on the 34-task bank and 139/140 on the 14-task hard
     tier, 10 trials each.
   - It costs **$0.00021 a run, $0.00022 per success**, at about 19 s a run.
   - It's the cheapest at 80% and 90% too.
   - Next, also certified above 95%:
     - `deepseek/deepseek-v4-flash-0731` with reasoning off: 99%, $0.00042 per success.
     - The same model at default reasoning: 98%, $0.00054.
     - `anthropic/claude-haiku-5.5`: 478/480 (100%, interval 98–100%), $0.00114. It's the most reliable cheap
       model, at five times the price.
2. **The frontier references cost about 100 times more on these tasks.**
   - Claude Sonnet 5.5, Kimi K3.1 Pro, Gemini 4 Argon, GPT-5.6 Sol and Claude Opus 5.5 each passed all 42
     hard-tier runs.
   - They cost $0.023–0.046 a run, against ling-3.0-flash's 139/140 at $0.0002.
   - **This bank and hard tier no longer separate strong models**: they show that cheap models clear the floor, not
     where cheap models stop.
3. **Where cheap models do stop: broad reading.** Measured on the delegation scenarios.
   - ling-3.0-flash alone solved the survey (16 notes) and the log sweep (five long logs) only 1 time in 3 each.
   - Every frontier parent solved them.
4. **Delegating to cheap subagents pays only for a parent that would otherwise read everything.**
   - Argon alone costs $0.092 a run across the five scenarios. With ling-3.0-flash subagents it costs **$0.034
     (−63%), with no loss of quality** (15/15).
   - On the log sweep, argon alone reads every log ($0.28). With subagents it costs $0.043.
   - Sonnet 5.5 alone is already frugal ($0.022 a run; it greps instead of reading). Forced delegation made Sonnet
     and GPT-5.6 Sol 1.7–2× dearer, and worse on the survey.
     - The cheap subagents report distractor notes, and those parents pass them on. Haiku subagents leak them too.
     - Only argon checked the subagents' claims.
5. **Cheapest adequate judge: Claude Haiku 5.5 by the parent path.**
   - Kappa 0.67 against argon's 0.71, on the same 204 stored runs.
   - It catches 67% of failures (argon 69%), and wrongly fails 2% of good runs (argon 0%).
   - About 4.6 s a judgment, at 1/13 of argon's cost.
   - `ling-3.1-flash` scores a little higher (kappa 0.69, no false alarms, 1/24 of the cost) but takes 63 s a
     judgment.
6. **Reasoning off is usually cheaper per success.**
   - True for 61 of the 85 models measured both ways.
   - It isn't free: ling-3.0-flash drops from 99% to 88% with reasoning off.
   - Choose per model; don't flip a global switch.
7. **A fifth of the field couldn't run at all.** 105 of 499 configurations failed every run on infrastructure:
   - "reasoning can't be turned off" (324 runs, the `#off` twins of reasoning-only models);
   - no provider that doesn't train on prompts (100 runs);
   - rate limits and provider errors.
8. **The gold checks had bugs, which real runs exposed.**
   - Eight checks were wrong; they're listed below.
   - Each was fixed with a regression test from the real report, and every stored run was re-scored with no model
     re-run.
   - Before the fixes, the frontier references looked as if they failed up to 10 of their 42 hard-tier runs.

## Recommended setup

| Role | Model | Why | Expected cost |
|---|---|---|---|
| Subagent (default) | `inclusionai/ling-3.0-flash`, reasoning at default | Cheapest above 95%, certified | ≈ $0.0002 a task |
| Subagent (retry on failure, D3) | `deepseek/deepseek-v4-flash-0731` with reasoning off, then `anthropic/claude-haiku-5.5` | Other model families; 99% and 100% | $0.0004 / $0.0011 |
| Judge | `anthropic/claude-haiku-5.5`, parent path | Kappa 0.67, fast | ≈ $0.0011 a judgment |
| Parent | `anthropic/claude-sonnet-5.5` alone, or argon with cheap subagents for broad reading | Cheap models fail broad reading on their own | ≈ $0.02–0.03 a turn |

**What's not established:**
- whether ling-3.0-flash's 99% holds on real work, which is bigger than these fixtures;
- whether a nudge, rather than an order, gets frontier parents to delegate the broad-reading tasks only.

The router (P3) should take these as priors and learn from real outcomes. The subagent pool (D6) should now include
these OpenRouter models.

## Spending by stage

| Stage | Budget | Spent (list price) | Runs |
|---|---|---|---|
| 1 screen: every configuration, 6 tasks | $48 | $40.07 | 2,754 |
| 2 bank: survivors at ≤ $0.01 a run, the other 28 tasks | $20 | $20.00 (cap reached) | 6,209 |
| 3a finalists: hard tier and more bank trials | $25 | $6.92 | 6,782 |
| 3b references: hard tier, 3 trials | $35 | $7.22 | 210 |
| 4 delegation (ling, then Haiku subagents) | $35 | $6.54 | 165 |
| 5 judges | $7 | $1.30 | 2,040 judgments |
| **All** | **$185** | **$82.06** (key: $83.22) | |

The key's count is $1.16 higher. It includes the stage-4 subagents' own calls, which the parents' records don't
carry, and a few calls that failed with no recorded cost.

## The field and the funnel

- **Catalog.** 281 models with tool calling and a 32k+ context, with variants removed and `:free` left out. Thinking
  models got a second configuration with reasoning off (`#off`), making 499 configurations.
- **Stage 1** screened all 499, cheapest first, on 6 tasks. 335 passed at least 5 of 6, and 105 never ran.
- **Stage 2.** The bank can't rank anything above about $0.0005 a run, because deepseek-v4-flash-0731 already passes
  34/34 at that price. So stage 2 ran the other 28 bank tasks only on the 232 survivors that cost at most $0.01 a
  run. It stopped at its $20 cap.
- **Stage 3a.** The 25 configurations with at least 32/34 on the bank ran the hard tier, 3 trials. The 12 at 93% or
  more then went to 10 trials on bank and hard tier (480 runs each), enough to certify a 95% floor.
- **Stage 3b.** Five frontier references ran the hard tier, 3 trials.

## Finalists (bank + hard tier)

| configuration | bank | hard | all (95% CI) | $/run | $/success | mean s |
|---|---|---|---|---|---|---|
| inclusionai/ling-3.0-flash | 335/340 | 139/140 | 99% (97–99%) | $0.00021 | $0.00022 | 19 |
| deepseek/deepseek-v4-flash-0731#off | 334/340 | 139/140 | 99% (97–99%) | $0.00042 | $0.00042 | 16 |
| deepseek/deepseek-v4-flash-0731 | 336/340 | 136/140 | 98% (97–99%) | $0.00053 | $0.00054 | 18 |
| inception/mercury-2.5 | 327/340 | 128/140 | 95% (92–96%) | $0.00059 | $0.00062 | 16 |
| poolside/laguna-s-2.1#off | 326/340 | 138/140 | 97% (95–98%) | $0.00070 | $0.00073 | 19 |
| deepseek/deepseek-v4-flash#off | 331/340 | 136/140 | 97% (95–98%) | $0.00079 | $0.00081 | 20 |
| deepseek/deepseek-v4-flash | 336/340 | 136/140 | 98% (97–99%) | $0.00087 | $0.00088 | 22 |
| inception/mercury-3 | 335/340 | 136/140 | 98% (96–99%) | $0.00093 | $0.00095 | 14 |
| anthropic/claude-haiku-5.5#off | 332/340 | 139/140 | 98% (96–99%) | $0.00107 | $0.00109 | 16 |
| anthropic/claude-haiku-5.5 | 339/340 | 139/140 | 100% (98–100%) | $0.00113 | $0.00114 | 17 |
| deepseek/deepseek-v4.1-flash | 325/340 | 138/140 | 96% (94–98%) | $0.00181 | $0.00188 | 19 |
| stepfun/step-3.5-flash | 329/340 | 134/140 | 96% (94–98%) | $0.00195 | $0.00202 | 36 |

Finalists with 3 trials only (144 runs) are in `analysis.md`, along with the by-kind table. ling-3.0-flash's only
misses are in search (a relative import, an aliased call) and summarize (counting 46 lines).

**Frontier references, hard tier (42 runs each, all passed):**

| model | $/run |
|---|---|
| Claude Sonnet 5.5 | $0.0229 |
| Kimi K3.1 Pro | $0.0287 |
| Gemini 4 Argon | $0.0349 |
| GPT-5.6 Sol | $0.0397 |
| Claude Opus 5.5 | $0.0458 |

## Delegation economics (stage 4)

Three trials per cell; parent list price per run, plus an estimate of the subagents' calls.

| parent | setup | survey | log-sweep | two-questions | tiny-lookup | small-fix | mean $/run |
|---|---|---|---|---|---|---|---|
| Sonnet 5.5 | alone | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | $0.0224 |
| | + ling subagents | 1/3 | 3/3 | 3/3 | 3/3 | 3/3 | $0.0388 |
| | + Haiku subagents | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | $0.0471 |
| Argon | alone | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | $0.0921 |
| | + ling subagents | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | **$0.0339** |
| | + Haiku subagents | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | $0.0441 |
| GPT-5.6 Sol | alone | 2/3 | 2/3 | 3/3 | 3/3 | 3/3 | $0.0487 |
| | + ling subagents | 1/3 | 3/3 | 3/3 | 3/3 | 3/3 | $0.0580 |
| | + Haiku subagents | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | $0.0597 |
| ling-3.0-flash | alone | 1/3 | 1/3 | 3/3 | 3/3 | 3/3 | $0.0002 |
| | + ling subagents | 0/3 | 1/3 | 3/3 | 3/3 | 3/3 | $0.0013 |

- **Every delegated survey failure found all five postponements and added distractors.** The distractors came from
  subagent reports that the parent didn't check. Argon re-read before answering and never failed.
- **Forced delegation on "don't delegate" scenarios** (tiny-lookup, small-fix) costs 1.5–3× more and gains nothing.
  The force was an order in the prompt, used to measure the economics. It isn't a policy.
- **Wall time grows with delegation**, by 15–30 s a task, except for argon on the log sweep, which went from 193 s
  to 64 s.

## Gold bugs found and fixed during the run

Every one was a right answer marked wrong. All now have regression tests from the real report (`TaskBankTests`,
`TaskBankHardTests`, `Fixtures/hard-real-reports.json`).

| Task | Bug |
|---|---|
| h-aliased-calls | Failed any mention of d.py, including "d.py:1 is only a comment" and lists of the project's files |
| h-import-cycle | Counted every module named, so it failed good reports that listed the whole import graph or said "mod_a → mod_c → mod_d → mod_a is not a cycle", or "would have been" one |
| h-log-correlate | Failed reports that named the decoy requests in order to exclude them ("not included: the API returned 500") |
| h-mutable-default | Missed "evaluated once", "reuses" and "the same list" as the explanation |
| review-clean | Read "does **not** introduce a bug" (Markdown), "whether this introduces a bug" and "## does the diff introduce a bug?" as alarms; missed "not a correctness bug" |
| count-tests | Failed "no failures or errors" for containing "failure" |
| insufficient-status, find-reserve-def | Rejected range citations such as `inventory/storage.py:31-34` that hold the line |
| review-shop-diff | Missed "price × quantity" as saying it should multiply |

Format stays strict where the prompt asks for it: "give path:line" fails a table with separate path and line columns.
That costs Haiku 5.5 one of its 480 runs.

## What changed from the plan

- **One budget counter.** I added two options to `kurtkode-eval`:
  - `--own-cost`: a process's cap counts only its own runs, so concurrent stages don't stop each other.
  - `--key-limit`: a hard stop on the key's absolute usage, set at $185 above the starting point.
  - Argon ran through OpenRouter rather than the Google key.
- **Stage 2 was limited to configurations at ≤ $0.01 a run**, for the reason given above. The 36 pricier survivors
  ran only the screen.
- **Stage 3a went to 10 trials** for the 12 best finalists. With 144 runs, no configuration could certify 95%; with
  480 runs, ling-3.0-flash's lower bound is 97%. This cost $3.
- **Stage 4 ran the five delegation scenarios without the 4 hard tasks.** The eval runs bank tasks as subagent runs,
  so forced delegation doesn't apply to them without a code change. In exchange it ran a second subagent model
  (Haiku).
- **Stage 5 ran on the 236 stored bank1 runs that all four earlier judges rated, 204 of them after infrastructure
  runs.** The plan said 262, a count I couldn't reproduce.

## Findings for kurtkode itself

- **grep needs a count mode.** Asked "how many WARN lines", cheap models call grep with `output_mode: "count"`
  (Claude Code's parameter), get the 46 matching lines back, and guess 47. That's most of the failures on warn-count.
- **A parent should check what subagents claim before passing it on.** The delegated-survey failures show that the
  rubric's "check the work" applies to list answers too, not only to edits.
- **Regold over a whole large store missed changes** that the same regold catches one task at a time. That happened
  twice on cf2 (9,961 runs), with no error and no skipped restore. The cause isn't found yet.
  `spike/regold_by_task.sh` re-scores per task, and every set here was re-scored that way. `regold` now logs any run
  it can't restore.

## Caveats

- **Runs aren't independent.** 480 runs are 48 tasks × 10 trials, and the intervals treat them as independent. For
  ling-3.0-flash the 6 failures fall on 3 tasks:
  - warn-count, 3 of 10: the grep count problem above;
  - importers-of-storage, 2 of 10: it missed the relative import;
  - h-aliased-calls, 1 of 10: it missed the aliased call.

  Every other task passed all 10 trials. The tasks are all small Python fixtures, and the floor is relative to them.
- **Times were measured under heavy load:** up to four eval processes on 10 cores.
- **Costs are list price.** The billed amounts were close: the key's count is within 1.5% of the sum.
- **Context.** Every run had kurtkode's 32k context budget.
- **Subagent cost in stage 4 is estimated.**

## Files

- **Plan:** COST_FLOOR_PLAN.md.
- **Scripts:**
  - `spike/costfloor_catalog.py` (stage 0)
  - `spike/costfloor_survivors.py` (cuts)
  - `spike/costfloor_analyze.py`
  - `spike/costfloor_delegation.py`
  - `spike/regold_by_task.sh`
  - `eval-results/costfloor/run-s3a*.sh`
- **Model lists:** `eval-results/costfloor/models-*.txt` and `judges.txt`.
- **Code:**
  - The hard tier is `EvalKit/TaskBankHard.swift` (`--bank hard`).
  - Spending options are in `kurtkode-eval/main.swift` (`--own-cost`, `--key-limit`).
  - Gold fixes are in `TaskBank.swift` and `TaskBankMore.swift`.

## Re-run after Phase 1 (2026-10-26, session 14)

The three finalists again, under what sessions now have: Phase 1's tools (ripgrep grep with count mode, multi-edit,
read before edit, background bash), Round 5's fixes, and **kurtkode's built-in skills** for general subagents
(`kurtkode-eval --skills builtin`). Same bank (34 tasks) and hard tier (14), 10 trials, `--no-train`. Store
`eval-results/runs/cf6` (gitignored); script `eval-results/costfloor/run-cf6.sh`; tables
`eval-results/costfloor/rerun-phase1.md` (made by `spike/costfloor_rerun_compare.py`). **Charged: $1.69**, by the
records (the key went from $2,614.62 to about $2,616.31). 1,439 of 1,440 runs: one ling-3.0-flash run was lost to a
grep hang (`Process.waitUntilExit` never returning; fixed in 28e9843), which also held the run for 5 hours.

| model | bank then → now | hard then → now | pass now (95% CI) | charged a run, then → now | prompt tokens a run, then → now |
|---|---|---|---|---|---|
| ling-3.0-flash | 335/340 → 335/339 | 139/140 → 135/140 | 98% (96–99%) | $0.000247 → $0.000251 | 13,829 → 18,592 |
| deepseek-v4-flash-0731 #off | 334/340 → 339/340 | 139/140 → 140/140 | 100% (99–100%) | $0.000755 → $0.001827 | 10,594 → 20,773 |
| claude-haiku-5.5 | 339/340 → 339/340 | 139/140 → 137/140 | 99% (98–100%) | $0.001134 → $0.001444 | 11,199 → 18,557 |

- **All three still clear the 95% floor** (lowest interval bound 96%), and **ling-3.0-flash is still the cheapest by
  far**, at the same $0.00025 a run. Pass rates moved within their intervals (ling −4 runs, deepseek +6, Haiku −2).
- **No model loaded a skill in 1,439 runs.** The skill tool and its listing (about 1.8k tokens a request for general
  subagents) bought nothing here, and with Phase 1's larger tool definitions they nearly doubled general agents'
  requests (2.5–3.4k tokens → 5.5–7.4k). On the same 34 bank tasks prompt tokens a run rose 32% (ling), 103%
  (deepseek, which also made more requests) and 67% (Haiku). Most of the increase is served from prompt caches, so
  charges rose much less: ling flat, Haiku +27%.
- **deepseek-v4-flash-0731 costs 2.4 times what it did**: its prompt tokens doubled, and OpenRouter sent more of its
  requests to dearer providers. Its listed price didn't change ($0.044 / $0.133 a million tokens, read 2026-10-26; an
  earlier version of this note said the listing had risen to $0.44, a misreading). Before, 70% of its requests went
  to the three cheapest providers (Baidu, Relace, DeepInfra, about $0.03–0.05 a million input tokens); in the re-run,
  27%, with the rest on Wafer, Cohere, DigitalOcean and CoreWeave ($0.07–0.17). What it was charged a million tokens
  rose from $0.066 to $0.084. Even so, it's no longer clearly the second-cheapest finalist: Haiku 5.5 now costs
  about as much a run and passed as often. Pinning providers (`ProviderRouting.order`) would bring it back down, at
  the risk of the pinned ones failing.
- The skill listing stays (the user's decision, 2026-10-26: small models have large contexts). Follow-up: compare
  charges, not listings, before relying on a cheap model's price.
