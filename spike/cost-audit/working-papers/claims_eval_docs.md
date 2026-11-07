# Claims extraction: kurtkode cost-optimization eval docs (read-only audit notes)

Sources (all under ~/git/kurtkode/). Abbreviations: CFR = COST_FLOOR_RESULTS.md, ER = EVAL_RESULTS.md,
SRD = SUBAGENT_ROUTING_DESIGN.md, CTD = COST_TRACKING_DESIGN.md, FTR = FUNCTIONAL_TEST_RESULTS.md, EP = EVAL_PLAN.md,
CFP = COST_FLOOR_PLAN.md, GAP = GAP_ANALYSIS.md (not on the reading list; read lines 760-925 only because CFR/SRD point to
"A6 review" and "retry ladder" numbers that live only there). I also skimmed AgentCore/Sources/EvalKit/TaskBank*.swift
headers/ids to confirm task composition. I ran nothing and made no network call, so no URL or price was verified.
"L123" = line 123 of the named doc. Percentages I computed myself are marked (calc).

====================================================================================================================
## 1. BENCHMARK DESIGN
====================================================================================================================

### 1.1 The 34-task bank (EP L78, ER L36-38, TaskBank.swift + TaskBankMore.swift)
- 16 original tasks (SRD P2, L558) + 18 added = 34 (ER L38 "34 tasks"; EP L78 "three or four per kind", one review with no bug).
- Ten kinds: search, explain, summarize, edit, refactor, fix, write-tests, review, research, run (SRD L147).
- By agent (from source ids): 23 read-only `explore` tasks, 11 `general` (can edit/run). Only 9 tasks actually change code
  (fix-calc, rename-total, add-median, write-pricing-tests, fix-rates, fix-shop-total, rename-discount-table,
  add-count-items, write-report-tests); run-script and count-tests only run things. (calc from source)
- Examples (ids): find-reserve-def, callers-reserve, class-in-file, file-for-class, insufficient-status, discount-for,
  calc-bugs-explain, log-error, list-classes, sum-csv, find-tax-rate, importers-of-storage, warn-count, warn-top-component,
  january-decisions, region-max, explain-*, grow-value, review-diff, review-shop-diff, review-clean (no bug), count-tests.
- Fixtures: "all small Python fixtures" (CFR L216): a server log, a shop module, a stats module, a diff to review, a
  checksum script, sales CSVs, meeting notes. maxSteps = 30 per task (TaskBank.swift L12). Context: 32k budget in cost-floor
  runs (CFR L220), 16k for delegation scenarios (ER L160, SRD L561).
- Tasks are "shaped like real delegations" (SRD L436): one self-contained prompt for a subagent, with a card.

### 1.2 The 14-task hard tier (CFP L81-89, TaskBankHard.swift L1-8, CFR L127-135)
- Run with `--bank hard`; deliberately NOT in `all` "so the 34-task bank stays comparable" (TaskBankHard.swift L4).
- 7 edit/run tasks (`general`): h-discount-code (thread an option through 3 files), h-config-migrate (INI to typed JSON),
  h-unit-bug (bug in a module the failing test doesn't name), h-leap-year (fix for every input; hidden cases),
  h-rename-trap (name is also a data key), h-edge-tests (tests must catch planted bugs; mutation testing),
  h-crash-diagnose (run a crashing script). 7 read-only (`explore`): h-plugins, h-log-correlate (two logs, decoys),
  h-import-cycle (10 modules), h-aliased-calls, h-mutable-default (subtle diff bug), h-retry-explain (backoff schedule),
  h-incidents (mixed units).
- Planned as "12-15 new, harder tasks ... same gold discipline (right, idle, wrong and stray-edit outcomes tested before any
  model runs)" (CFP L81-82).
- Outcome: frontier models pass all of it (CFR L28-30), so "This bank and hard tier no longer separate strong models" (CFR L31).

### 1.3 How a pass is decided
- Pass/fail = deterministic gold in code (`TaskBank.gold`): the task's own check (regexes over the REPORT TEXT plus file state,
  `python3 -c` hidden cases for some hard tasks, verify command re-run) AND "no file outside the task's allowed set changed"
  (TaskBank.swift L29-36; EP L73). Judges are NOT used to decide pass in the cost-floor study; they are only evaluated
  against gold (EP L31, ER L65: "Pass means verdict 2-3; fail 0-1").
- Many checks are string-matching on the model's prose (e.g. cites path:line within slack 1; `onlyRuledOut` negation word lists;
  `claimsOnly` import-chain regex, TaskBankHard.swift L10-40). Format is strict where prompt asks for it ("give path:line" fails
  a table with separate columns; costs Haiku 5.5 1 of 480 runs, CFR L178-179).
- Gold is tested before use: must pass a right outcome, fail an idle one, a plausible wrong one and a stray-edit one
  (ER L38, EP L99-107, TaskBankTests/TaskBankHardTests).

### 1.4 Trials per cell
- bank1 (EP/ER): 6 subagent models x 34 tasks x 3 trials = 102 runs/model (ER L47-54). Judges: trial 1's runs + copies.
- cost-floor stage 1: 1 trial x 6 tasks per configuration (CFR L99). Stage 2: 1 trial x other 28 tasks, only survivors <= $0.01/run,
  stopped at its $20 cap (CFR L100-103). Stage 3a: 25 configs x hard tier x 3 trials; the 12 best (>=93%) then 10 trials on bank
  and hard (480 runs each) (CFR L103-105). Stage 3b: 5 frontier refs x hard tier x 3 trials = 42 runs each (CFR L127-129).
  Stage 4: 5 delegation scenarios x 3 trials = 15 runs/cell (CFR L139). Stage 5: judges re-rate 204 stored runs (CFR L195).
  Re-run cf6: 3 finalists x (34+14) x 10 = 1,440 runs, 1,439 completed (CFR L246).

### 1.5 "Degraded copies" (EP L57-74, ER L41, SRD L569)
- A synthetic known-failure made from a PASSING run, kept only if gold then fails. Seven types: digits (change every multi-digit
  number in the report), wrong-file (swap each cited path for another same-extension file), drop-half (delete every other answer
  line), undo-half (reverse-apply first hunk), undo-all (reset project; report still claims success), vanish (delete created
  files), stray-edit (append edit to README.md).
- Counts: 332 kept (gold fails) + 127 stray-edit copies of read-only tasks "that the report leaves out" (ER L41). Judges
  rated 536 items (Gemini judges), local judges a fixed balanced sample of 300 (ER L42).
- Failure counts used for grounded-check table: 346 failures vs 190 good runs (ER L125, L127): a 65% failure base rate.
  The 262-run judge table has 118 failures / 144 good = 45% base rate (ER L65-70). Real model failures are only 14 of those.

### 1.6 "Enriched samples"
- ER 262-run set: runs "every judge rated" = 118 failures (real + degraded) + 144 good (ER L65). Enriched ~45% failures.
- GAP L817 / FTR R7-24 (L71 of the Round-7 block): A6's reviewer was evaluated on "the 32 sampled code runs (8 failures: an
  enriched sample, so precision reads high)"; FTR R7-24 says the trigger-table precision "came from the enriched review sample
  (8 failures in 32), not the population".
- A6 review-sim set: 80 runs = 8 real failures + 48 degraded copies (12 each of 4 types) + 24 good (GAP L777-778).
- Local judges: `--sample 300` balanced (ER L42).
- cf6 / cf2 trigger tables use unenriched populations: cf2 9,958 runs / 628 failures (6.3%); cf3a hard 2,226 / 70 (3.1%);
  bank1 612 / 42 (6.9%) (GAP L809).

