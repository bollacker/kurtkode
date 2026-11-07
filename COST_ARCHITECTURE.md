# kurtkode's cost-optimization architecture: what exists, what it rests on, what we learned

Written 2026-10-26, at the end of session 16 (Phase 3 of GAP_ANALYSIS.md), as the starting point for an independent
audit (AUDIT_PROMPT.md). It maps every cost mechanism to its code, its default, and the evidence behind it, then
lists what was learned and what is still open. The detailed records are elsewhere and are cited, not repeated:
COST_TRACKING_DESIGN.md (how cost is recorded), SUBAGENT_ROUTING_DESIGN.md (the routing design, research survey and
decisions D1–D8), EVAL_RESULTS.md (subagents and judges), COST_FLOOR_RESULTS.md (the cheapest adequate models),
GAP_ANALYSIS.md (Phases 0–3 as built and measured), FUNCTIONAL_TEST_RESULTS.md (review rounds).

## The thesis, and how far it got

kurtkode exists to let one coding session mix models from several sources and spend as little as the work allows.
The plan (GAP_ANALYSIS.md Part 2, Theme A) was: measure cost precisely, ship measured cheap defaults, label run
outcomes, then act on cost inside live sessions (cascade, review, delegation), and finally learn a router from real
outcomes. **Measuring and the static defaults are done and well evidenced. Acting is built only in advisory or narrow
forms, because the failure detectors measured so far are either free and weak or strong and as expensive as the step
up they would save. The learned router is designed but not built, and real-session outcome data is still thin.**

## Map of the mechanisms

### 1. Measuring what was spent

| Mechanism | What it does | Where | Default | Evidence |
|---|---|---|---|---|
| Cost entries | One per billed request: tokens by kind (prompt, cached read and write, output, reasoning), list price, the provider's charge where it says, purpose (reply, summary, retry, grading, routing, review…) | `LLM/CostEntry.swift`, `CostSink` | always | COST_TRACKING_DESIGN.md; calibration on existing keys $0.1124 |
| List price as the basis | Comparisons use list price; `spent` = charge where known, else list price (≈) | `PriceList`, `RemotePrices` (OpenRouter `/models`, no key needed) | user decision 2026-10-15 | OpenRouter's provider routing made deepseek 2.4× dearer a run with no list-price change (COST_FLOOR_RESULTS.md re-run) |
| Reconciliation | OpenRouter's generation record (exact charge) fetched at a run's end | `CostEntry.reconcile` | on | records lag minutes; one in three after ten |
| Run records | Per run: setup, totals, outcome, signals, judgments, snapshots, children's costs | `Agent/RunRecord.swift` | always | basis of every report below |
| Reports | `kurtkode cost report --by model|kind|project|day [--eval STORE]`, `cost whatif -m E:M` (reprice recorded tokens), the Spending window | `Agent/Spending.swift`, `DebugCommands`, `SpendingView` | on demand | the cost-floor re-run's own figures reproduced exactly |
| Limits | Run ($2), session, daily, per-project limits; a run stops at one | `CostMeter`, `RunSettings` | run $2; others off | — |
| Cache care | Claude's 1-hour cache option; a notice when a paid request misses a previously warm cache; "≈$X to switch" before a model switch (the history re-read uncached) | `CacheWatch`, `PriceList.switchCost` | notice on; 1-hour cache off | cache share 64% on this Mac's paid runs |

### 2. Choosing models

| Mechanism | What it does | Where | Default | Evidence |
|---|---|---|---|---|
| Model pool | Configurations (endpoint, model, reasoning, provider pins) with a tier (local < cheap < standard < frontier), roles (main, subagent, judge, reviewer, summarizer), a retry rung | `Models/ModelPool.swift`, `pool.json` | shipped: ling-3.0-flash (cheap), deepseek-v4-flash-0731 reasoning off (cheap; reviewer), Haiku 5.5 (standard; judge, reviewer, main), Sonnet 5.5 (frontier; was Opus until 2026-10-30) | cost-floor finalists: ling 474/480 at $0.0002 a run |
| Automatic subagent model | A hosted session's subagents run on the pool by the task card's tier/importance (ling, or Haiku for important tasks); local sessions keep their model | `SubagentRouting.automatic` | on ("Automatic") | Haiku parent: pool subagents halved a run's cost (−48%) at the same pass rate (12/15 both) |
| Retry ladder (D3) | A subagent run with a hard failure retried once, one rung up, its edits undone | `AgentLoop.runSubagent(retry:)` | on | catches 1 of ling's 9 bank failures (retry-sim over 1,439 runs) |
| Default grader | Haiku grades `importance: high` subagent runs in hosted sessions | `SubagentRouting.grader` | on | Haiku parent-path kappa 0.67 (catches 67% of failures, 2% false alarms) |
| Reasoning per model | none / effort level per model profile, sent in each API's form | `ModelProfile.reasoning`, `ReasoningSetting` | the model's default | reasoning off cheaper per success for 61 of 85 models, but ling 99% → 88% |
| Prompt style | detailed or lean working rules; templates editable | `Prompts/*.md` | detailed (lean for some) | Gemini long-doc 0/2 detailed vs 1/2 lean (tiny n) |

