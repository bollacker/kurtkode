# Independent audit of kurtkode's cost-optimization architecture

Written 2026-10-26 (session 17) from the prompt in `AUDIT_PROMPT.md`. Everything measured here is from the stored
eval runs (`eval-results/runs/`, 18,893 runs in 9 stores), this Mac's own session records, the source, and the public
OpenRouter model listing. **No paid API call was made, no model was loaded or unloaded, and no product code was
changed.** (Session 18, 2026-10-27, then implemented the recommended decisions on the branch
`cost-audit-improvements`: section 8; P1 and P3 were run the same day with the user's approval: section 9.) The working papers (claims extracted from the docs, the code audit, the literature bibliography, the
experiment write-ups with full tables, the scripts) are in `spike/cost-audit/`. Numbers marked *measured* come from
the stores or the session records and reproduce from the scripts; numbers marked *modeled* rest on stated
assumptions.

## 1. Verdict

kurtkode measures cost well and its static defaults are sound: on the task bank and the hard tier, ling-3.0-flash
passes 98% of runs at $0.00025 a run (*measured*), 80–83% below Haiku 5.5 and 98–99% below any frontier model, and
the headline figures in the docs (474/480, 12/15 at −48%, 1 of 9, 51 of 55, 16–23%, 2.4% of Haiku's cost) all
reproduce exactly from the stores. **But the architecture's acting parts barely touch the bill.** Nothing automatic
moves main-run work to a cheaper model in a hosted session; delegation to cheap subagents never trips for hosted
parents (0 of 15) and no model delegates unprompted (3 of 36); escalation is advisory and only applies when the user
already started cheap. In the product as shipped, a session on a frontier model realizes about 0–10% of the measured
per-task savings. The money is in long, multi-step tasks, where no cheap model has been measured at all: on a
realistic developer-day mix (*modeled*, section 5) the long tasks are 55–90% of a Sonnet-class bill, and running the
short tasks cheap saves 11–43% of it. On the stored data there is **no routing headroom**: the best possible per-task
router beats "always ling" by 0 to 1.5 points at 5–30% more cost, and a kNN over task text does not beat each model's
own average. The detector evidence is from samples with 45–65% failures; at the real 2–6% rates the shipped judges
and reviewers are 20–74% precise. Two things found here are worth more than any cascade: **the system prompt's
Environment block (project path, date, git status) sits ahead of the tools and instruction files, so a fresh subagent
or eval run never reads the prompt cache** (0 of 480 Haiku runs; cache writes are 54% of Haiku's eval cost), and the
**default grader for the common important task is Opus** (in the code, deliberately; the docs say Haiku) at about
$0.019 a grade, roughly 14 times the Haiku run it grades.

**Savings estimate** (list price; ranges are the spread over workloads and price assumptions):

| Baseline → policy | Task bank (*measured*) | Hard tier (*measured*) | Realistic day mix (*modeled*) |
|---|---|---|---|
| Always frontier (Opus / Sonnet / argon) → ling | −98.8% | −98.6 to −99.3% | −27% of Sonnet (−11 to −43% as long tasks go 12→2 a day); −64% of Opus |
| Always Haiku → ling | −82.6% | −79.9% | −80% if everything goes cheap; long tasks unmeasured |
| Always the session's model (frontier) → as shipped | ≈0% (nothing automatic moves work) | ≈0% | 0–10% (only what the user delegates) |
| ling + escalation on free signals → vs always Haiku | −82% at 98.5% pass (Haiku 99.2%) | −81% at 99.3% | same shape; moves failures, not dollars |
| ling + perfect trigger → vs always Haiku | −81% at 100% | −79% | the ceiling; real triggers get 25–36% of the gap on the bank, 9% on the hard tier |
| **Real-sized tasks (P2, measured)**: always Sonnet → Haiku | — | — | −94% a run, −93% a success, at 83% pass against 100%; → ling: −98% a run but 10% pass; Haiku + "suite fails" trigger → Sonnet: ≈−75% at Sonnet's pass rate (modeled from the cells) |

**Measured later the same evening (P2 and P2b, section 5)**: on ten real-sized tasks from a real repository, ling passes 10%, deepseek-off 72%, Haiku 83% and Sonnet 100%; Haiku is the cheapest success at $0.057 against Sonnet's $0.78 a run, and ling's bank result does not transfer at all. The rows above hold for bank-sized work only.

The quality side is the weak point: these benchmarks cannot show where cheap models stop (frontier models pass 42
of 42 hard-tier runs; ling 139 of 140), so every "no quality loss" above is "no loss the fixtures can see". In
absolute terms the whole architecture is worth about $0.20 a month at this Mac's current usage (19 runs, $0.218 in 30
days, *measured*) and perhaps $3–6 a day at a Claude-Code-like $13 a day, if the short-task share holds.

## 2. Findings, most important first

**F1. The acting mechanisms don't reach the bill (high).** The pool, automatic subagent routing, the grader and the
retry ladder apply only to subagent runs; the escalation card applies only to sessions that started below the
frontier; the delegation threshold (`AgentLoop.swift:568`: six broad reads in a row adding up to a fifth of the
context) is 40k tokens on a 200k context and never tripped for a Haiku parent (GAP_ANALYSIS "Phase 3 measured", 0 of
15) and no model delegates unprompted (3 of 36). The −48% subagent saving was measured only under
`--force-delegation` (n = 15 a side); the −63% argon saving is one scenario (the log sweep) for about 80% of it, with
Sonnet and GPT-5.6 getting dearer when forced. The realized saving for a hosted frontier session is therefore the
share the user delegates by hand. *Evidence: the measured sections of GAP_ANALYSIS.md; the workload model in
`spike/cost-audit/scripts/model/workload.py`.*

**F2. The benchmarks give no routing headroom, and failures cluster on a few tasks (high).** *Measured on cf6 (3
models × 48 tasks × 10 trials) and cf3a (12 models × 14 tasks × 10):* the oracle per-task router reaches 100% at
1.3× ling's cost when it picks and scores on the same trials, and 99.6% at 1.2× (cf6) or exactly ling's 99.3% (cf3a)
when scored on fresh trials. Models fail on the same tasks: where ling fails, Haiku passes 90–92% against 99% overall;
a dearer model is strictly better on 3 of 48 tasks. ling's 9 cf6 failures sit on 4 tasks (8.3 expected at random, p <
0.0001); mercury's 12 on 5 of 14, 7 of them on `h-aliased-calls`. A leave-one-task-out kNN over task text (k = 3, 5,
TF-IDF) has a worse Brier score than the per-model prior on cf2 and cf6 and ties on cf3a; nothing observable before a
run (prompt length, card kind, edit vs read) correlates with failure (|ρ| ≤ 0.37, p ≥ 0.14), and the only correlates
appear after the run (output tokens ρ = 0.38, seconds 0.28). Also, ling's "98% of 479 runs" is a run-level bound;
with failures on 3–4 of 48 tasks the task-level bound is about 83–92%. *Implication: do not build the P3 router on
this data, and treat the 95% floor as "passes the fixtures", not a quality guarantee.* **Confirmed by P2 and P2b**: on real-sized tasks ling drops to 10%, deepseek-off to 72%, Haiku to 83%, while Sonnet passes all ten.

**F3. Detector numbers come from enriched samples and the shipped grader isn't the one measured (high).** The judge
calibration sets hold 45% (cf5: 118 failures vs 144 good, 81 of 90 Haiku-judged failures synthetic) and 65% (bank1
judges) failures; real rates are 1–2% for the recommended models and 6% across cf2. Corrected to a 2% base rate
(*modeled from the measured recall and false-alarm rates*): Haiku judge (parent path) 44% precise, Haiku reviewer
20%, deepseek reviewer 48%; at 6%: 71%, 43%, 74%. COST_ARCHITECTURE.md cites "Haiku 67%" on bank1, but Haiku never
judged bank1; the 67% is cf5. On real hard-tier failures (mercury, cf3a) the Haiku parent path catches 3 of 12 at 33%
precision (kappa 0.23) and the grader path 7 of 12 at 24% (kappa 0.25). The shipped default grader
(`ModelPool.grader`, `ModelPool.swift:257–263`) for the common case (importance high, no tier, so the run is on Haiku)
skips the run's own model and falls back to the strongest reviewer, Opus; the code comment says so, COST_ARCHITECTURE
says "Haiku grades importance: high". An Opus grade is about $0.019 (40× a Haiku grade of $0.00048). Nobody measured
Opus as a grader. The reviewer figures "51–56 of 56 bad changes" are 48 synthetic degradations plus 8 real failures
(deepseek 6 of 8, Haiku 8 of 8).