### 1.7 Known gold bugs
- ER L170-177 (3, all fixed, 18 runs fail->pass): grow-value rejected shown working ("100 x 1.1 = 110.0"); review-clean took
  analysis words for an alarm; add-median counted added tests as outside-task edit. Plus an earlier "docstring" gold bug (EP L19; SRD L582).
- CFR L162-176 (8 rows / 9 tasks): h-aliased-calls, h-import-cycle, h-log-correlate, h-mutable-default, review-clean (again),
  count-tests, insufficient-status + find-reserve-def (range citations), review-shop-diff.
- ALL were right-answer-marked-wrong (false negatives): "Every one was a right answer marked wrong" (CFR L164). Before the
  fixes "the frontier references looked as if they failed up to 10 of their 42 hard-tier runs" (CFR L61-62).
- Regold over a whole large store "missed changes" twice on cf2 (9,961 runs), cause not found; re-scored per task (CFR L203-207).

### 1.8 What makes the benchmark easy or unrepresentative (my assessment, grounded in the docs)
1. Ceiling effect: Gemini 3.6/3.8-flash and argon 102/102 (ER L49-51); five frontier models 42/42 on hard tier; ling 99%. Docs
   concede it "separates local models from Gemini, not Gemini models from each other" (ER L11-12) and "show[s] that cheap
   models clear the floor, not where cheap models stop" (CFR L31-32). A 95% floor on a saturated benchmark selects "cheapest
   model that passes easy tasks".
2. Small, single-language (Python), self-contained fixtures; 30 steps; 32k context; one-shot specified prompts; no ambiguity,
   no user interaction, no build systems, no large repos (CFR L216; "bigger than these fixtures" is listed as not established, CFR L73-75).
3. 23 of 34 bank tasks and 7 of 14 hard tasks are read-only; only 9 bank tasks edit code. Edit-quality evidence is thin.
4. Gold is mostly prose-regex on the report. Every bug fix found so far LOOSENED a check (false negatives). Nothing in the docs
   reports a systematic hunt for false positives in real runs (wrong answers that pass); loosened regexes ("evaluated once",
   "reuses", range citations, negation lists) may admit sloppy answers. The gold unit tests use hand-made "plausible wrong" outcomes only.