### 3. Detecting failure (the cascade's detectors)

| Detector | Cost | What it catches (measured) | Where |
|---|---|---|---|
| Grounded checks at a subagent's end (no report, error stop, made-up citations, the card's `verify`) | free | 14% of failures; with the re-run check 35%; all undone work, no stray edits (EVAL_RESULTS.md) | `GroundedChecks` |
| Run signals on main runs (last check and exit, files the request didn't name, unfinished todos) | free | recorded; as triggers, 16–23% of cheap models' failures pooled over ~12,000 stored runs, precise where they fire (re-run check 100%, stopped early 60–96%) | `RunSignals`, `--trigger-sim` |
| Judges, parent path (reads files) | ≈ one cheap run | argon 71%/100% precise, Haiku 67%, gemini flash 57% on bank1; deepseek 44% on mercury's hard runs | `JudgeCalibration` |
| Judges, grader path (no tools) | a fraction of a run | 29–58% recall at 21–71% precision | `AgentLoop.grade` |
| Cross-vendor review of the diff (A6) | $0.0001 (deepseek) – $0.0005 (Haiku) | 51–56 of 56 bad changes on the sampled code runs, 0–2 false alarms in 24; blind to omissions in files the diff doesn't touch | `Agent/Review.swift`, `--review-sim` |
| The user's thumbs, retries, rewinds | free | labels, not detectors; few so far | `MainRunJudgments` |

### 4. Acting on cost in sessions

| Mechanism | What it does | Default | Evidence |
|---|---|---|---|
| Escalation card (A4) | After a run below the frontier: on grounded signals, a 👎, or (opt-in) a cheap review that finds problems, offer the next tier's main model with a price; one click hands over reasons and diff; never automatic | offers on, review off | replays: a perfect trigger would give Haiku's results at 2% of its cost from a local model; real triggers recover a quarter to a third of that; no judge measured makes it pay automatically (mercury → Haiku: the best judge's cascade costs more than Haiku alone) |
| Delegation nudge and A7 | At six broad reads filling a fifth of the context, a note, then a forced task call (hosted) or a kurtkode-written one (LM Studio) | on, local included (user's call) | no model delegates on its own (3 of 36); argon −63% cost with cheap subagents, Sonnet 1.7–2× dearer when forced; the threshold never tripped for a Haiku parent; locally it cost time, no gain |
| Compaction and output budgets | Keep requests inside the context; trim answered tool output; structured summaries | on | Phase 0–1 measurements (fewer steps, no growth) |

### 5. Designed, not built (SUBAGENT_ROUTING_DESIGN.md)

- **The router (P3)**: kNN over task embeddings with a Bayesian prior, predicting success per configuration;
  `router eval` must beat "always the same model" and "the model's average" before it's used.
- **θ, the value of an hour of waiting** (D1) and **routing modes** (Thrifty / Balanced / Best): expected cost =
  dollars + θ · hours. Nothing in the code uses θ yet; local models are timed, not priced.
- **Exploration and shadow runs** (D4) with caps.
- **Automatic escalation** (decision 2: only after trigger precision is measured; measured, not good enough yet).
- **The OpenAI Responses API** (Phase 4): GPT-family models with reasoning carried.

## Where the money actually goes

- **This Mac, last 30 days**: 19 main runs, $0.218 in all, all of it gemini-4-argon (4 runs, $0.055 a run, 64%
  cached); the rest local (qwen3.5-9b, muse-glimmer, Gemma). Real-session data is too thin to estimate savings from
  usage; the evidence is from the eval stores.
- **Eval stores** (`eval-results/runs/`, on disk only, ~19,000 stored runs): cf1 (the 499-configuration screen), cf2
  (the shortlist on the bank), cf3a/cf3b (hard tier, cheap and frontier; mercury-2.5's runs have Haiku, deepseek and
  qwen3-coder judgments), cf5 (judge calibration), cf6 (finalists re-run after Phase 1), bank1 (6 models, judgments,
  degraded copies), p1-before/after (Gemma). `kurtkode cost report --eval STORE` gives their spending; `--trigger-sim`, `--review-sim`,
  `--retry-sim` replay detectors on them for free.
- **Typical prices** (list): ling ≈$0.0002–0.0003 a task, deepseek-off ≈$0.0004, Haiku ≈$0.0013, frontier
  $0.02–0.05 (≈100× ling) on the bank and hard tier, where they all pass.
- **Spent on measurement**: cost floor $83.22 + re-run $1.69; Phase 2 $0.198; Phase 3 ≈$0.74.

## Lessons

1. **Cheap models fail by being wrong, not by failing.** Their failing reports look fine. Hard-failure retries catch
   almost nothing (1 of 9); every cheap detector misses most wrong answers. The detector is the whole problem of a
   cascade.
2. **A detector has to be much cheaper than the step up it saves.** A judge that reads the files costs about one cheap
   run; when the next tier is only 2× dearer (mercury → Haiku), judging every run costs more than just using the
   stronger model. Cascades pay where the price ratio is large (local → cheap, cheap → frontier at ~100×).
3. **The ceiling is high.** With a perfect trigger, local Gemma → ling → Haiku would match Haiku at 2% of its cost on
   the bank; mercury → Haiku at 67%. The gap between real triggers and the oracle is where improvement lives.
4. **Grounded checks are precise and narrow**: they catch undone work every time and wrong content almost never.
   Re-running the check and "stopped early" are near-certain signals when they fire.
5. **Diff review is cheap and good for code changes**, and blind to what the diff doesn't show (a rename left half
   done in an untouched file, tests that don't test the request).
6. **Delegation saves money only for parents that would read everything** (argon −63%); frugal parents (Sonnet) get
   dearer when forced, and no model delegates unprompted. A threshold that is a share of the context almost never
   trips for large-context hosted models. Delegating to the same one-slot local model costs time.
7. **The benchmarks saturate.** Cheap finalists pass 98–100% of the bank and hard tier; frontier models all pass. The
   fixtures show that cheap models clear the floor, not where they stop or what frontier models are worth. Savings
   claims need harder or real tasks.
8. **Prompt tokens are the bill.** Input dominates (20k in, 900 out for a typical task); caching is 64% of paid input
   here. The built-in skills listing raised prompt tokens 32–103% with no skill loaded in 1,439 runs (the user chose
   to keep it: small models have large contexts).
9. **Provider routing moves prices.** The same model on OpenRouter cost 2.4× more a run when routing sent it to dearer
   providers; list price hides that, the charge shows it.
10. **Reasoning settings are per model**: off is usually cheaper per success, sometimes much worse.
11. **Replay before paying.** `--retry-sim`, `--trigger-sim`, `--review-sim` over stored runs answered each question
    for free and stopped at least one bad design (the retry ladder as a cascade). Build the replay first.
12. **Gold and samples lie in specific ways.** Real runs exposed eight gold bugs; enriched samples inflate precision
    (report base rates); infrastructure failures and degraded copies must be excluded from rates; read every failure
    cluster before trusting a rate.
13. **A fifth of OpenRouter configurations can't run at all** (reasoning can't be turned off; no provider that doesn't
    train on prompts; rate limits).
14. **Money safety in the rig**: give every paid mode a `--max-cost` (the judge mode lacked one until Phase 3);
    runs sharing a key report the key's usage, not their own (`--own-cost`).
15. **Privacy and cost interact**: cheap remote helpers (reviewers, escalation targets) receive diffs; files withheld
    from remote models must be filtered there too (Round 7, R7-4), and "local" must mean surely local (R7-15).

## Open questions for the audit

- How much would the current defaults save on real work, against "always the session's model" and "always the
  frontier"? There's no real-workload estimate yet.
- Is there a detector cheap enough and precise enough for automatic escalation (self-consistency, agreement between
  two cheap models, log-probabilities, the model's own confidence, test generation)?
- Is the cost model right: list price, θ unused, local models free, the switch cost, cache economics?
- Are the shipped priors stale (prices change; introductory Gemini prices end 2026-11-30/12-31)?
- Do the benchmarks measure what matters for savings (task mix, difficulty, size)?
- What does the literature now say about cascades, routers and judges for agentic coding?