**F4. The prompt cache is cold for every fresh run (high, and cheap to fix).** *Measured on cf6/cf3a/cf3b from each
request's usage:* Haiku read a cache across runs 0 times in 480 runs; every run wrote its first prompt; cache writes
are 54% of Haiku's cf6 cost. ling and deepseek (provider prefix caches) reuse only 256–512 tokens of a 1.7k–4.9k first
prompt, so the first difference is within the first 500 tokens. mercury and argon get 4–13% cache reads against 70–80%
possible. The cause is in `SystemPrompt.buildWithFacts` (`Agent/SystemPrompt.swift:116–140`): the Environment block
(project root path, platform, date, git summary) comes right after the working rules and before the tool list and the
instruction files, so any change in it invalidates everything after it; in the eval every run has its own temporary
path, and in a real session every subagent run rebuilds the prompt with the current git facts. Within one session the
prompt is frozen (`FrozenSystemPrompt`), which is why this Mac's sessions reach 64%; Claude Code's documented reference
is 91%. With ideal prefix reuse the cached share would be 84–87% at 10 requests and 95–96% at 40. *Probe: run 5 bank
tasks on Haiku twice within five minutes and read `cacheReadTokens` of the second set's first requests (now 0).*

**F5. Price priors are wrong or stale (medium).** (a) 340 deepseek-v4-flash-0731 runs of 2026-10-26 10:43–11:18 UTC
were recorded at a 10× OpenRouter listing glitch ($0.44/$1.32 per M instead of $0.0444/$0.1333); the cf6 list price
for deepseek is $0.00285 a run against $0.00183 charged and about $0.00045 at the correct list price. The pool note
"$0.0018 a run" (`ModelPool.swift:93`), COST_ARCHITECTURE's "≈$0.0004" and COST_FLOOR_RESULTS' "no list-price change"
are each wrong in a different direction. (b) ~~The shipped table's claude-sonnet-5-5 cache-read price is twice
OpenRouter's (0.20 vs 0.10 per M); Anthropic's docs give 0.05× base for Opus 5.5 and Sonnet 5.5 reads, so the table's
0.1× rule overcharges those two.~~ *Corrected in session 18:* Anthropic's own pricing lists Sonnet 5.5 cache reads at
$0.20 a million (0.1×) and Opus 5.5 at $0.20 (0.05× of $4), which is what the table has; only OpenRouter lists $0.10,
and OpenRouter-routed prices come from its live listing anyway. (c) gemini-3.8-flash is listed 10% above the shipped introductory price, and the
introductory Gemini prices end 2026-11-30 and 12-31 while the table's 60-day staleness warning (asOf 2026-10-14) fires
about 2026-12-13. (d) ling-3.0-flash, deepseek-v4-flash-0731 and mercury-2.5 are still listed, each with a dearer
successor. *Evidence: `spike/cost-audit/working-papers/code_audit.md` §C; the listing is saved beside it.*

**F6. Cost accounting misses, mislabels and misreads some requests, but does not double-count (medium).** Checked
and sound: entry ids, subagent nesting, retries, reconciliation (replaces the charge, never the list price), token
parsing for the three vendors, cache multipliers. Defects, each with a code path: requests made outside the agent loop
(skill routing in `ChatController.swift:1325` and `CLISession.swift:461`, post-run and `/review` reviews, `/compact`,
replays, calibration, the Settings chat test) never reach a run record, so `cost report` and the Spending window
disagree with the daily-limit counter; grader, reviewer, summarizer and fallback costs are summed into the parent run
under the parent's model and kind "main" (`Spending.swift:46–52`, `Subagents.swift:708,733`), and `whatif` reprices
them as if they were the main model's tokens; `whatif` compares a charge with a list price
(`DebugCommands.swift:252–264`), so repricing at the same model is not 1.00×; unpriced requests count $0 toward every
limit (`CostMeter.swift:42`: gemini-3.7/3.5/3.1 variants, claude-opus-4.5, claude-sonnet-4.5, api.openai.com are never
stopped); a run about to be retried is graded anyway (`Subagents.swift:704` before `:754`); the escalation estimate
(`Escalation.swift:92`) omits the cache-write premium and the hand-over diff, and the switch notice gives OpenRouter
models no figure (`PriceList.swift:113`). Report-level: `--eval NAME` needs the full path despite its help; `--by
model` merges reasoning-on and `#off`; "a success" divides priced spend by all passes including local ones (bank1
$0.011 a success against $0.020 a run); eval reports ignore subagent costs (`Spending.swift:188`). `kurtkode-eval` has
no `--help` and ignores `KURTKODE_NO_KEYCHAIN`.