5. Hard tier was built and its gold repaired AFTER seeing frontier-model failures (CFR L162-176; "real reports from the first
   references did" TaskBankHard.swift L13). Tasks and gold co-developed with the evaluated models' outputs.
6. Runs are not independent: 480 runs = 48 tasks x 10 trials; CIs assume independence (CFR L210-211). ling's 6 failures sit on 3
   tasks (warn-count 3/10, importers-of-storage 2/10, h-aliased-calls 1/10). Cluster-aware: 45 of 48 tasks all-pass is about
   94% with a Wilson 95% lower bound near 83% (calc). Repeated trials of the same fixtures also share prompt-cache prefixes, which
   likely flatters cache-dependent price (see 8.9).
7. Selection effects: finalists chosen from 499 configs on 1-trial stage-1/2 results (>=32/34), then certified; if the selection
   trial is included in the 10-trial counts there is mild winner's-curse bias (docs do not say whether it is excluded).
8. Degraded copies are experimenter-made, e.g. "digits" (94/100 caught by argon) alters numbers the judge can look up. Real
   failures were only 14 in the judged sets (ER L91). Judge recall (67-69%) is mostly a statement about synthetic corruption.
9. Judges evaluated on Gemini/gemma/qwen runs; in production, Haiku judges ling/deepseek runs and Claude judges Claude (same-vendor)
   - never measured (self-preference tested only among Gemini judges, ER L107-109).
10. Cost-floor run times under heavy load (4 processes on 10 cores, CFR L217); context 32k not a real 200k.

====================================================================================================================
## 2. PRICE AND COST NUMBERS
====================================================================================================================
Convention: LIST = list price of reported tokens (CTD decision 1, L135); CHARGED = OpenRouter's reported cost.
Stores: bank1 = eval-results/runs/bank1 (Gemini + local, Oct 24-25); cf1/cf2/cf3a/cf3b/cf5 = cost-floor (OpenRouter, Oct 25);
cf6 = Phase-1 re-run (Oct 26); gap = GAP_ANALYSIS stored-run replays.

### 2.1 Totals spent on measurement
- ER L4-5: about $30 list, all Gemini: $6.11 recording + $22.18 judging + $1.79 delegation (= $30.08, calc ok).
- CFR L4-5: $83.22 of $185 by the OpenRouter key's own count; table L82-90: stage 1 $40.07 (2,754 runs); stage 2 $20.00
  (cap reached; 6,209 runs); 3a $6.92 (6,782); 3b $7.22 (210); 4 $6.54 (165); 5 $1.30 (2,040 judgments); total $82.06 list
  (sum calc = $82.05). Key higher by $1.16 (stage-4 subagent calls not in parents' records + failed calls, L92-94).
- CFR L242-247 re-run cf6: charged $1.69 by records; key $2,614.62 -> ~$2,616.31.
- CTD L189, L214: calibration $0.0995, then $0.1124 total of $0.15 cap (Haiku 5.5, Opus 5.5, Gemini 3 Flash preview, Haiku 4.5 via OR).
- GAP L915: Phase 3 paid $0.74 on OpenRouter ($0.31 A6 reviewers + $0.35 A4 judges + ~$0.08 A7 + $0.0002 live escalation).
- Grand total across docs (calc): about 30.08 + 83.22 + 1.69 + 0.11 + 0.74 = about $116 (+ earlier eval spends not itemized).
- Note: the funnel run counts sum to 16,120 runs (2,754+6,209+6,782+210+165), plus 2,040 judgments; CFR L12 and HANDOFF L153 say
  "about 26,000 runs" in the store, and GAP L809 says cf2 alone has 9,958 runs (stage 2 spend table says 6,209). See 8.7.

### 2.2 Cost-floor finalists (CFR L111-125; store cf1-cf3a; LIST price; bank 340 + hard 140 runs each = 480)
| configuration | pass | $/run | $/success | mean s |
| inclusionai/ling-3.0-flash | 474/480 99% (97-99) | 0.00021 | 0.00022 | 19 |
| deepseek-v4-flash-0731#off | 473/480 99% (97-99) | 0.00042 | 0.00042 | 16 |
| deepseek-v4-flash-0731 (default reasoning) | 472/480 98% | 0.00053 | 0.00054 | 18 |
| inception/mercury-2.5 | 455/480 95% (92-96) | 0.00059 | 0.00062 | 16 |
| poolside/laguna-s-2.1#off | 464/480 97% | 0.00070 | 0.00073 | 19 |
| deepseek-v4-flash#off | 467/480 97% | 0.00079 | 0.00081 | 20 |
| deepseek-v4-flash | 472/480 98% | 0.00087 | 0.00088 | 22 |
| inception/mercury-3 | 471/480 98% | 0.00093 | 0.00095 | 14 |
| claude-haiku-5.5#off | 471/480 98% | 0.00107 | 0.00109 | 16 |
| claude-haiku-5.5 | 478/480 100% (98-100) | 0.00113 | 0.00114 | 17 |
| deepseek-v4.1-flash | 463/480 96% | 0.00181 | 0.00188 | 19 |
| stepfun/step-3.5-flash | 463/480 96% | 0.00195 | 0.00202 | 36 |
(pass counts calc from bank+hard columns; all match stated %.) Mercury-2.5 is NOT above the 95% floor on lower bound (92%).
Other: ling-3.0-flash with reasoning off drops 99% -> 88% (CFR L52; n not given). Reasoning-off cheaper per success for 61 of 85
models measured both ways (L50-51).
- Frontier refs, hard tier, 42 runs each, all passed (CFR L129-135, store cf3b): Sonnet 5.5 $0.0229; Kimi K3.1 Pro $0.0287; Gemini 4
  Argon $0.0349; GPT-5.6 Sol $0.0397; Opus 5.5 $0.0458. Sum x 42 = $7.22 exactly (calc) = stage 3b spend. Ratio to ling: 109x, 136x,
  166x, 189x, 218x (calc); to Haiku 5.5: 20x-40x. CFR headline says "about 100 times".
- Haiku "most reliable cheap model, at five times the price" of ling (CFR L26) = 0.00114/0.00022 = 5.2x (calc ok).

### 2.3 Delegation economics (CFR L139-153; store cf5; 3 trials/cell, 5 scenarios, "parent list price per run, plus an estimate of the subagents' calls")
mean $/run: Sonnet alone 0.0224; +ling 0.0388; +Haiku 0.0471. Argon alone 0.0921; +ling 0.0339; +Haiku 0.0441. GPT-5.6 Sol alone
0.0487; +ling 0.0580; +Haiku 0.0597. ling alone 0.0002; ling+ling 0.0013. Argon log-sweep alone $0.28 vs $0.043 with subagents (L46-47);
wall 193 s -> 64 s (L160). Quality: argon 15/15 in all three setups; Sonnet+ling survey 1/3; GPT-5.6 survey 2/3 alone, 1/3 +ling;
ling alone survey 1/3, log-sweep 1/3. -63% = (0.0921-0.0339)/0.0921 (calc ok). Sum of the 11 means x 15 = $6.69 (calc) vs stage
spend $6.54.

### 2.4 bank1 subagent runs (ER L47-54; LIST; 102 runs each; Gemini via Google key)
argon 100% 102/102, 19 s, 3.6 steps, 8,180/513 tokens, $0.0207; gemini-3.8-flash 102/102, 17 s, 7.3 steps, 19,845/1,197, $0.0195;
gemini-3.6-flash 102/102, 12 s, $0.0197; gemma-4-26b 91/102 (89%), qwen3.5-9b 90/102 (88%), gemma-4-e4b 83/102 (81%); local models
unpriced. 3 x 102 x ~0.0200 = $6.11 (calc) matches ER L5. Note argon is $0.0207/run on bank1 (Google key, list) but $0.0349 on
the hard tier via OpenRouter and ~$0.092/run on delegation scenarios (CFR L143-153) - different tasks, not a contradiction, but
price source differs (Google vs OpenRouter).

### 2.5 Judge costs
- ER L70-77 (262-run set, LIST): argon parent $3.94 (= $0.0150/judgment, calc), 3.8-flash parent $2.52, 3.8-flash grader $0.67,
  argon grader $0.86. These four sum $7.99 but ER L5 says $22.18 spent on judging all 536 (+ re-judges of ~104 missing verdicts?);
  scaling 7.99 x 536/262 = $16.3 (calc), unexplained residual about $6.
- CFR L44-49 + L70-71: Haiku 5.5 parent path about $0.0011/judgment, "1/13 of argon" (0.0150/13 = 0.00115, calc ok), 4.6 s;
  ling-3.1-flash 1/24 of argon (about $0.00063) but 63 s; stage 5 total $1.30 / 2,040 judgments = $0.00064 avg.
- GAP L781-785 A6 review per call: Haiku $0.0005 (4 s), gemini-3.8-flash $0.0039 (8 s), deepseek-0731#off $0.0001 (2 s), qwen3-coder local free.
- GAP L836-839: gemini-3.8-flash judging every Gemma run $0.0033/run vs Haiku doing the task $0.00125.

### 2.6 List vs charged (provider's charge)
- CFR L218-219 "Costs are list price. The billed amounts were close: the key's count is within 1.5% of the sum" ($83.22 vs $82.06 = 1.4%).
- BUT per-model re-run table (CFR L250-252, "charged a run, then -> now"): ling $0.000247 -> $0.000251 (charged) vs list $0.00021
  (+18% over list); deepseek-0731#off $0.000755 -> $0.001827 vs list $0.00042 (+80% over list "then", +335% "now"); Haiku
  $0.001134 -> $0.001444 vs list $0.00113 (matches "then"). Charged-per-M-tokens for deepseek $0.066 -> $0.084 (L264-265)
  versus list $0.044/$0.133 (L262-263).
- CTD L196-197: OpenRouter Haiku 4.5 calibration list = charged = $0.019040 (18,970 in, 14 out: implies $1.00/M input).
- Prompt tokens a run, then -> now (CFR L250-252): ling 13,829 -> 18,592 (+34%); deepseek 10,594 -> 20,773 (+96%); Haiku 11,199 -> 18,557 (+66%).
  Doc text says +32%, +103%, +67% on the 34 bank tasks.
- CTD calibration list prices (L192-197): Haiku 5.5 3 req $0.001893; Opus 5.5 $0.072032; gemini-3-flash-preview $0.006559; Haiku 4.5
  via OR $0.019040 (charged same). Reverse-engineering the Anthropic rows (calc, assuming 1.25x write / 0.1x read / 5x output):
  Haiku 5.5 about $0.10/M input; Opus 5.5 about $3.9/M input; i.e. Opus/Haiku about 38x. Haiku 4.5 was $1.00/M. So the list table
  prices Haiku 5.5 at roughly one tenth of Haiku 4.5. Corroborated for Haiku only by OpenRouter charging $0.001134 (= list)
  in cf-run. The same ratio shows in CFR (Opus 0.0458 vs Haiku 0.00113 = 40x). Auditor should check these against current published prices.
- CTD L215 "Next: compare the table with the Anthropic and Google consoles" - no later doc line records that this was done
  (HANDOFF L143: "comparison with the Anthropic and Google consoles still to do"). Anthropic/Gemini list prices are therefore
  estimates not reconciled to a bill.
- CFR L262-267: deepseek-0731 listed $0.044 in / $0.133 out per M, "read 2026-10-26"; earlier note of $0.44 was "a misreading".

### 2.7 Other cost figures
- CFR L104 "ling's only misses... search and summarize"; GAP L821-830 ladder replays (LIST, per run / per success): Gemma local alone 91/102
  $0; Gemma->ling->Haiku on grounded signals 94/102 $0.00001; +Gemma-own-grader 95/102; +gemini-3.8-flash reading files 96/102 $0.0033/$0.0035;
  oracle trigger 102/102 $0.00003; Haiku alone 102/102 $0.00125. Hard tier: mercury-2.5 alone 128/140 $0.00087/$0.00095; -> Haiku on
  grounded signals 129/140 $0.00109/$0.00118; oracle 139/140 $0.00104; Haiku alone 139/140 $0.00154/$0.00155.
  (Haiku per-run on same hard tier: $0.00154 here vs $0.00113 CFR L120 (bank+hard) vs $0.001134/$0.001444 cf6: three values.)
- CFR L69-71 recommended setup: subagent ling ~$0.0002; retry deepseek#off $0.0004 then Haiku $0.0011; judge Haiku ~$0.0011;
  parent Sonnet 5.5 alone or argon+cheap subagents ~$0.02-0.03/turn.
- SRD L449-450: seeding estimate "35 tasks x 1-2 Gemini configs x 2 trials = 70-140 runs at $0.01-0.07 = $1-10".
- SRD L728: rating calls count as parent cost, purpose `rating`.
- Gemini 3 Flash est. $0.007, Opus 5.5 $0.06, Haiku 5.5 $0.002 (CTD L183-184 calibrate estimates).

====================================================================================================================
## 3. DETECTOR NUMBERS
====================================================================================================================
Base rate is the key caveat: nearly all samples below are enriched (45%-65% failures) vs a real cheap-model failure rate of
about 1-2% (ling 6/480, Haiku 2/480) to 6% (cf2).

### 3.1 Judge calibration, bank1, 262 runs every judge rated; 118 failures / 144 good (ER L65-77)
| judge (path) | no verdict | agree | kappa | failures caught | good failed |
| argon parent | 0 | 86% | 0.71 | 69% (61-77) 82/118 | 0% 0/144 |
| 3.8-flash parent | 2 | 85% | 0.68 | 66% 76/116 | 0% 0/144 |
| gemma-4-26b parent | 50 | 82% | 0.63 | 62% 60/97 | 1% 1/115 |
| qwen3.5-9b parent | 10 | 80% | 0.57 | 58% 63/109 | 3% 5/143 |
| 3.8-flash grader | 0 | 78% | 0.53 | 53% 63/118 | 2% 3/144 |
| argon grader | 0 | 77% | 0.53 | 52% 61/118 | 1% 2/144 |
| gemma-4-26b grader | 3 | 77% | 0.51 | 52% 61/118 | 2% 3/141 |
| qwen3.5-9b grader | 0 | 74% | 0.47 | 60% 71/118 | 14% 20/144 |
My recomputation: argon parent kappa = 0.715, agreement (82+144)/262 = 86.3% -> consistent.
- By failure kind (ER L82-91; denominators differ per column): digits grounded 28/101, argon-parent 94/100, argon-grader 87/101,
  qwen parent 30/32; wrong-file 10/44, 44/44, 44/44, 11/14; drop-half 0/43, 33/43, 17/43, 4/17; undo-all 51/51, 51/51, 32/51, 13/13;
  undo-half 18/18, 18/18, 12/18, 4/4; vanish 12/12, 12/12, 5/12, 6/6; stray-edit 0/63, 0/63, 0/63, 0/26; real failures 2/14, 10/14, 5/14, 4/13.
- "Excluding stray edits argon parent caught 93% (262 of 282)" (ER L102): sum of kind-table numerators 94+44+33+51+18+12+10 = 262,
  denominators 282 (calc ok). This is over all items argon rated (not the 262-run set).
- Real failures (the models' own) are only 14 in this set; argon caught 10 (71%), grounded checks 2 (14%). n tiny.
- Parent beats grader by about 15 points for every Gemini judge (ER L95); no self-preference: argon parent 74% on own vs 76% others (ER L107-109);
  local judge self-pref samples only 11-28 failures.
- Missing verdicts (ER L110-119): first-pass 110 (gemma-4-26b) and most of Gemini's 104; after fix gemma still 56, Gemini 5; grader
  thinking limit 40 -> 1; Gemma text-call 4 -> 0.
### 3.2 Grounded checks (ER L123-134, 346 failures / 190 good)
- run-end checks 14% (11-18) 48/346; + re-run check 35% (30-40) 121/346; + argon parent 76% 263/346; + 3.8-flash parent 74% 257/346;
  each 1/190 good run falsely failed. Re-run catches all 81 undo/vanish copies. Combined with weak judge: checks + qwen grader 71% vs 63% grader alone.
- Internal check (calc): by-kind table numerators for grounded sum 28+10+0+51+18+12+0+2 = 121 (matches "checks + re-run"), implying run-end
  checks alone = 28+10+2 = 40, but ER L125 says 48/346. 8 unexplained.
### 3.3 Cheapest judge, cost-floor stage 5 (CFR L44-49; store cf5; "the same 204 stored runs")
- Haiku 5.5 parent path: kappa 0.67 (vs argon 0.71), catches 67% (argon 69%), wrongly fails 2% of good (argon 0%), 4.6 s, 1/13 argon cost.
  ling-3.1-flash: kappa 0.69, no false alarms, 1/24 cost, 63 s. Failure/good counts in the 204 are not given.
- Sample-size note: ER L65 base set is 262, plan said 262 "a count I couldn't reproduce" -> 236 -> 204 after infra removal (CFR L195-196).
  Argon's quoted numbers (kappa 0.71, 69%, 0%) are IDENTICAL to ER's 262-run figures, yet said to be "on the same 204 stored runs".
  Either re-computed with identical result (unlikely) or copied from ER. Flag.
- Illustrative precision at realistic base rates (calc, Haiku recall 67%, false-alarm 2%): failure rate 1% -> precision about 25%;
  2% -> about 41%; 5% -> 64%. At the sample's 45% base rate -> 97%.
### 3.4 P1/P2 early numbers (SRD) - tiny samples, qwen3.5-9b as subagent AND parent AND grader
- P1 live (L523-534): 5 delegations; parent rated every run 3/3; in 3 of 4 ratings that claimed a check it had made none.
- P2 first (L580-604): bank 16/16; parent path read files before rating in 10 of 14; claimed checks it didn't make 4 of 16;
  degrade: 13 degraded copies failed gold; grader caught 54%, parent 44%, 0 false alarms (3 degraded didn't count); with check available:
  parent 40%, grader 46% (13 failures each; "differences are noise"); parent ran check twice, mis-scored a found failure as 2/3.
- Re-run grounded + tighter rubric (L655-671; 12 known failures, about 15 good, one 9B model): parent 44/40% -> 82%, parent false alarms 0 -> 7% (1 run),
  grader 46%, checks with re-run 15% -> 31%; combined label put 11 of 12 at <=1/3 (missed run-script). "Caveats: ... size isn't settled" (L670-671).
### 3.5 Run signals / triggers (GAP L809-817; computed on stored runs vs gold; precision, recall)
| trigger | cf2 (9,958 runs, 628 fail) | cf3a hard (2,226; 70) | bank1 (612; 42) |
| re-run check failed | 100%, 3% | 100%, 9% | 100%, 7% |
| stopped early | 96%, 13% | 70%, 20% | 67%, 10% |
| last check failed after changes | 100%, 1% | -, 0% | 67%, 5% |
| any grounded signal | 31%, 16% | 10%, 23% | 54%, 17% |
| judge reading files (parent path): argon / 3.8-flash / Gemma | | | 100%,71%; 100%,57%; 67%,20% |
| judge w/o tools (grader): argon / Gemma | | | 71%,36%; 57%,29% |
| A6 reviewer on 32 sampled code runs (8 fail): Haiku / deepseek / qwen3-coder | | | 80%,100%; 100%,75%; 100%,63% |
(The A6 row's "precision, recall" order is my reading: matches 8/8, 6/8, 5/8 in GAP L782-785.) Row labelled "bank1 612 runs of 6 models":
bank1 elsewhere is 1,071 runs / 102 per model (ER L4) - 612 = real, non-infra, non-copy runs (FTR R6-11).
### 3.6 A6 cross-vendor review (GAP L777-791; bank1; 80 runs = 8 real failures + 48 degraded copies + 24 good; paid $0.31)
| reviewer | real fail | stray | undo-all | undo-half | file gone | all bad | false alarms /24 | $ / s |
| Haiku 5.5 (OR) | 8/8 | 12/12 | 12/12 | 12/12 | 12/12 | 56/56 | 2 | 0.0005, 4 |
| gemini-3.8-flash | 6/8 | 12/12 | 12/12 | 12/12 | 12/12 | 54/56 | 0 | 0.0039, 8 |
| deepseek-0731#off | 6/8 | 11/12 | 12/12 | 11/12 | 11/11 | 51/55 | 0 | 0.0001, 2 |
| qwen3-coder-30b local | 5/8 | 7/12 | 12/12 | 8/12 | 12/12 | 44/56 | 0 | free, 3 |
Copies are 12 per type from a few distinct change runs (not independent). Reviewers saw a diff only (no tools).
### 3.7 Retry ladder / cascade (GAP L819-842, L872-894)
- Offline replay (LIST cost, paired runs, fresh stronger-model run not hand-over): see 2.7. Perfect trigger = oracle. Grounded signals
  recover "a quarter to a third" of the oracle gain (L833-835). Ling ladders "say little: 9 of 479 bank runs fail" (L841).
- Mercury-2.5 hard-tier judging (12 failures in 140; Haiku & deepseek both paths; qwen local 88 judged; paid $0.35), L878-886:
  grounded signals 1/12 caught, precision 7%, 129/140, $0.00109; Haiku grading (no tools) <=1: 7/12, precision 24%, 134/140, $0.00171;
  deepseek reading files <=1: 4 of 9 judged, 67%, 132/140, $0.00140; qwen3-coder grading: 3 of 11 judged, 21%, 131/140, $0.00115;
  perfect 12/12, 139/140, $0.00104; Haiku alone 139/140 $0.00154. deepseek often gave no verdict as grader (82 of 140).
  Conclusion (L888-893): no judge makes the cascade cheaper than running the next model; escalation stays advisory.
- Retry trigger as shipped: FTR R6-10 - replay over 1,439 stored cf6 runs: 47 triggers, 2 real failures (4% precision); after
  fix 4 triggers, 1 real failure. (The fix was tuned on the same set it was replayed on; n=1 real failure.)

====================================================================================================================
## 4. DECISIONS
====================================================================================================================
### SRD D1-D8 (2026-10-24, "the user", L683-698)
- D1 Waiting vs dollars: value-of-an-hour theta, routing only, never recorded as cost; Settings; starts $5/h placeholder.
- D2 Who judges: parent + grounded checks on every run, plus a grader model for importance:high runs; every judgment kept for fine-tuning; user ratings override.
  (Made before the eval; ER later found grader path about 15 pts weaker than parent path, kappa 0.53 vs 0.71; D2 not amended. See 8.)
- D3 Automatic retries: yes; hard failures retried once on another model within budget.
- D4 Exploration: Thompson on up to 10% of low/normal runs, paid exploration capped $0.50/day; shadow runs on free models with guardrails.
- D5 Embeddings: in-app on Mac GPU (swift-embeddings; Nomic v1.5 and CodeRankEmbed), not through LM Studio. Rationale (L702-716): MLX can't
  build Metal shaders with swift build; about 1.1 GB download needing approval.
- D6 Pool: this Mac's LM Studio models, LAN server (bang), and Gemini (Gemini 3 Flash on the user's key). Claude and OpenRouter out for now.
- D7 Loop advice to delegate broad reading: built and on; eval still measures it.
- D8 Scope: subagents only; the user's thumbs on main runs go to same index for later.
### Cost-tracking decisions (CTD L133-142, 2026-10-15)
1. Compare models on LIST price of reported tokens; actual charge recorded beside it only.
2. Local models: time, tokens, hardware only; no hourly rate.
3. Delegation is the parent's cost (writing the task and reading the report are its requests); sizes recorded on the subagent run record.
4. Dedicated API keys per provider acceptable; OpenRouter per-request check on by default.
5. Both units: main run (one user message; later: each send is its own run) and the session = sum of runs + entries outside any run.
CTD "accurate" criteria L9-23: complete, comparable (list price), exactly priced per component, attributable (each request to exactly one run;
"nothing shared and nothing counted twice"), explained/checkable (raw usage, rates, request id).
### Cost-floor plan decisions (CFP L123-132, 2026-10-25): floor 95% (also 80/90); no free models; ~5 frontier refs x 3 trials hard tier;
only providers that don't train on prompts; screen every paid model; thinking models get two configs (off/default); delegation parents = argon, Claude, GPT-5.x,
cheapest model clearing 95%.
### Later decisions referenced (GAP, not on list): A2 defaults to ling-3.0-flash subagents / Haiku grader (FTR L36-37 "by design, A2"); decision 4
keeps forced delegation on for local sessions (GAP L912-913).

====================================================================================================================
## 5. THE P3 ROUTER DESIGN
====================================================================================================================
Naming: in SRD's phase table (L472-480) "P3" = similarity + outcome index (embedder, index, neighbors, `kurtkode route` dry run,
`router eval` with leave-one-out, both baselines, Nomic vs CodeRankEmbed); P4 = advisory router (pool, filters, predictor, bar,
cascade rule); P5 = acting router + retries; P6 = seeding; P7 = fitted IRT/behavioral similarity. COST_ARCHITECTURE.md L65 and
CFR L77 call the whole thing "the router (P3)".
- What it does (SRD L138-290): for each filtered candidate "arm" (endpoint, model, reasoning effort, prompt style, agent hash, quantization),
  predict p-hat of success on the new task: (1) top-k (k=20) past judged runs of that arm by distance d = w_text(1-cos) + w_kind[kinds differ]
  + w_write[writes differ] + w_size|log size ratio|, weight exp(-d/h) * r_i (judgment reliability); (2) prior = arm's success rate for the
  kind, backing off to overall then tier seed table; (3) cross-model difficulty shift logit mu_m(x) = logit mu_m + gamma(logit s(x) - logit s) (one-parameter IRT);
  (4) Beta posterior alpha = alpha0*mu + sum w y, beta = alpha0*(1-mu) + sum w(1-y), n_eff = sum w; (5) cost/time from neighbors' median tokens x
  verbosity x price list; time from measured prompt/output speeds + load time.
- Choosing: success bar tau by mode x importance (Thrifty 0.6/0.7/0.8; Balanced 0.7/0.8/0.9; Best 0.8/0.9/0.95), then cheapest expected cost,
  cost = dollars + theta*hours (theta $5/h). None clears: highest p-hat, warn if < tau-0.2. Cheap-first cascade when
  c_c + c_judge + [(1-p_c)*recall + p_c*false_alarm]*c_s < c_s and shipped quality >= tau. Thompson exploration <=10% of low/normal runs,
  paid exploration $0.50/day. Precedence: agent `model:` > user-named > router > Settings subagent model > session model. Advisory mode first.
- Data needed: outcome index (outcomes.jsonl: config, card, embedding, label y, reliability r, cost, time) rebuilt from sessions; labels from
  user > test > grader > parent judgments (verdict/3, forced 0 by hard failure), reliability from calibration; cost/time entries;
  bank tasks labelled source:eval with shrinking weight; shadow runs; kNN useful "from about 5 judged neighbors per configuration and kind"
  (L463-466); fitted models need "a few hundred" runs. Judge reliability (recall, false alarm) per verification type.
- Acceptance test (L239-243, L47, L730-731): leave-one-out Brier score and log loss of p-hat vs judged outcomes, against two baselines
  ("model average only" and "model x kind"); `router eval` must show the router beats "always the same model" and the model's average;
  if similarity doesn't beat model x kind the router uses model x kind and says so; every layer that fails its baseline is switched off.
  Text-embedding comparison Nomic vs CodeRankEmbed on the same data.
- Why not built (docs): "There is no history, so first predictions are priors" (SRD L434; L89 "sessions hold no subagent runs"); CFR L77-78
  "The router (P3) should take these as priors and learn from real outcomes"; COST_ARCHITECTURE L14-17 "learned router is designed but not built, and
  real-session outcome data is still thin". Implicit: the cost-floor result (one model ling at $0.0002 clears 95% on everything measured)
  makes routing among models look low-value on this data; the shipped substitute is a static pool + tier ladder + advisory escalation (FTR R6/R7;
  GAP A2/A4). SRD does not state a reason explicitly; AUDIT_PROMPT L55 poses "would kNN beat always-ling on stored runs?" as open.
- Sanity points: kNN needs per-arm per-kind neighbors; with ling at 99% pass on all kinds the bank has almost no failures to learn from
  (labels y almost all 1) so Brier skill vs "always ling" is likely nil on bank data.

====================================================================================================================
## 6. RESEARCH SURVEY (SRD L35-77)
====================================================================================================================
(Years from arXiv ids / text; I could not fetch any link.)
1. kNN routers: Li 2025, arXiv 2505.12601 - well-tuned kNN over prompt embeddings matches/beats learned routers (locality). Took: kNN + Bayesian prior.
   ContextualRouter - cited as "retrieval-based routing works from about 1% of the history" but the link is an ACL Anthology AUTHOR page
   (aclanthology.org/people/christophe-bouvard/), not a paper. Weak citation.
2. LLMRouterBench 2026 (2601.07206); routing and cascading survey (2603.04445, Mar 2026); RouterBench (2403.12031, Mar 2024) - most routers do about the
   same, several don't beat simple baselines; large oracle gap; models complementary. Took: every component must beat "always same model" / "model's average".
3. Agent-as-a-Router 2026 (2606.22902) - feedback loop for coding agents; task-level stats help. Online multi-LLM selection (2506.17670, Jun 2025) and
   neural bandits (2508.09958, Aug 2025). Took: verified outcomes feed next decision; budgeted exploration.
4. Cascades: FrugalGPT-style (no link), C3PO (2511.07396, Nov 2025), agreement-based cascading (2407.02348, Jul 2024), "is escalation worth it?" (2605.06350,
   May 2026), signed rescue routing (2609.07786, Sep 2026). Took: ladder at most two deep, escalation accounts for judge reliability (two levels capture most gain;
   escalation can hurt a good run; detector quality decides).
5. Judges: self-preference (2410.21819, Oct 2024), BabelJudge (2606.22329, Jun 2026) - miss hallucinations/favor length; self-evaluation bias (2607.25152, Jul 2026).
   Took: grounded checks over opinions, record how a judgment was checked, flag same-model parent/child, measure judge reliability vs gold.
6. Multi-agent: Anthropic multi-agent research system (about 15x tokens; token use explains most variance; coupled coding fits worse); Cognition's
   argument via a morphllm.com blog summary (secondary source). Took: delegate read-only separable work, count overhead.
7. EmbedLLM (ICLR 2025) - IRT-style abilities/difficulties for the later fitted model (L216).
8. Embedding tooling: swift-embeddings (MIT), Nomic Embed Text v1.5, CodeRankEmbed (HF), MLX Swift rejected (L702-716).
Survey is dated 2026-10-24; newest cited paper is Sep 2026 so it is current to about 1 month. Observations (mine, from general knowledge, unverified here):
no mention of RouteLLM (2024), Hybrid LLM, AutoMix, FrugalGPT paper itself, Mixture-of-Agents, or any coding-agent cost studies (e.g. SWE-bench-style
cost/performance of cascades, aider-style leaderboards); no real-repo benchmark cited for the task bank; the two multi-agent sources are a company blog
and a third-party summary. Most 2026 arXiv ids were not checkable offline.

====================================================================================================================
## 7. DEFECTS FROM ROUNDS 6 AND 7 (FTR L826-925) concerning cost/pricing/judging/review/escalation/delegation/pool
====================================================================================================================
Round 6 (session 15, Phase 2; 573 -> 588 tests, 11 known issues), Round 7 (session 16, Phase 3; 628 -> 645).
### Round 6
- R6-1 (A) LAN server by unrecognizable name counted as remote -> subagents/retries/grading went to OpenRouter/Anthropic. FIXED (Endpoint.isCloudAPI).
- R6-2 (A) failed run's edits undone after releasing writer slot; partial restore reported as nothing undone. FIXED (retry decided + undo under slots).
- R6-3 (B) retries ignored user's subagent model/agent `model:`; could go down a tier. FIXED (only pool-chosen runs retried; unknown tier not).
- R6-4 (B) pool.json slip silently restored shipped pool and a toggle overwrote user's file. FIXED (lenient read, empty pool + reason).
- R6-5 (B) Ollama trained context taken for served num_ctx. FIXED.
- R6-6 (B/C) retried background run's report named failed run; and a run that changed no files was NEVER retried (empty undo store threw). FIXED.
- R6-7 (C) profile reasoning setting hid a rung, retry skipped step. FIXED.
- R6-8 (C) mistyped --reasoning sent to server; Gemini 2.5 Pro offered "none". FIXED.
- R6-9 (B) important task without tier ran on Haiku and default grader was Haiku too, so important tasks were NEVER graded. FIXED (grader = pool's first judge,
  else reviewer, not the run's model).
- R6-10 (A) retry fired mostly on runs that had passed (47 triggers over 1,439 runs, 2 real failures); false "made-up citations" (bare file names, dotted names), "no report"
  on cut-off runs that did the work. FIXED; replay after: 4 triggers, 1 real failure.
- R6-11 (A) `cost report --eval` counted degraded copies and infra failures as runs: bank1 showed 1,071 runs and $11 for 612 real runs; cf1 pass rate 81% vs 93%. FIXED.
- R6-12 (A) run with a charged and an uncharged request reported only the charge (undercount). FIXED (`RunTotals.spent`).
- R6-13 (B) after retry/Continue a run's "request" was kurtkode's note; thumbs and the next retry's judgment landed on the wrong run; replies after queued messages got no thumbs.
  FIXED.
- R6-14 (B) daily limit on paid models stopped free local sessions. FIXED.
- R6-15 (C) report keys/rows split or merged (reasoning key order, "all" project name, local tokens skewing cache share, JSON $0 for unpriced groups, same-name projects). FIXED.
- R6-16/17/18 (B) Tools "On" ignored when OpenRouter lists none; listed contexts raised sessions to 200k; eval re-run behaved differently under same label (reasoning not
  inherited, provider pins added). FIXED.
- R6-19 (C) Spending window "Today" = last 24h; cache notice vs fallback model; /good toggled off; rewind labeled every later run 0; CLI model listing 300 s. FIXED.
- NOTED, NOT FIXED (C): retried background run's "Started..." names first run; parallel sessions can jointly pass a daily limit (each reads the day's spending at start); an unreadable
  store counts as nothing spent today; built-in /good and /bad hide same-name custom commands.
- Defaults change (by design, A2): unset subagent/grader settings on hosted sessions now send subagent tasks to ling-3.0-flash on OpenRouter and important grading to Haiku.
### Round 7
- R7-4 (A) review/hand-over diffs ignored files withheld from remote models (.env/*.pem). FIXED (UnifiedDiff.withholding).
- R7-15 (A) local session's reviewer could be any unrecognized server. FIXED (!isThirdParty).
- R7-16 (A) accepting an escalation dropped pool entry's provider pins (data_collection: deny) and reasoning. FIXED (offer carries them; session-only, not saved).
- R7-1,2,3,6,7,8,9,10 (A/B) snapshot/restore/rewind data-loss bugs (LFS pointer, CRLF, skip lists, case rename, link write, hunk revert by index...). FIXED (not cost-related).
- R7-5 (A) changes by user/other session during a run count as the run's own and a rewind reverts them. NOT FIXED (documented).
- R7-17 (B) unknown hosted server counted as tier "local" -> offered a cheap model (downgrade). FIXED (no offer).
- R7-18 (B) reviewer picked vs session's current model, so after switch could be reviewed by own vendor. FIXED (different vendor than every model that made the change).
- R7-19 (B) server errors/timeouts earned escalation offers with reason "AgentCore.StopReason.failed". FIXED.
- R7-20 (B) hand-over sent latest request with an older run's diff; late review could resurface a card; offers priced from the current model. FIXED.
- R7-21 (B) CLI reviewed turns that changed nothing; re-offered last run after a failed turn. FIXED.
- R7-22 (B) stale card or /escalate could switch session DOWN a tier. FIXED.
- R7-23 (B) `--trigger-sim` "stopped early" counted cost limits/stops/denials unlike shipped trigger; tables regenerated. FIXED.
- R7-24 (B) reviewers' precision in trigger tables came from the enriched review sample (8 failures in 32), not the population. FIXED = labeled as such in GAP.
- R7-25 (C) review costs missing from CLI session costs; escalation review ran after a cost limit. FIXED (a user-requested /review still isn't limit-checked).
- R7-26 (C) reviewer's judgment claimed it read files (it saw a diff); session verdict landed on latest run. FIXED (`spot-checked`).
- R7-27 (C) `/review -m typo:model` fell back to default endpoint. FIXED.
- R7-28 (C) passed-by offers stayed "offered". FIXED (`ignored`).
- R7-30 (C) purpose breakdowns omitted review costs. FIXED.
- R7-31 (B) new built-ins /review /diff /rewind /escalate hid user's commands. FIXED (four yield).
- R7-32 (C) older builds skip new record kinds so their spending reads lower. NOTED.
- R7-33 (B) kurtkode-written task call broke Claude thinking requests; forced choice to OpenRouter Claude with reasoning refused. FIXED (note only).
- R7-34 (B) queued message followed by a task call written from old request. FIXED.
- R7-35 (C) forced choice lost when turn dropped. FIXED. R7-36 (C) note lost on a written call; written call counts as step and task call in run stats. NOTED stats.
- R7-38 (C->A in effect) hand-over message went through skill router as new request (a router question on every escalation, seen live). FIXED.
- 21B.4/21B.5 (L98-99): live accept qwen3-coder -> ling ($0.0002) then Haiku declined; "on a Haiku parent the threshold never tripped" (A7).

====================================================================================================================
## 8. RED FLAGS
====================================================================================================================
Severity: H = could change a headline conclusion; M = weakens evidence; L = tidiness.

8.1 (H) Detector evidence is on enriched / synthetic samples, but conclusions are drawn for production.
 - ER L65: 118 failures vs 144 good (45%); ER L125-127: 346 vs 190 (65%); GAP L817: "8 failures: an enriched sample, so precision reads high"; FTR R7-24 admits it.
 - Real model failure rates of the recommended models are about 1-2% (CFR L110-112: ling 6/480, Haiku 2/480). With Haiku's 2% false alarm and 67% recall, precision at 1-2% base rate
   is about 25-41% (my calc). CFR L44-49 presents "catches 67% of failures, wrongly fails 2% of good runs" with no base-rate caveat and recommends Haiku as the judge (L70).
 - Real failures judged: 14 (ER L91); argon caught 10; grounded 2. Everything else is experimenter-made corruption.
8.2 (H) Haiku-judge numbers vs argon "on the same 204 runs" look copied from the 262-run set.
 - CFR L44-45 "Kappa 0.67 against argon's 0.71, on the same 204 stored runs" vs ER L71 "argon (parent) ... 86% ... 0.71 ... 69% ... 0%" computed on 262 runs (L65). Plan itself said 262 "a count I couldn't
   reproduce" (CFR L195-196). Identical argon figures on a different denominator is implausible; the difference 0.67 vs 0.71 is also within noise at this n.
8.3 (H) "Costs are list price. The billed amounts were close" (CFR L218-219) vs the per-model charge data (CFR L250-252, L261-268): deepseek-0731#off charged $0.000755 "then" vs list $0.00042 (+80%),
 ling charged $0.000247 vs $0.00021 (+18%), Haiku equal. The 1.4% agreement is for the whole $83 total, dominated by stage 1/2 pricier models, not for the cheap finalists. The headline
 rankings "deepseek $0.00042 per success" (CFR L24-25, L69, SRD L428-432) therefore used list prices that under-stated what OpenRouter charged by a factor of 1.8 even before the re-run; after
 the re-run deepseek is $0.001827 > Haiku $0.001444 (CFR L251-252, L266-267). The Recommended setup table (L68-71) and SRD "Measured priors" (L428-432) still carry the stale figures.
 Inconsistent with CTD decision 1 (compare on list) vs CFR L270 "compare charges, not listings, before relying on a cheap model's price".
8.4 (H) Delegation saving rests on one scenario, forced delegation, and an estimated cost.
 - CFR L33-47: "-63%, with no loss of quality (15/15)" for argon+ling. Of the 5 scenario mean ($0.0921), the log-sweep alone is $0.28 -> $0.043 (L46-47): 0.237 of the 0.058x5 = 0.29 total
   per-scenario saving (about 80%+) comes from one scenario (3 trials). Subagent cost is "an estimate" (L139, L221); the "$1.16 higher on the key" is attributed to uncounted subagent calls (L92-94)
   although the delegation table claims to add an estimate - unclear whether $6.54 includes it.
 - Delegation was ordered in the prompt ("an order... isn't a policy", L158-159); ER L142-147 shows no model delegated on its own (3/36); GAP L902,906 shows A7's threshold never trips for Haiku (0/15) and "A7
   changes nothing for hosted sessions as set". So the 63% saving cannot be realized by the shipped product on hosted sessions. CFR L71 still recommends "argon with cheap subagents".
 - Sonnet/GPT-5.6 got worse with delegation (survey 3/3 -> 1/3; 2/3 -> 1/3): quality-neutral claim holds for argon only (n=15).
8.5 (H) Selection/ceiling: the "95% floor" is certified on a saturated bank. ER L11-12, CFR L31-32 concede it. The same docs then use the result as "priors" for the router (CFR L77) and to set defaults
 for all hosted users (FTR L36-37: ling is now the default subagent model). "What's not established: whether ling's 99% holds on real work" (CFR L73-75) is a decisive caveat sitting after the recommendation table.
 Run-level CI (97-99%) vs task-level clustering (6 failures on 3 tasks; Wilson lower bound for tasks all-pass about 83% (calc)).
8.6 (M) One-directional gold repair. 12+ gold defects across 48 tasks (3 in ER L170-176; 8 rows/9 tasks in CFR L164-176; "docstring" bug EP L19; review-clean fixed twice), all found as false negatives
 and loosened. No quantified check for false positives. Pass rates (99%) could include sloppy passes. Also "Regold over a whole large store missed changes ... cause isn't found yet" (CFR L203-207): stored scores
 for cf2 (9,961 runs) may be stale despite re-scoring "per task".
 Also "Eight checks were wrong" (CFR L59) vs 9 tasks in the table (insufficient-status and find-reserve-def share a row).
8.7 (M) Run counts don't reconcile. CFR L12: "about 26,000 runs" (HANDOFF L153 same). Stage table runs sum to 16,120 (+2,040 judgments). GAP L809: cf2 has 9,958 runs / FTR L9 says 9,961, but stage 2 = 6,209 runs.
 Stage 1 2,754 runs vs 394 runnable configs x 6 = 2,364 (infra runs counted?). ER L4 "1,071 runs" vs 612 real (FTR R6-11) vs 102x6 = 612; ER also removed 168 infra runs (L177) -> 1,071-168 = 903
 (so the "1,071" includes ~291 copies). Different docs use different denominators for "bank1".
8.8 (M) Double-count / attribution risks in cost data.
 - FTR R6-11: the cost report counted degraded copies (carrying their original's record) as runs: bank1 "$11 for 612 real runs" vs ER L5 recording cost $6.11. Fixed in tooling, but ER's judging $22.18 vs
   $7.99 shown in tables (2.5) is unexplained; possible re-billing of re-judges (`--rejudge-missing`).
 - CTD L50-52, decision 3: delegation charged to parent AND subagent run has own cost; totals "cover its own entries only". A naive sum of a parent's `listPrice` and its children double counts task text/report tokens only if
   those are also priced in the child; docs say not. Stage 4 "parent list price per run, plus an estimate" (CFR L139) mixes recorded and estimated; the -63% uses it.
 - R6-12: charged+uncharged requests undercounted before fix (cost data prior to fix).
 - CFR L205-206 (judge costs): the "$/judgment" for Haiku ($0.0011) equals Haiku's task $/success ($0.00114) - fine, but note equality is coincidental.
8.9 (M) Cache and provider-routing dependence of cheap prices. Haiku 5.5 $0.00113 for about 11k prompt tokens implies about $0.10/M effective, i.e. heavy cache reads; repeated trials share prefixes (10 trials x same
 fixtures, parallel). Real sessions with unique projects will cache less. OpenRouter provider routing moved deepseek's cost 2.4x with no list change (CFR L261-268); ling's providers/uptime under `data_collection: deny`
 are never listed. 105/499 configs were infra-unrunnable (CFR L54-57) incl. "no provider that doesn't train" (100 runs).
8.10 (M) Haiku 5.5 vs Opus 5.5 price ratio of about 38x in the calibration table (CTD L192-195) vs Haiku 4.5 at $1/M (L197): check PriceList for Claude 5.5 rates; no console reconciliation was ever recorded (CTD L215; HANDOFF L143).
 Gemini "3 Flash" preview calibrated at $0.0066 (CTD L196) but ER L39 "gemini-3-flash doesn't exist on this key" and SRD D6 still names it (pool entry for a retired/non-existent model).
8.11 (M) Contradiction D2 vs ER: D2 (SRD L688-689, written 10-24) sets a no-tools grader for importance:high; ER L95-96, L190-191 (10-25) finds the grader path weaker by about 15 points (kappa 0.51-0.53 vs 0.63-0.71) and
 recommends the parent path + grounded checks. SRD L325, L510-512, L688 not amended; R6-9 shows the grader never fired in practice. GAP L893 later: "none of the six measured is" cheap and precise enough to automate escalation.
8.12 (M) Stray edits: ER L98-101, L183-184 "nothing catches stray edits (0 of 63)... needs a scope" vs GAP L782-785 where every reviewer with the diff catches stray edits (12/12, 12/12, 11/12, 7/12). The 0/63 is an artifact of how the copy was
 built (no transcript trace); the "next step #1" (task-card scope) is superseded by A6, but ER and SRD L678 still present it as the open gap.
8.13 (M) Delegation findings changed over time: ER L25-27 "No model delegates on its own (3 of 36)... the decision has to come from kurtkode"; CFR L35-47 forced delegation measured via a prompt order; GAP: kurtkode-initiated delegation (A7)
 never trips for hosted models (0/15) and doesn't help locally (0/6 either way, double time). D7 (SRD L697 "Loop advice built and on") was measured: qwen3.5-9b "ignored it when it fired" (SRD L628).
8.14 (M) bank1 judge table mixes samples: columns in the by-kind table have different denominators (argon digits 94/100, qwen parent 30/32; qwen judged a balanced sample of 300, ER L42). Comparisons of judges across columns are not like-for-like; ER L93-100 reads
 them as comparable. Also "Combined with argon's parent rating they catch 76% (263/346)" vs argon alone 262: the "+1" and "the 262-run" coincidence invites misreading.
8.15 (M) Internal count mismatch in grounded checks: ER L125 "checks at the run's end 48/346" vs by-kind column (28+10+2 = 40 without the re-run). 8 unexplained.
8.16 (M) Small n quoted as results: P2 "82% vs 44%" from 12 known failures and about 15 good, one 9B model as subagent and judge (SRD L655-671; they do caveat); A4 mercury table 12 failures, deepseek 4 of 9 judged, qwen 3 of 11 (GAP L878-886);
 R6-10 fix verified on 1 remaining real failure; stage 4: 3 trials per cell, 15 runs; frontier refs 42 runs each, "all passed" (lower bound about 91% by Wilson, calc) while ling gets certified at 480 runs (apples to oranges: references only used for cost ratios).
8.17 (M) Haiku "the most reliable cheap model" (CFR L25-26): 478/480 vs ling 474/480 vs deepseek 473 - overlapping intervals; and Haiku "wrongly fails 1 of 480 on format strictness" (CFR L178-179), gold strictness not a model property.
8.18 (L) Stale/inconsistent Haiku per-run costs: $0.00113 (CFR L120), $0.00154 (GAP L830), $0.001134 -> $0.001444 (CFR L252). Different tasks/stores/charged-vs-list; no table reconciles them.
8.19 (L) Cost-floor plan assumed 371/355/200 models; actual funnel 281 models/499 configs (CFR L97-98) - plan numbers superseded, no issue except "A fifth of the field couldn't run" (105/499).
8.20 (L) SRD status line L3 says P3 "unbuilt" but D6's pool (OpenRouter excluded) was overridden by A2 defaults (FTR L36-37); SRD L695-696 D6 not amended even though CFR L77-78 says the pool "should now include" OpenRouter models.
8.21 (L) Time numbers (19 s, 16 s) were "measured under heavy load" (CFR L217) yet appear in the finalist table and the Pareto choice; judge speed comparisons (4.6 s vs 63 s) similarly uncontrolled.
8.22 (L) Survey citation for ContextualRouter is an author page (SRD L40-41); Cognition claim cited to a third-party blog (SRD L75-76).

Files written: /private/tmp/claude-1001/-Users-kurt-git-sugar-kurtagent/31759f81-c617-4d82-b869-6dea14aad382/scratchpad/claims_eval_docs.md