**F7. Claims in the docs the data don't support (medium).** Reproduced and wrong or stale: "no judge makes the
cascade cheaper than Haiku" (GAP_ANALYSIS "Phase 3 measured": the deepseek-judge and local-qwen ladders cost $0.00108–
0.00140 a run against Haiku's $0.00154, passing 129–132 of 140 against 139; the trade-off is real but unstated); the
A4 "stopped early" figures (cf3a 70%/20% and cf2 96%/13% in the doc; 60%/13% and 96%/8% from the same replay today);
"19 main runs" (14 main, 5 subagent); "24 runs in 30 days" (19); "about 26,000 runs" (16,191 folders); "$0.0002 for
a live escalation to ling" (not in the session data; the doc itself says accepting was not tried live);
"gemini-3.8-flash checking every Gemma run costs $0.0033" (it judged 34 of 102; all of them would be about $0.0103);
COST_ARCHITECTURE swaps argon's precision and recall and writes "67%" for Haiku where 67% is Gemma's precision;
"no false alarms" for the reviewer (Haiku: 2 in 24). The retry ladder "catches 1 of 9" is right, and the rest of its
record is that 3 of its 4 firings were on runs that had passed: +1 pass in 479 for +1% cost. "Forced task call
(hosted)" was never exercised on a hosted model. The judge-cost replay charges a judge only on runs where it returned a
verdict (deepseek's grader path gave none on 82 of 140), prices local judges at $0, and escalates to a fresh clean run
with no hand-over cost: it is a lower bound on cascade cost.

**F8. The user's time is uncounted, and it dominates local "savings" (medium).** θ (D1) is unused; local models are
timed, not priced. *Measured:* Gemma 26B on bank1 takes 58 s a run on average (median 40 s, p90 127 s) against 17–19 s
for ling, Haiku or argon on the direct API; local delegation doubled a log sweep from 196 s to 419 s with no pass
gained (0 of 6). At θ = $30 an hour, 40 s of extra waiting is $0.33, over a thousand ling runs. By any θ above about
$1 an hour the local tier is the most expensive one per task, and "Thrifty" as designed would be the dearest mode.

**F9. Hidden costs (low–medium).** Fixed prompt overhead for a hosted session with all tools is about 8.7k tokens on
Claude and 6.4k on ling or deepseek (skills listing ≈2.1k, core tools ≈3.4–4.0k, hosted extras ≈2k, templates
≈1–1.4k; measured first requests 6.7k on Haiku, 4.9k on ling), about 85% of a bank-sized request; the user has decided
to keep the listing, so this is a fact to price, not a change to propose. Every OpenRouter run waits up to 10 s at its
end for a generation record that is usually not there yet. An important subagent change is reviewed every time
(cheap) and graded by Opus (not cheap). The eval leaves `kk-restore-*` folders in the temp directory (about 19,400,
2.6 GB, seen by the reproduction agent; not re-verified).

**F10. The literature agrees with the shape of what was found (context).** Routers rarely beat the best single
model and solve sets nest (LLMRouterBench 2026; Scrouting 2026); self-confidence and self-correction without
external feedback don't work (Huang 2024, Kamoi 2024, Lin 2026); agreement-based deferral works for short answers,
not shown for tool-using agents (Yue 2024, Kolawole 2025); a clean restart on the stronger model beats continuing the
weak trajectory (SWE-Router 2026, which matches D3's design); input tokens dominate agentic coding cost (Bai 2026);
the one structural result with a cost win is a cheap worker plus a single strong read-only review at the end
(Fireworks 2026, vendor data). Section 6 has the table.

## 3. Improvements, ranked

| # | Improvement | Expected effect | Effort | Risk | How to measure |
|---|---|---|---|---|---|
| 1 | **Make the prompt prefix stable across runs**: move the Environment facts (date, git summary, and for subagents the path if it varies) to the end of the system prompt or into the first user message (the `FrozenSystemPrompt` mechanism already carries facts in messages); keep tools and instruction files in the cacheable prefix | Haiku eval and subagent runs −40–50% (cache writes are 54% of cost; ideal reuse gives 84–96% cached); real sessions from 64% toward 85–90% cached; ling/deepseek provider caches from 256–512 tokens to the full prefix | small (one function, one test) | low; a resumed session already gets facts by message | `cacheReadTokens` of the first request of a second run within 5 minutes, before and after: 5 bank tasks on Haiku, ≈$0.02 |
| 2 | **Fix the prices**: re-record cf6's deepseek list price from the correct rate; a sanity rule in `RemotePrices` (a listing more than 3× the last seen one is held, not adopted); Sonnet 5.5 and Opus 5.5 cache reads at 0.05×; honor the Gemini `until` dates; refresh the pool notes | Reports stop overstating deepseek 5×; the pool's cheap tier is ordered right (deepseek at $0.00045 is the best cost per success on the bank, 99.8%) | small | low | `cost report --eval eval-results/runs/cf6 --by model` shows deepseek ≈$0.0005 list; `whatif` at the same model = 1.00× |
| 3 | **Grader default**: never fall back to the strongest reviewer silently; for a Haiku-run important task use the cheap reviewer path (deepseek, $0.0001) or no grade, and show the grade's price on the card | Saves ≈$0.019 per important subagent task (14× the run); removes an unmeasured judge from the default path | small | low–medium (deepseek as a judge of Haiku runs is unmeasured too; measure it on bank1's 42 real failures, ≈$0.05) | the proposed experiment P5 |
| 4 | **Change the escalation card's action from "re-run on the next tier" to "one strong read-only review of the diff, report and verify status"**, keeping re-run as the second button | Quality kept at ≈$0.005–0.02 a task instead of a $0.02–0.05 frontier re-run; the literature's one measured structural win (Fireworks: Opus-alone cost −66%); A6 has the machinery | medium | medium (vendor evidence; needs P3 below) | P3: strong review of the 21 real cheap failures on file, ≈$0.25 |
| 5 | **Account for every request**: record out-of-loop requests (skill routing, `/review`, `/compact`, replays, calibration, the settings test); label grader, reviewer and summarizer entries with their own model and kind; `whatif` list-vs-list; unpriced requests count at a default rate or stop the run; split `#off` in `--by model`; per-success denominators on priced passes; `--eval NAME`; `kurtkode-eval --help` and `KURTKODE_NO_KEYCHAIN` | Reports, limits and the Spending window agree; honest kind breakdowns | medium (many small sites) | low | a test per site: one request, one entry with the right model, kind and run |
| 6 | **Count the user's time**: a θ setting (default $20–60 an hour) shown as a second column in `cost report` and the Spending window ("time cost"), and in the local-vs-hosted comparison | Makes the local tier's real cost visible (Gemma 26B: 40–58 s a run against 17 s hosted); informs the Thrifty mode before it's built | small (display only) | low | the column exists; the decision is the user's |
| 7 | **Delegation threshold in absolute tokens** (TODO already): e.g. 30k tokens of broad reads, with the note only (no forcing) for frugal parents | argon-like parents −60% on read-heavy tasks when the user accepts; Sonnet-like parents unaffected | small | medium: forced delegation made Sonnet 1.7–2× dearer; keep it an offer | replay the delegation scenarios with the new rule (`--kk-delegation both`, ≈$0.20 on Haiku) |
| 8 | **Retry ladder (D3) off by default**, or limited to hard failures that aren't "made-up citations" | +1 pass in 479 for +1% cost today; 3 of 4 firings on passing runs | trivial | none | `--retry-sim cf6` |
| 9 | **Reconcile in the background** instead of waiting up to 10 s at every OpenRouter run's end (`CostReconciler` exists) | 10 s of the user's time per run | small | low | wall time of a `-p` run on OpenRouter |
| 10 | **A harder, real-sized task set** before any further cascade claim: 20–30 original tasks over real repositories with implementation-agnostic verifiers (the DeepSWE pattern), multi-file edits, 10–40 steps; and real-session labels (thumbs, rewinds, re-asks) kept in the run records | The only way to learn where cheap models stop; also the only data a router could learn from | large | low | P2 below; the next 20 tasks: REAL_TASKS_PLAN.md |
| 11a | **Pool default for real-sized work**: with `importance: high` or an edit task over a real repository, route subagents to Haiku, not ling (P2+P2b: $0.057 a success against $0.128, 83% against 10%); keep ling for bank-sized lookups | the shipped subagent default stops failing most real delegations | small | low | P2b done (the rates held at 16k); real-session labels next |
| 11b | **Escalate on the user's own test suite**: when a task has a verify command that is a real suite, make "the suite fails after the run" an automatic escalation trigger (Haiku → Sonnet ≈ −70% against always-Sonnet at Sonnet's pass rate); the eval's after-run re-check is fixed (the fixtures skip the sandbox-broken tests) | the one detector that is both free and near-perfect where it applies: in P2b it agreed with gold on all 12 re-runs | medium | low–medium (weak suites leak: Stroebl 2026) | P2b done; **built 2026-10-27** (section 9); live precision next (REAL_TASKS_PLAN.md) |
| 11c | **Eval harness**: raise the OpenRouter output cap for bank runs (`--max-tokens`, added; default still 4096), count in-flight runs toward `--max-cost`, let the sandbox deliver signals to the workspace's own children (the real fixtures now skip such tests), use charged prices for stale-listed models | fair cheap-vs-dear rates; no cap overshoot (the Sonnet process overshot by $3.30) | small | none | P2b (16k cap, skipped tests): done; in-flight counting and charged prices: open |
| 11 | **Shelve the P3 router** until ≥100 labeled real failures exist; revisit with task features that the literature finds predictive (files to edit, repository size), not text alone | Avoids building something the data can't validate (kNN below prior on cf2/cf6) | none | none | R2's Brier comparison on the new data |

## 4. Missing or wrong

**Design gaps.** No mechanism acts on a hosted main run's cost without the user's hand. The delegation threshold is a
share of the context, so the endpoint's context (32k default on OpenRouter, 200k native) decides whether it can fire.
θ is designed and unused. The grader design (D2: tool-less grader for important runs) was not revisited after the
eval found the grader path 15 points weaker than the parent path, and the shipped fallback (Opus) was never measured.
The P3 router's acceptance test ("beat always the same model") is right, and on the stored data it fails before being
built. The escalation card hands over "reasons and diff" and re-runs; it doesn't offer the cheaper strong-review
action. Same-vendor judging (Haiku judging Haiku or ling runs) was never measured; the shipped grader for ling runs is
Haiku, measured only on Gemini, Gemma and qwen runs.

**Accounting bugs** (section F6; probes in `spike/cost-audit/working-papers/code_audit.md` §B): out-of-loop
requests missing from run records; grader/reviewer/summarizer costs under the parent's model and kind; `whatif`
charge-vs-list; $0 unpriced requests against limits; grading before a retry; eval reports without subagent costs;
`--by model` merging `#off`; per-success denominators; `--eval NAME`. One more, found by the reproduction: the review
sample's rebuilt diffs are 6 bytes shorter than when reviewed (a later fix), so a `--review-sim` re-run would re-pay
for 18 rows.

**Stale data.** deepseek's 10× price glitch (340 runs; cf6 list prices; the pool note; three docs); the Sonnet 5.5
cache-read price; the Gemini introductory dates against the table's warning; the A4 "stopped early" figures;
"Phase 1 is being built" at the top of GAP_ANALYSIS.md; the three different counts of this Mac's runs.

**Unsupported claims.** Section F7's list; plus the sample sizes behind several "findings": reasoning off vs on (1
trial each), long-doc lean vs detailed (2 vs 2), deepseek as a judge (4 of 9 judged), the R6-10 retry trigger fix
checked on the one failure it was tuned on, bank1's "last check failed" precision on about 3 firings, the −48%
saving on 15 forced runs a side.

## 5. Experiments

### Run (free, offline, reproducible from `spike/cost-audit/scripts/`)

| Id | Hypothesis | Data and method | Result |
|---|---|---|---|
| E0 | The docs' numbers reproduce | `cost report --eval` on all 9 stores; `--retry-sim cf6`; `--trigger-sim` on 6 stores with the 5 ladders; `--review-sim bank1` on stored rows; python recount | All headline figures reproduce exactly (474/480; 12/15 at −48.2%; −63.7%; 1 of 9; 51/55; 16/23/17%; 2.4% and 67.5% of Haiku; kappa 0.67 and 0.71); the mismatches are in F7 |
| E1 | Agreement between two cheap models' reports flags failures | cf6 pairs (ling/deepseek/Haiku) and cf3a (mercury vs ling, deepseek, Haiku); word, identifier, path and last-sentence overlap; sweep thresholds; PR-AUC | No signal beyond empty reports: ling vs any, PR-AUC 0.077 at a 1.9% base rate, best point = the 2 empty reports; on non-empty reports 0.012–0.021. mercury (8.6% base): PR-AUC 0.17–0.25; vs deepseek recall 25% at 43% precision. Cascade: ling + deepseek tuned to Haiku's pass rate costs $0.00134 against Haiku's $0.00144 |
| E2 | A second trial of the same model flags failures | cf6 and cf3a, each run against its other trials | ling PR-AUC 0.064 (one extra trial) to 0.099 (nine); mercury 0.16–0.28 (recall 58% at 26% precision, fires on 19%), but two mercury runs already cost more than one Haiku run |
| E3 | Where a run's money goes | per-request usage in cf6, cf3a, cf3b, bank1 | First request = 30–46% of a bank run's cost (16–29% hard tier); Haiku cache writes 54% of its cost, cross-run reads 0 of 480; ling/deepseek reuse 256–512 tokens; argon 4–7% cached of 70–80% possible; ideal reuse → 84–96% cached at 10–40 requests |
| E4 | Failures cluster by task | cf6, cf3a against a random-placement null | ling 9 failures on 4 tasks (8.3 expected, p < 0.0001); mercury 12 on 5 of 14 (8.4, p = 0.002); escalation can help only on `h-discount-code`, `importers-of-storage`, `review-diff` (ling fails, Haiku 10/10); Haiku's own failures are formatting (`h-aliased-calls`: a table without `path:line`) |
| R1 | A per-task oracle router has headroom | cf6, cf3a (+Opus/Sonnet from cf3b) | Oracle 100% at 1.3× ling (same trials), 99.6% at 1.2× (fresh trials, cf6), = ling on cf3a; −77–79% vs Haiku where ling alone is −80–83% |
| R2 | Task text predicts failure (the P3 premise) | leave-one-task-out TF-IDF kNN, k = 3, 5, vs per-model prior; Brier; router simulation at 0.9/0.95/0.98 | kNN worse than prior on cf2 (0.0630 vs 0.0586) and cf6 (0.00245 vs 0.00216), tie on cf3a; the simulated router is worse than always-ling on cf2 (94.6% at $0.00024 vs 98.2% at $0.00018), +0.4 points at +20% cost on cf6, = ling on cf3a |
| R3 | A static difficulty rule beats kNN | rank correlations of failure count with prompt length, kind, edit-vs-read, steps, tokens, seconds | Nothing pre-run is significant (|ρ| ≤ 0.37, p ≥ 0.14; signs flip between stores); post-run output tokens ρ = 0.38 (p = 0.05): a cascade's signal, not a router's |
| R4 | The pool ordering is price-fragile | cost per success at the measured pass rates | ling's price must rise 1.9× (deepseek at $0.00045), 5× (Haiku), 73× (Sonnet), 112× (argon), 147× (Opus) before they tie; a silent cheap failure must cost over $0.027 (deepseek) or $0.11 (Haiku) for those to win on expected cost |
| W | Savings on a defined day mix | 10 short lookups + 6 small edits + 4 long tasks (long = 10× a hard-tier run; sensitivity 0–12 long tasks and 70–95% cheap pass on them) | Table in section 1: short tasks cheap saves 11–43% of a Sonnet bill; trigger quality changes failures per day (0.08–0.31), not dollars; all-cheap costs $0.017 a day and 0.4–1.4 failures a day |
| B | Base-rate correction of judge and reviewer precision | the measured recall and false-alarm rates at 2, 6, 10, 25% failure rates | Haiku judge 44/71/81/93%; Haiku reviewer 20/43/57/80%; deepseek reviewer 48/74/83/94%; Haiku judge on mercury 10/25/37/64% |

### P2, run 2026-10-26 evening, and P2b, 2026-10-27: cheap models on real-sized tasks (paid, approved: `--max-cost 10`, then `--max-cost 1` twice)

**Task set.** Ten tasks from the git history of responsedigger (a private Python project of the user's, 16 modules,
4,200 lines, 90–102 tests): for each feature commit, the repository as it stood before it, with the commit's tests
already in `tests/`, and the task written from the commit message naming the interfaces the tests use. Pass = the
whole suite passes (`pytest`, 30 s) and no existing test was changed; `src/`, docs and new test files may change.
Solutions are 25–119 source lines over 1–7 files; 1–28 tests fail before the change. All ten were validated offline
(fail before, pass after). The set is in the harness as `--bank real` (`EvalKit/TaskBankReal.swift`, fixtures and
`tasks.json` in `eval-results/real-fixtures/`, 2 unit tests), with a per-task wall clock and a `--max-tokens`
option added to `kurtkode-eval`. Settings: 32k context, 60 steps, 1,800 s, OpenRouter for all four models, the
built-in skills listing, `--no-train`. Store: `eval-results/runs/real1` (72 runs, the 12 truncated cells replaced by P2b's); scripts and logs in
`spike/cost-audit/scripts/real-set/` and `working-papers/real1*`.

**Results, final store after P2b** (strict = gold with the corrected test rule: the suite passes, no existing test line removed, nothing outside `src/`, tests and docs changed; lenient = the suite passed, whatever else changed; costs are charged where the
provider reported one, else list):

| model | trials | strict pass | lenient pass | $/run | $/success (strict) | steps | s | prompt tokens | cached |
|---|---|---|---|---|---|---|---|---|---|
| ling-3.0-flash | 21 | 2 (10%) | 5 (24%) | $0.012 | $0.128 | 54 (18 hit the 60 cap) | 284 | 735k | 91% |
| deepseek-v4-flash-0731, reasoning off | 18 | 13 (72%) | 14 (78%) | $0.047 charged (list $0.129, stale) | $0.065 | 43 | 323 | 588k | 78% |
| Haiku 5.5 | 23 | 19 (83%) | 19 (83%) | $0.047 | $0.057 | 29 | 279 | 404k | 96% |
| Sonnet 5.5 | 10 | 10 (100%; 8 before the test-file rule was corrected) | 10 (100%) | $0.78 (median $0.52; two 60-step runs at $1.9) | $0.78 | 26 | 394 | 380k | 96% |
| qwen3-coder-30b, local, dry run | 1 | 0 | 0 | timed | – | 32 | 709 | 426k | – |

Per task, strict (passes/trials): ling passes only rd01 (2/3); deepseek fails rd02 (2/3), rd03 (1/3), rd04 (1/3);
Haiku fails rd04 (0/3) and rd05 (2/3); Sonnet passes every task; its two first-scored failures (rd06, rd08) appended 13 and 108 lines of new tests to existing files, which the first gold rule counted as touching tests. One ling run (rd01 #1) removed three test lines and fails under any rule. The models fail on the same tasks again
(rd04, the outage-grace change that breaks 28 tests at first, is the hardest for all).

**What this changes.**
1. **The cheap tier does not transfer.** ling's 98% on the bank is 10–24% here; it spends 45 steps a run and still
   fails. deepseek-off holds 72–78% and Haiku 83%, Sonnet 100% (10 of 10, one trial each). The 95% floor was a property of the
   fixtures, as F2 said; on real-sized work the shipped default subagent model is the wrong one.
2. **The cost-per-success order flips.** Haiku is the cheapest success ($0.057), below deepseek ($0.065 charged) and ling
   ($0.128, because it almost never succeeds), and about 14× below Sonnet ($0.78). The pool's "cheap
   before standard" ladder is right on the bank and wrong here; the audit's workload model assumed 85% cheap pass on
   long tasks, which holds for Haiku and deepseek, not for ling.
3. **The free re-run check is a near-perfect detector when the task has a real test suite.** By construction every failure here fails the suite, so "run the suite again after the run" would catch all 27 failures with no false alarm, and in P2b, with the four sandbox-broken tests skipped in the fixtures, it did: the after-run re-check agreed with gold on all 12 re-runs (3 passes exited 0, 9 failures exited 1). In P2 itself the re-check had exited 1 on all 60 remaining runs, because the sandbox breaks four stop-and-resume tests of this repository (they signal child processes) that gold, running unsandboxed, passes; every model saw four unfixable failures. The agent's own last verify call is a weaker signal that does work: "no clean run recorded" (no verify call, or exit 1) flags 24 of 27 failures with 7 false alarms in 45 passes (recall 89%, precision 77%). A
   Haiku → Sonnet cascade on the re-run check would cost about $0.047 + 0.17 × $0.78 ≈ $0.18 a run at Sonnet's pass
   rate, 75% below always-Sonnet (modeled from these cells; the hand-over cost and a fresh Sonnet run are assumed).
   This is the one place where automatic escalation pays, and it needs the user's tests, not a judge.
4. **Cheap models cost time.** 43–54 steps against 26–29, similar wall time per run but a quarter of the passes; at
   any θ the user's time makes ling the dearest option on this set.
5. **Two harness limits confounded the first rates**; P2b removed the first and the second is scored around. (a) The eval capped OpenRouter replies at 4,096 output
   tokens and ended a run after three replies cut mid-call; 12 failures stopped as "truncated" (Haiku 5 of its 6,
   deepseek 2, ling 5). Re-run at `--max-tokens 16384` (P2b below) none was truncated, and they split 3 passes, 9 failures: the
   truncations had hidden two Haiku passes and one deepseek pass, not more.
   (b) the strict stray-file rule failed 5 runs that passed the suite for creating `.python-version` (ling, 3) or
   `config/secrets.toml` (deepseek, 2), and failed Sonnet twice for adding test files until the gold was corrected and
   the store re-scored (the lenient column).
6. **Within-run caching works** (91–96% of prompt tokens read from cache for every hosted model), which confirms that
   F4's cold cache is a cross-run problem, not a per-request one.
7. **Prices**: the eval priced deepseek at about 3× its charge (list $0.136 against $0.046 a run), the stale listing
   of F5 still in effect; Haiku's and Sonnet's list prices matched their charges.

**Spend**: $10.80 list ($3.00 process 1; $7.80 Sonnet). The OpenRouter key's usage rose $3.13 during process 1 and
about $7.80 during the Sonnet process, so about $10.9 charged, over the $10 named: the Sonnet cap ($4.50) is checked
before each run starts, and two $1.9 runs were in flight when it tripped. Improvement: the cap should count the
running runs' expected cost (one more defect for the Round 8 list).

**P2b** (2026-10-27, `--max-cost 1` per process, two processes). The 12 truncated run folders were moved to the Trash and
the cells resumed at `--max-tokens 16384`, with the fixtures re-packed to carry a root `conftest.py` that skips the four
sandbox-broken tests. Process A (ling 5, Haiku 5): ling 0 of 5 (four hit the 60-step cap, one errored out), Haiku 2 of 5 (rd03,
rd08 pass; rd04 twice and rd05 fail with 1–6 tests still failing); $0.55 list, $0.55 charged by the key's usage delta. Process B
(deepseek-off, rd04 and rd05): 1 of 2 (rd05 passes in 19 steps; rd04 hits the step cap); $0.11 list, deepseek charged at about a
third of list. No run was truncated. Total ≈$0.66 list. Net effect on the rates above: Haiku 74% → 83%, deepseek 67% → 72%, ling
unchanged at 10%; the order of the models and of cost per success is unchanged, so improvement 11a stands at the measured
strength and the P2 conclusions hold without the cap caveat. rd04 (the outage-grace change) stays the one task Haiku never
passes, and deepseek and ling mostly fail it; it is the natural first escalation case.

### Proposed (paid; for the user's approval, each with `--max-cost` and one process per run)

| Id | Question | Method | Estimate | Priority |
|---|---|---|---|---|
| P2 | ~~Do cheap models hold on real-sized tasks?~~ **Run** (above): no for ling, partly for deepseek-off and Haiku | — | spent $10.80 list | done |
| P2b | ~~The truncated cells re-run fairly~~ **Run** (above): 3 of 12 pass at 16k; Haiku 83%, deepseek 72%, ling 10%; the re-check agrees with gold once the sandbox-broken tests are skipped | — | spent ≈$0.66 list | done |
| P1 | ~~Does the prefix fix restore cache reads?~~ **Run** (section 9): yes, 8 of 10 first requests read the cached prefix | — | spent $0.014 | done |
| P3 | ~~Is one strong read-only review at the end as good as a re-run?~~ **Run** (section 9, Sonnet only): 22 of 22 real failures flagged, 1 false alarm in 12 passes | — | spent $0.32 | done |
| P5 | Judge precision at real base rates, same-vendor pairs | Haiku and deepseek, parent path, on all 42 real bank1 failures and 200 passes | ≈$0.30 | third |
| P4 | Real-session labels | a month of the user's own sessions with thumbs, re-asks and rewinds kept per run; no extra spend | $0 | ongoing |
| P6 | ~~Forced delegation live~~ **Run as the improvement-7 replay** (section 9): Haiku never delegated, note or not | — | spent $0.15 | done |

## 6. Literature

Full annotated bibliography (about 55 sources, each marked opened or snippet) in
`spike/cost-audit/working-papers/literature.md`. The ones that bear on kurtkode's choices:

| Source | What it found | Implication for kurtkode |
|---|---|---|
| FrugalGPT, Chen et al., TMLR 2024, https://arxiv.org/abs/2305.05176 | Cascades match GPT-4 at up to 98% lower cost on QA with learned answer scorers | The tiered-pool idea is sound; the number is from short answers, not agents |
| LLMRouterBench, Li et al., ACL Findings 2026, https://arxiv.org/abs/2601.07206 | Many routers, including a commercial one, don't reliably beat the best single model; curation beats ensembles | Matches R1/R2; keep the pool small; P3's acceptance test is the right one |
| Rethinking Predictive LLM Routing (kNN), Li 2025, https://arxiv.org/abs/2505.12601 | Tuned kNN matches learned routers; margins over trivial baselines are small | The kNN design is reasonable in form; on this data it has nothing to learn |
| Scrouting, Bhola et al. 2026, https://arxiv.org/html/2608.04804 | Solve sets nest (containment 0.77–0.94); gains are in cost, not accuracy; 199 of 249 claimed reproductions were fake | Matches the clustering (E4, R1); supports grounded checks over self-report |
| SWE-Router, Son et al. 2026, https://arxiv.org/html/2607.00053v1 | Scoring a cheap model's first 1–4 turns lifts route-AUC from 0.55–0.63 to 0.70–0.78; restart the strong model clean; count the sunk cost | Supports D3's clean restart and R3's "signals appear after the run starts" |
| vLLM semantic-router note 2026, https://github.com/vllm-project/semantic-router/issues/5374 | Post-hoc judge AUROC 0.68–0.86 (Terminal-Bench), 0.67–0.76 (SWE); escalation gains have intervals including zero; one pair negative | Advisory-only escalation is the defensible default |
| Agreement-Based Cascading, Kolawole et al., TMLR 2025, https://arxiv.org/abs/2407.02348; Semantic Agreement, Soiffer et al., EMNLP 2025, https://arxiv.org/abs/2509.21837 | Ensemble disagreement as a training-free deferral signal, ≈40% of target cost on free-form answers | E1 found no such signal on agent reports; agreement on diffs is undefined |
| Correlated Errors in LLMs, Kim et al., ICML 2025, https://arxiv.org/abs/2506.07962 | Models agree on the same wrong answer ≈60% of the time; more so within a vendor | Supports cross-vendor review; two cheap models agreeing is weak evidence |
| Can LLMs Express Their Uncertainty?, Xiong et al., ICLR 2024, https://arxiv.org/abs/2306.13063; Lin et al. 2026, https://arxiv.org/abs/2609.07395 | Verbalized confidence is overconfident; agent self-confidence doesn't beat a naive baseline | Don't add a self-confidence trigger |
| LLMs Cannot Self-Correct Reasoning Yet, Huang et al., ICLR 2024, https://arxiv.org/abs/2310.01798; Kamoi et al., TACL 2024, https://arxiv.org/abs/2406.01297 | Self-correction needs reliable external feedback | The verify re-run is the right kind of signal; an LLM re-checking itself is not |
| JudgeBench, Tan et al., ICLR 2025, https://arxiv.org/abs/2410.12784; CodeJudgeBench 2025, https://arxiv.org/abs/2507.10535; Bias in the Loop 2026, https://arxiv.org/html/2604.16790v1 | Judges are near chance on subtle errors; thinking judges beat bigger ones; small judges are badly position-biased | A cheap no-tools grader on hard items is close to a coin flip (matches 24% precision on mercury) |
| Agent-as-a-Judge, Zhuge et al., ICML 2025, https://arxiv.org/abs/2410.10934 | A judge that can read the workspace agrees ≈90% with experts vs ≈70% for a plain judge | Supports the parent path over the grader path (as the eval found) |
| Rethinking Agent-Generated Tests, Chen et al. 2026, https://arxiv.org/abs/2602.07900 | Agent-written tests are print-style probes and don't change outcomes | Don't use test generation as a detector; use pre-existing checks |
| Limits of Inference Scaling Through Resampling, Stroebl et al., ICLR 2026, https://arxiv.org/abs/2411.17501; Wang et al., ICSE 2026, https://arxiv.org/abs/2503.15223 | Weak verifiers cap accuracy; SWE-bench validation inflates resolution by 6 points | "verify passes" is leaky; keep the diff review and unnamed-files check beside it |
| How Do AI Agents Spend Your Money?, Bai et al. 2026, https://arxiv.org/abs/2604.22750 | Input tokens dominate even with caching; same-task token use varies up to 30×; accuracy often peaks at intermediate cost | Matches lesson 8; several trials per cell; "spend as little as the work allows" has a floor |
| Anthropic prompt caching docs, https://platform.claude.com/docs/en/build-with-claude/prompt-caching | Writes 1.25× (5 min) or 2× (1 h); reads 0.1×, 0.05× on Opus 5.5 and Sonnet 5.5; tool, effort or thinking changes invalidate | F4 and F5(b) |
| Anthropic multi-agent research system 2025, https://www.anthropic.com/engineering/multi-agent-research-system; Google, Scaling Agent Systems 2025, https://arxiv.org/abs/2512.08296 | Multi-agent ≈15× tokens; helps parallel reading, hurts sequential edits | Delegate exploration only; matches "argon −63% on the log sweep, Sonnet dearer" |
| Harness design study, Fan et al. 2026, https://arxiv.org/abs/2609.20804 | Rule-based elision of old tool output beats LLM summarization on cost | Prefer trimming to summarizing in compaction |
| Fireworks, open worker + closed advisor 2026, https://fireworks.ai/blog/frontier-open-source-worker-with-closed-source-advisor | One strong read-only review at the end: Opus-alone cost −66%, quality kept; the worker reviewing itself gave no lift (vendor data) | Improvement 4 |
| Claude Code costs and subagents docs, https://code.claude.com/docs/en/costs, https://code.claude.com/docs/en/sub-agents; Codex config, https://learn.chatgpt.com/docs/config-file/config-reference; opencode, https://opencode.ai/docs/config/ | Manual per-role tiering (Haiku for simple subagents, a `review_model`, a `small_model`), effort levels, compaction; 91% cache-hit example; no automatic escalation anywhere | kurtkode's automatic subagent routing is already ahead of practice; its cache share is behind |
| Cursor Router 2026, https://cursor.com/blog/router | A pre-task classifier trained on 600k live requests; offline evals omit cache-miss cost; 30–50% savings claimed | The one production router; needs data kurtkode doesn't have; counts the switch cost as kurtkode does |
| DeepSWE 2026, https://arxiv.org/abs/2607.07946; SWE-Bench Pro 2025, https://arxiv.org/abs/2509.16941; OpenAI on SWE-bench Verified 2026 | Original tasks with implementation-agnostic verifiers; held-out splits; saturated sets can't separate tiers | The model for improvement 10 |
| Al-Haque & Johnson, ESEM 2026, https://arxiv.org/abs/2608.18280 | Static task features (patch fragmentation, repository scale) predict difficulty at AUC 0.86 | If a router is ever built, use those features, not text alone |

## 7. Decisions for the user

1. ~~Spend ≈$8 on P2?~~ Done (the user said yes; $10.80 list, section 5). ~~P2b?~~ Done (the user said yes; ≈$0.66 list):
   Haiku 83%, deepseek-off 72%, ling 10% at a 16k output cap, so the P2 picture is confirmed, not an artifact of the cap.
   **Next on this thread: the subagent default for real-sized work (improvement 11a)**: (a) Haiku for edit tasks over a real
   repository and for `importance: high`, ling kept for bank-sized lookups; (b) deepseek-off there (72%, $0.065 a success
   charged, but 3× dearer at list while the listing is stale, and 43 steps a run); (c) leave ling. *Recommendation: (a)*.
   **Done (a), session 18** (section 8).
2. **Fix the prompt prefix (improvement 1)?** It changes product behavior (the order of the system prompt), so it is
   your call. Options: (a) move the facts to the end of the system prompt; (b) move them into the first user message
   as `FrozenSystemPrompt` already does on resume; (c) leave it. *Recommendation: (a)*, measured by P1. **Done (a),
   session 18, with a cache breakpoint before the changing part; P1 confirms it (section 9).**
3. **The grader for a Haiku-run important task**: (a) Opus, as now, with the price shown; (b) the deepseek reviewer
   path; (c) no second opinion (the A6 review still runs). *Recommendation: (c) until P5 shows a cheap judge is worth
   it at the real base rate.* **Done (c), session 18.**
4. **The escalation card's first action**: (a) re-run one tier up, as now; (b) one strong read-only review, re-run as
   the second button. *Recommendation: (b) after P3.* **Done (b), session 18, after P3 (section 9).**
5. **The P3 router**: (a) shelve until real-session labels exist; (b) build it anyway on the eval data.
   *Recommendation: (a).* **Shelved; nothing built.**
6. **Count the user's time** with a θ column (display only): (a) yes at $30 an hour, editable; (b) no.
   *Recommendation: (a).* **Done (a), session 18.**
7. **The retry ladder**: (a) off by default; (b) keep. *Recommendation: (a)*; it is nearly inert either way. **Done (a), session 18.**
8. **Accounting and price fixes (improvements 2, 5, 8, 9)**: these don't change what runs, only what is recorded and
   shown; *recommendation: do them in one Round-8 pass with a test per site.* **Done, session 18** (section 8), except
   the calibration and escalation purposes (B9's last two) and eval runs' children (B11, latent).

The branch was merged into main on 2026-10-27 (fast-forward, not pushed); section 9 has what was measured after the
decisions.

## 8. Implemented after the audit (session 18, 2026-10-27)

The user asked for the recommended decisions to be implemented in the recommended order, with no paid calls. Each is
one commit on the branch `cost-audit-improvements` (merged into main 2026-10-27), with unit tests; the AgentCore suite and the app build
pass. Nothing here was measured live: P1 (the prefix fix) and P3 (decision 4) remain.

| Decision or improvement | What changed | Verified by |
|---|---|---|
| 11a, decision 1 | A task card with no tier asks for the standard tier (Haiku) when its kind is edit, refactor, fix or write-tests, as for `importance: high`; lookups stay cheap | routing tests |
| 1, decision 2 | The project root, date and git status are the system prompt's last section, under a fixed heading; a profile's addendum and a subagent's role go before it. The Anthropic and OpenRouter-Claude encoders split the prompt there and put a cache breakpoint on the stable part (same TTL as the automatic one) | tests: two folders on two days share the stable part byte for byte; both wire shapes. **Not measured live (P1)** |
| 3, decision 3 | The automatic grader is the pool's first judge that isn't the run's model, or none; no fallback to the strongest reviewer | routing tests |
| 8, decision 7 | The retry ladder is off unless `subagentRetry` is on (Settings → Model pool) | settings and retry tests |
| 6, decision 6 | `hourlyRate` ($30, 0 hides it): "wait a run" and "time cost" in `cost report` (`--hourly N`) and the Spending window; Settings → Spending edits it | tests; on real1 at $30 an hour, waiting cost $33–53 a model against $0.26–7.80 charged |
| 2 | OpenRouter listings that move more than 3× from the last adopted price are held until a read 6 hours later confirms them (remembered in `~/Library/Caches/kurtkode/remote-prices.json`); explicit intro-price tie-break; pool notes with P2 results. cf6's 340 glitch-priced deepseek runs corrected (`spike/cost-audit/scripts/fix_cf6_deepseek_listing.py`; originals in `eval-results/backups/`) | tests; cf6 deepseek now $0.00048 a run at list |
| 5 (B4, B8, B9, report items) | whatif compares list with list; "a success" over priced passes; a run about to be retried isn't graded; grader and reviewer entries say "grader"/"reviewer"; `--eval NAME`; `kurtkode-eval --help` and `KURTKODE_NO_KEYCHAIN` | tests; CLI runs |
| 5 (B2, B3) | Reports rebuild each run's totals from its cost entries; another model's grading, review, summary or fallback is filed under that model; requests outside any run, and runs that left no record, get rows of their own that don't count as runs | tests; on this Mac's last 30 days, $0.11 of $0.33 was in requests no run record held |
| 5 (B5) | A remote model with no known price counts toward limits at $3/$0.30/$15 a million; the stop note says how much is estimated | tests |
| 5 (B7) | The escalation estimate prices the history at the cache-write rate and adds 3,000 tokens of diff when the run changed files | tests |
| 9 | Sessions look once for OpenRouter's records at a run's end instead of waiting up to 10 s; the app reconciles every 10 minutes; reports read settled charges | tests |
| 11c | `kurtkode-eval --max-cost` counts the expected cost of runs in flight and of the next one | tests |

Not done in that pass: improvement 4 (needed P3) and improvement 7 (to be measured first); both were done after the paid
runs (section 9). Still open: B9's calibration and escalation purposes, B11.

Found while doing it: OpenRouter listed deepseek-v4-flash-0731 about 3× higher on 2026-10-27 ($0.119/$0.238 per M, cache
reads $0.0238, against $0.0444/$0.1333/$0.0014 the day before). The held-price rule adopted it, since input and output
moved less than 3×. Repriced at the new listing, a real-sized deepseek-off run (588k prompt tokens, 78% cached, 11k out)
is about $0.029 at list, $0.040 a success, still below Haiku's $0.057; its charges, not its list, are what to watch.

## 9. Measured after the decisions (session 18, 2026-10-27, paid, approved)

The user approved the paid items. Total spent: about $0.48 (P1 $0.014, P3 $0.32, the improvement-7 replay $0.15),
each process with `--max-cost`. Commands, logs and stores: `eval-results/runs/p1-prefix`,
`eval-results/review-sim/cf6-rows.jsonl` and `cf3a-rows.jsonl`, `eval-results/delegation-note/`.

**P1, the prompt prefix (improvement 1).** Haiku 5.5 on five bank tasks (`add-median`, `fix-calc`, `find-tax-rate`,
`count-tests`, `explain-checksum`), two trials each, one at a time. The first request of every run after the first of
its agent kind read the cached prefix: 6,478 tokens for the edit agent, 2,089 for the read-only one (8 of 10 runs; the 2
misses are each kind's first run, which wrote it). Before the fix, 0 of 1,463 stored Haiku runs (cf1, cf2, cf3a, cf6,
real1) read anything on their first request. The same five tasks cost $0.0014 a run (mean of task means) against $0.0022
in cf6, about −37%, on two trials a task.

**P3, a strong review against a re-run (decision 4).** Sonnet 5.5 through OpenRouter as `--review-sim` reviewer: the
change rebuilt as a diff, with the request, report and checks, one request per run. It flagged **22 of 22 real
failures** (cf6 3 of 3, all "wrong"; cf3a 19 of 19, 3 "wrong") and **1 false alarm in 12 passes** (cf6), at $0.006–0.011
a review, against $0.02–0.05 for a frontier re-run. The caps stopped cf6 at 15 of its 23 sampled runs and cf3a at 19 of
31, so cf3a's passes and 10 of its failures were not reviewed; real-sized (real1) failures were not reviewed (larger
diffs, ≈$0.03 a review). For comparison, the stored bank1 reviews: Haiku caught 8 of 8 real failures with 2 false alarms
in 24 passes at ≈$0.0005; deepseek-off and gemini-3.8-flash 6 of 8, none in 24. So a review catches failures about as
well as anyone can measure here, for a fifth to a tenth of a re-run; it does not fix them.

**Decision 4, built (commit 2e9e131).** For a run that changed files, the escalation card's first action is one
read-only review of the change on the model the offer would escalate to ("Review on X for ≈$", priced as 4,000 tokens
in and 800 out); the re-run is the second button. After the review the card shows the verdict, and the findings can go
to the session's model to fix, or the request to the stronger model. The CLI asks r/e/N, then f/e/N. Offers record
`reviewed`; offers made by A6's review, and runs that changed nothing, keep the re-run only. Tests: offer pricing and
old-record decoding; the CLI review goes to the offer's model with the pool entry's pins.

**Improvement 7, built (same commit) and replayed.** Six reads in a row adding up to `delegationTokens` (30,000) earn
the note to delegate whatever the context size; this trigger never forces a task call. The delegation scenarios read
only 3.5k–8.8k tokens, so the replay scaled the trigger to 3,000 tokens: Haiku parent, 200k context, subagents on the
pool, three trials, the trigger off (`--delegation-tokens 0`) against on (`3000`).

| scenario (expected) | off: pass, delegated, note | on: pass, delegated, note |
|---|---|---|
| survey (yes; 16k cap) | 1/3, 0/3, 3/3 | 2/3, 0/3, 3/3 |
| log-sweep (yes; 16k cap) | 3/3, 0/3, 0/3 | 3/3, 0/3, 0/3 |
| two-questions (yes) | 3/3, 0/3, 0/3 | 3/3, 0/3, 0/3 |
| tiny-lookup (no) | 3/3, 0/3, 0/3 | 3/3, 0/3, 0/3 |
| small-fix (no) | 3/3, 0/3, 0/3 | 3/3, 0/3, 0/3 |

The new trigger never fired: on the uncapped scenarios Haiku never made six broad reads in a row. Where the old
fifth-of-context rule gave the note (survey's 16k cap, both arms), Haiku ignored it 6 times of 6; survey's pass
difference is between arms that got the same note, so it is noise. Reading: the trigger is harmless (no note on the
scenarios that shouldn't delegate) and Haiku, like the earlier parents, does not act on a note; it can only pay off for
a parent that accepts, in sessions that really read 30k tokens in a row. Nothing here says to force it.

The branch is merged into main (2026-10-27). What is left: P5 (judge precision at real base rates, ≈$0.30) and P3 on
real-sized failures (≈$0.70–1.00) if the escalation card's review is to be priced for real work; not built: 11c's
charged prices, B9's calibration and escalation purposes, B11; improvement 10 has 10 of its 20–30 tasks, and
REAL_TASKS_PLAN.md plans the next 20.

**Improvement 11b, built (2026-10-27, after the merge).** A project names its test suite as `"testCommand"` in
`.kurtkode/settings.json` (or `settings.local.json`, which wins). After a main run that changed files and ended on its
own, kurtkode runs it once more, authorized and sandboxed like any command, and records it with the run
(`signals.suite`). A failure or a timeout is an escalation reason ("the project's tests fail after the run (exit 1):
…"), and when the suite ran, its result replaces the model's own last check, the weaker signal (P2: 77% precision
against 12 of 12). A delegated task's check that fails when re-run at the parent's end is now also recorded on the
parent's run (`signals.failedRechecks`) and is a reason too. No project names a command by default, so nothing changes
until one does. Tests: `TestSuiteTests` (reading the setting; reasons and precedence; a live run that passes, fails,
changed nothing, or is a subagent's) and the parent's record in `aFailingCheckRunAgainIsAHardFailure`. Not measured
live: the escalation it triggers is still the one-click card (decision 2), and its precision on real sessions is P4's
and the plan's to measure.

## 10. Measured on real-sized tasks (2026-10-27/28, paid, approved)

REAL_TASKS_PLAN.md has the details: 11 new real tasks (responsedigger and kurtkode, hidden tests and lookups), the
Main row (Haiku, deepseek-off, ling, three trials), Frontier (Sonnet, one trial), P3 at real size, P5, and the live
cascade over all 21 real tasks. **$24.11** in all (Pilot $0.55, Main $3.23, the rest $20.33, of which $1.81 went to
runs set aside). Four grading faults were found and fixed on the way (edited test helpers, a test-suite name clash,
narrow lookup patterns, P3's diff); the numbers below are after them.

| on the 11 new tasks | pass | $ a run | $ a success |
|---|---|---|---|
| ling | 11/33 (33%) | 0.013 | 0.040 |
| deepseek-off | 14/33 (42%) | 0.053 | 0.124 |
| Haiku | 25/33 (76%) | 0.049 | 0.064 |
| Sonnet | 10/11 (91%) | 0.65 | 0.72 |
| **Haiku, escalating to Sonnet (main runs, 200k)** | **32/33 (97%)** | **0.092** | **0.095** |

What it changes:

1. **11a (Haiku for real-sized edits) holds, and the cheap tier is weaker than P2 showed.** ling and deepseek pass the
   easy tasks and the lookups but none or almost none of the harder kurtkode edits (kk02–kk04: 0 of 18 runs); Haiku
   passes 8 of 9. deepseek-off is dominated by Haiku on real work (lower pass rate at the same cost per run). Keep ling
   for lookups and bank-sized work.
2. **The cheap-first cascade works at real size**: over 63 runs, 84% on Haiku alone, 98% after escalation, every offer
   on a real failure and every escalation a fix, for $0.13 a run, about a fifth of Sonnet alone. What fired was mostly
   Haiku's reasoning running away (8 of 9 offers: all 16,384 output tokens spent thinking); the project's tests (11b)
   fired once, the step limit never. **Proposed**: (a) for a reply cut off with no text or tool call, retry once on the
   same model before offering escalation (≈$0.02 against ≈$0.72; measure first); (b) decide the standard tier's
   escalation target: the shipped pool sends Haiku to **Opus**, the cascade measured **Sonnet** (9 of 9 fixed).
   **Decided 2026-10-30: Sonnet** (an Opus cascade fixed 7 of 8 at $1.57 each against Sonnet's $0.72;
   REAL_TASKS_PLAN.md).
3. **11b's precision is fine, its reach is small**: the project's own tests catch a failure only when the visible tests
   see it. In Main the re-run flagged 10 of 40 hidden-test failures; in the cascade 1 of 10 offers. It costs nothing, so
   keep it, but it is not the cascade's main trigger.
4. **Decision 4's review (the card's first action) needs a stricter verdict at real size.** Sonnet's review caught 97%
   of real failures but flagged 60% of passes as "has problems"; "wrong" alone caught 74% with 1 false alarm in 47.
   **Proposed**: offer escalation after a review only on "wrong"; show "has problems" as findings to fix. Its price
   estimate (4,000 tokens in, 800 out: ≈$0.024 on Sonnet) matches the measured $0.015–0.026. **Done 2026-10-28**
   (section 11).
5. **A cheap judge is a trustworthy "fail" (P5)**: Haiku and deepseek-off, parent path, caught 57–59% of bank1's real
   failures with no false alarms in about 180 passes each; at about the same price per judgment ($0.0008 and $0.0010).
6. **Product gaps found by running main runs at 32k**: a main run that changes nothing on an edit request earns no
   offer, and the built-in `handoff-notes` skill ("use when running low on context") invites a model under context
   pressure to stop and write notes. At the models' real 200k context neither happened. **Proposed**: count "an edit
   request ended with no change" as an escalation reason; reword the skill so low context means compacting, not
   stopping. **Both done 2026-10-28** (section 11).
7. **Measure real work at real context.** The 32k used in P2, Main and Frontier depressed every model (rdh03: 0 of 10 at
   32k, 3 of 3 at 200k; Haiku 76% as a 32k subagent, 84% as a 200k main run). Later real-sized rows should use the
   models' own context.

## 11. Implemented after section 10 (2026-10-28, no paid calls)

The user said yes to the three free proposals of section 10. Each has tests; the full suite passes apart from the
usual LM Studio test and load-sensitive timing tests.

1. **Escalation after a review only on "wrong"** (point 4). `CodeReview.escalates` is true for "wrong" only. With
   Settings' automatic review on, a "has problems" verdict makes no offer: the app keeps the review in Changes (Fix
   These) with a notice, the CLI prints it and asks whether to send the findings to the session's model
   (`CLISession.reviewToFix`). On the escalation card, after its review, "wrong" makes escalating the main button and
   "has problems" makes fixing on the session's model the main button; both stay. Tests: `onlyAWrongReviewEscalates`,
   `onlyAWrongReviewEarnsAnOffer` (a CLI session, both verdicts).
2. **"It changed no files, though the request asked for a change"** (point 6), an escalation reason
   (`Escalation.gaveUp`): a main run that finished on its own, had edit tools (not Plan mode), was denied nothing,
   whose snapshots show no change, on a request that asked for one, and whose last reply isn't a question to the user.
   Whether a request asks for a change (`Escalation.asksForChange`, recorded as `RunSignals.changeAsked`): a task
   card's kind when there is one; otherwise a sentence that starts with a verb of change, has one after "and" or
   "then", or asks about "what you changed" (a question counts only as a polite request, "can you rename Foo?"). It
   agrees with the card on every bank and real-sized prompt (`ChangeRequestTests`), including the spec-style real
   prompts that describe the behavior and end "report what you changed and why"; a first-sentence-only rule missed
   them. Snapshots are required: the edit tools' file list misses command edits (sed, a script), and that fallback
   flagged 7 stored real-sized runs that gold passed.
   **Measured offline** (`--trigger-sim bank1,real1,real2`, free): it fires on 2 of 794 stored runs, both real
   failures (a Haiku run in real1, a deepseek run in real2), no false alarm. It would also have fired on the three 32k
   cascade runs that gave up (no change, completed, `rd03`/`rd04`). On the way: the trigger replay's change for a stored
   run, and `ReviewSim.ownDiff`, now diff against the fixture's last commit (the eval's), not its first: bank tasks
   like `fix-shop-total` have two ("fixture", then "broken"), and a correct fix looked like no change. Every stored
   real-sized fixture has one commit, so P3's rows are unaffected.
3. **`handoff-notes`** (point 6): its description is now "Use when asked to stop mid-task or pass work to another
   session… Not for your own context running low (it gets summarized) or plans", and its body says that context
   filling up is no reason to stop.

Seen on the way, not changed: two of the 32k give-ups' final replies were a compaction-style "Session summary (for
resuming)" and one began "I'm stopping here as you asked", though nobody asked; worth a look if 32k runs come back.


## 12. What the real-sized rounds decide (2026-11-04, no paid calls)

Written after the Go round. Data: 47 real tasks in six repositories (responsedigger and kurtkode, the user's; packaging,
sqlglot, cel-go and OPA, four other authors) in three languages (Python, Swift, Go), from the rounds in
REAL_TASKS_PLAN.md: section 10's $24.11, group D's pilot $0.05, the Opus cascade $15.98, the public round $9.85 and the
Go round $4.75, **$54.74** in all. Every failure in the later rounds was checked by hand.

| main rows, one model per run | the user's (32k) | `pkg`+`sqg` (200k) | `cel`+`opa` (200k) | all |
|---|---|---|---|---|
| Haiku | 44/56 (79%) | 31/36 (86%) | 31/33 (94%) | 106/125 (85%) |
| deepseek-off | 27/51 (53%) | 24/36 (67%) | 24/33 (73%) | 75/120 (63%) |
| ling | 13/54 (24%) | 11/36 (31%) | 11/33 (33%) | 35/123 (28%) |
| $ a success: Haiku / deepseek-off / ling | 0.064 / 0.124 / 0.040 (`real2`) | 0.036 / 0.090 / 0.027 | 0.032 / 0.143 / 0.033 | |

(The first column is `real1` and `real2`, run as 32k subagents; section 10's 7th point says 32k depressed every model.)

| cascade, Haiku main runs at 200k | Haiku alone | after escalation | $ a run |
|---|---|---|---|
| the user's, Sonnet (`cascade2`) | 53/63 (84%) | 62/63 (98%) | 0.13 |
| the user's with `rdw`, Opus (`cascade3-opus`) | 60/72 (83%) | 67/72 (93%) | 0.22 |
| `pkg`+`sqg`, Sonnet (`cascade4-pub`) | 28/36 (78%) | 33/36 (92%) | 0.17 |

### Settled: more tasks of the same shape won't move these

1. **Haiku is the default for real-sized edits (11a).** 76–94% in every repository and language. ling is as cheap
   or cheaper per success ($0.027–0.040), but it fails about 70% of runs, and each failure costs a rerun and the
   user's time.
2. **The cheap tier is for bounded work.** The order Haiku > deepseek-off > ling held in all three groups, and so did
   the pattern: bounded fixes pass for all three (pkg03, pkg05, pkg07, cel04, opa05), multi-part changes and big
   codebases (kk02–kk04, sqlglot, cel03, opa06, OPA's compiler) fail for the cheap tier. It's about size, not language.
3. **deepseek-off is dominated on real work**: below Haiku's pass rate at 2–4½× its cost per success in every round.
4. **Sonnet is the escalation target** (decided 2026-10-30): 14 of 16 rescues across `cascade2` and `cascade4-pub`, at
   less than half Opus's cost per rescue.
5. **Escalate after a review only on "wrong"; keep 11b's after-run tests; run real work at the models' own context.**
   All three are in the product (section 11).

Building more hidden-test edit tasks would re-confirm these. The spread rule (at least 5 tasks Haiku fails) isn't met
by the public or the Go sets, so such tasks also add few cascade escalations.

### Proposed, free (the user's call)

1. **The shipped pool's notes** (`ModelPool.shipped`) still quote P2's figures (Haiku 83%, deepseek-off 72%, ling
   10%). Update them to the table above. Text only; routing doesn't change.
2. **deepseek-off's subagent role.** Given 3 above, real-sized edits never should go to it, and 11a already sends them
   to Haiku. It stays useful as a reviewer and judge (P5: a cheap "fail" with no false alarms). Options: (a) drop
   `.subagent` from its roles; (b) leave it at ladder 1 for bank-sized work. *Recommendation: (a)*, since ling covers
   bank-sized work for a quarter of the price.

**Both done 2026-11-04 (the user's yes, (a)).** deepseek-off is now a reviewer only, off the retry ladder (ling, then
Haiku), and every shipped entry's note quotes this section. A saved `pool.json` keeps what it has. The ladder's own
tests run on a copy of the old three-rung pool (`ModelPool.threeRungs` in the tests).

### Open, and what each needs

1. **The router** (decision 5, shelved until about 100 labeled real failures). There are now 153 in `real1`–`real4`,
   75 of them at 200k. But 88 are ling's and 45 deepseek-off's, against 19 Haiku's, so a router trained on them mostly
   learns "not ling". Next: R2's Brier comparison on these rows (free, offline). The user's own session labels (P4)
   are still the better source for Haiku's failures, which are the ones that cost. **Checked 2026-11-06**: this
   Mac's sessions hold 41 main runs and 204 requests ($0.72 at list price, mostly local models) and 2 of the user's
   own judgments, and the installed app predates the signals, so P4 has no data yet; it needs a current install used
   for real work on a hosted model.
2. **A same-model retry on a cut-off reply** (section 10, 2a). Runaway reasoning is the main escalation trigger (7 of 8
   offers in `cascade4-pub`, 8 of 9 in `cascade2`). It needs a small paid run on the tasks that cut Haiku off only
   some of the time (pkg08, sqg02, sqg03, opa03): about $2. sqg01 cuts it off every time, so a retry there only costs.
3. **The escalation target's output limit.** Sonnet hit 16,384 tokens twice on sqg01 and changed nothing. One task, a
   few trials at a higher limit: about $2–4.
4. **Real-sized lookups: the one gap where new tasks would help.** ling's lookup role rests on three tasks, all from
   kurtkode (`kkq`), and Haiku's lookup misses can't trigger an escalation (no change, no tests). A few lookups from a
   second codebase would settle both; building is free, a round like the Go one about $5.
5. **Run mode or noise.** Haiku on `sqg` went from 8/12 as a subagent to 5/12 as a main run. Three trials can't tell
   which. It matters only if something is decided by run mode.
6. **Silent failures.** sqg03 #3 passes the visible suite, reports success, and fails a hidden case the prompt names.
   No grounded signal sees it; only a review (decision 4) could. Not measured how often this happens beyond that run.
