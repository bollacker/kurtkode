# Audit extraction: GAP_ANALYSIS.md (925 lines) and COST_ARCHITECTURE.md (134 lines)

Notation: "GA Lnnn" = GAP_ANALYSIS.md line; "CA Lnnn" = COST_ARCHITECTURE.md line. P/F = paid or free (replay / local / mock).
"Store" = the eval-results store or document the claim cites. Nothing here was verified against code or stores; this is an extraction from the two documents only.

Store key (from GA L632-637, L809, CA L78-82): cf1 = 499-configuration screen (3,107 runs); cf2 = "shortlist on the bank" per CA L80 but "9,958 runs of ~500 configurations" per GA L809; cf3a/cf3b = hard tier, cheap/frontier (cf3a 2,226 runs); cf5 = judge calibration; cf6 = finalists re-run after Phase 1 (1,439 runs: ling, deepseek-off, Haiku); bank1 = 6 models, 612 runs, with judgments and degraded copies; p1-before/after = Gemma 96 runs each.

====================================================================
## 1. CLAIMS
====================================================================

### 1a. Theme A / framing (pre-Phase text)

| # | Claim | GA line | Evidence cited | n | P/F |
|---|---|---|---|---|---|
| 1 | "the eval harness has screened 499 OpenRouter configurations and found a 95%-floor model at 1/100 of frontier price" | L16-18 | none in this doc (cost-floor study, COST_FLOOR_RESULTS.md); later: cf1 2,897/3,107 passed (L634) | 3,107 runs in cf1 (about 6 per configuration) | paid ($83.22 per CA L85) |
| 2 | Models "almost never" delegate: "3 of 36 runs where it would have helped" | L20-21; L57 "3 delegations in 36 helpful cases, 0 in 24 unhelpful" | "the eval" (no store named) | 36 helpful, 24 unhelpful | paid (presumed) |
| 3 | Reasoning off "was cheaper per success for 61 of 85 models, but cut ling-3.0-flash 99%->88%: must be per model" | L51 | none named (cost-floor study) | 85 models | paid |
| 4 | Haiku 5.5 judge "kappa 0.67" makes cross-vendor review "cheap and credible" | L156 | none named (judge calibration, cf5 per CA L81) | not stated | paid |
| 5 | A7 premise: "A7 ... Measured by the existing survey/log-sweep scenarios" (plan only) | L159 | plan | - | - |
| 6 | Part 3 Phase 2 measure: "retry ladder's rescue rate", "cost report over ... a week of real sessions" | L279 | plan | - | - |
| 7 | Part 3 Phase 3 measure: "Cheap-first vs frontier-alone on bank, hard tier and delegation scenarios: cost per success, wall time, escalation precision" | L280 | plan (compare with L819-830, L898-904 below) | - | - |
| 8 | Phase 0 plan measure: "Bank + hard tier on ling-3.0-flash and a local model: fewer steps per task, no regressions" | L277 | plan (never reported; see Gaps) | - | - |

### 1b. Phase 0 / Phase 1 (cost-relevant)

| # | Claim | GA line | Evidence | n | P/F |
|---|---|---|---|---|---|
| 9 | Tool output cap is ~8% of context (16 KB floor, 200 KB ceiling) [plan said "say 3%", L177] | L322 | design; unit tests | - | - |
| 10 | Saved-output note "reached Gemma 3 times and was used 0 times"; after `hiddenErrorsNote` fix "4 of 4 runs right" (caveat: fixture's script contains failure text; Gemma read it in some runs) | L353 | live Gemma 4 26B -p runs | 4 | free |
| 11 | Skill router picked `fix-build-and-ci` for "run this and tell me what failed" "in 2 of 2 runs" | L357 | live Gemma | 2 | free |
| 12 | Parallel reads not exercised: "at 32k only two reads ever run together" | L354 | derived from 3 x 16 KB > ~38 KB turn budget | 0 live | free |
| 13 | warn-count eval scenario: "1 of 6 trials passed"; all 6 used count mode; 5 failures counted "warning" (440) not "warning:" (408) | L379-381 | eval-results/phase1-b4-warn-count-gemma4-26b{,-b}.json | 6 | free |
| 14 | In manual Gemma runs "warning" (419) vs "warning:" (389), answered 389 | L378-379 | live | few, unstated | free |
| 15 | `openai/gpt-oss-120b`: with both tools offered used edit_file (3 calls, $0.0013, 11 requests); told to use apply_patch: one patch, $0.0011, 9 requests; "Total spent: $0.0024" | L405-412 | live OpenRouter | 2 runs | paid |
| 16 | `nested-rules` eval: "3 of 3", "no run without B6 to compare" | L467-468 | eval-results/phase1-b6-nested-rules-gemma4-26b.json | 3 | free |
| 17 | `long-doc` (16k cap): "2 of 2 passed", 14/14 each, 2 compactions each, 214 and 223 s; summaries 109-146 words; "two trials don't show a difference beyond the shorter summaries" | L479-485 | eval-results/phase1-b7-long-doc-gemma4-26b.json; compared with PLAN.md earlier runs (thinking on, 4 of 4, 183-662 s) | 2 vs 4 (different config) | free |
| 18 | Phase 1 bank before/after on Gemma 4 26B: 89/96 = 93% (86-96%) -> 85/96 = 89% (81-93%); mean 45 s -> 46 s; steps 6.4 -> 6.7; prompt tokens a run 15,036 -> 20,595; per request about 2,350 -> about 3,090 | L494-498 | run stores p1-before/p1-after; reports phase1-bank-{before,after}-gemma4-26b.md | 34-task bank + 14-task hard tier, 2 trials = 96 a side | free |
| 19 | "No measurable change in the pass rate: the intervals overlap, and none of the 8 new failures had a tool error"; 8 new failures listed as model slips | L500-502 | same | 8 new, about 4 fixed (L503) | free |
| 20 | "Every request costs about 740 more input tokens (about +31% a request, +37% a run)" attributed to "Phase 1's larger tool definitions" | L505-508 | same stores (arithmetic: 3,090-2,350 = 740; 20,595/15,036 = 1.37); no ablation | 96 runs | free |
| 21 | "matters for paid cheap models (the cost-floor re-run measures it)" | L506-507 | cf6 (no figure given in GA) | - | paid |

### 1c. Phase 2 as built / measured

| # | Claim | GA line | Evidence | n | P/F |
|---|---|---|---|---|---|
| 22 | Typical task = "20k prompt tokens, 13k of them cached, 900 out, 8 requests" ("a cost-floor bank run after Phase 1"); plan said "average run: 20k in, two-thirds from cache, 1k out" | L554 (plan L524-525) | a cost-floor bank run (single run or average not stated) | unstated | paid (cf6) |
| 23 | Model menu prices: ling-3.0-flash "$0.02 / $0.06 a million tokens, about $0.0003 a task"; Opus 5.5 "about $0.049" | L560-561 | OpenRouter live prices x TypicalTask (modeled) | - | free (price read) |
| 24 | Reasoning live: `--reasoning none` sent `reasoning_effort: "none"`, 0 reasoning tokens vs 284 default; 9:40->13:05 trip answered 185 min (wrong) off vs 205 on; one-line fix 42 s (also rewrote test for uninstalled pytest) off vs 55 s clean on | L556-559 | live Gemma, "one trial each" | 1 each | free |
| 25 | OpenRouter model browser lists "466 models"; Ollama/vLLM "Not checked live" | L561-563 | live app; unit tests | - | free |
| 26 | Behavior change: remote sessions now send subagent tasks to ling-3.0-flash and important ones' grading to Haiku 5.5 on this Mac | L578-579 | code change | - | - |
| 27 | A2 end-to-end test through `CLISession` with mock endpoints: subagent failed with made-up citations, edits undone, retried on rung 2 | L594-595 | mock | 1 | free |
| 28 | `cost report` over the re-run store: "$1.690; $0.00025 / $0.00183 / $0.00144 a run" (the three are unlabelled); this Mac 30 days "24 runs and $0.218, in 0.4 s" | L601 | cf6; session store | 1,439 runs; 24 runs | free (replay) |
| 29 | What-if: "re-run's 1,439 runs at ling-3.0-flash's listed price: $0.37 against $1.69 charged" (labelled first approximation, ignores verbosity differences, L150-151) | L602 | `cost whatif` over cf6 | 1,439 | free (modeled) |
| 30 | Cache notice test: 90%-cached request then 22k uncached: "$0.0440 for this request's input" | L610-611 | priced mock | 1 | free (mock) |
| 31 | Retry-sim, as first built: fires on 47 runs (14 ling, 21 deepseek, 12 Haiku), 2 gold failures, catches 2 of ling's 9, ling 470 -> 472 of 479, $0.120 -> $0.162 (+35%) | L619-622 | `kurtkode-eval --retry-sim cf6` (deepseek's stored run substituted as 2nd attempt) | 1,439 runs, 9 ling failures | free (replay) |
| 32 | Retry-sim after Round 6 checker fixes: fires on 4 runs (1, 2, 1), 1 gold failure, catches 1 of 9, 470 -> 471 of 479, $0.120 -> $0.122 (+1%); "cheap and rarely wrong, but it catches almost nothing" | L619-625 | same | same | free (replay) |
| 33 | "of ling's 9 failures, 8 were wrong answers whose reports looked fine (h-aliased-calls, importers-of-storage, review-diff)"; "the as-built trigger's 45 false alarms" | L626-630 | same | 9 | free |
| 34 | Eval-store spend (a run / a passing run; passes): bank1 $0.020/$0.011, 570 of 612; cf1 $0.013/$0.014, 2,897/3,107, 49% cached; cf2 $0.0024/$0.0025, 9,330/9,958; cf3a $0.0014/$0.0014, 2,156/2,226; cf6 $0.0012/$0.0012, 1,425/1,439, 64% cached | L632-634 | `cost report --eval` | as listed | free (replay of paid runs) |
| 35 | "Before Round 6 the same report counted bank1's degraded copies and cf1's infrastructure failures (1,071 runs, $11; 81% passed)" | L635-636 | same | 1,071 | free |
| 36 | This Mac, last 7 days: "16 runs, $0.218 (gemini-4-argon, 4 runs, $0.055 a run, 64% cached); the rest local"; "Too few labeled runs yet to say anything about quality" | L636-638 | session store | 16 runs / 4 paid | paid (real use) |
| 37 | Delegation, Haiku parent via OpenRouter, told to delegate (`--force-delegation`), 5 scenarios x 3 trials: subagents on Haiku 12/15, $0.0088 a run (subagents $0.0059, a subagent run $0.0024); on the pool 12/15, $0.0045 (subagents $0.0012, a subagent run $0.00047); survey 0/3 both; wall 48 s vs 51 s | L639-648 | eval-results/delegation-pool/{run.sh,haiku-pool-vs-main.json} | 15 runs per arm | paid ($0.198 by the key's count) |
| 38 | "The pool kept every pass and halved what a run cost (-48%); the subagents' share fell by 80%, a subagent run costing a fifth as much"; log sweep $0.0237 -> $0.0095 | L649-652 | same | 3 trials per scenario | paid |
| 39 | Survey failed in both setups (scores 0.60-0.90), "Not the pool's doing" | L652-654 | same | 3 + 3 | paid |
| 40 | "With a dearer parent the saving grows ... for an Opus or Sonnet parent the subagents' share ... several times larger (stage 4: Sonnet alone $0.022 a run)" | L654-655 | cost-floor stage 4 (not in GA); no Opus/Sonnet run in Phase 2 | none for this claim | modeled |
| 41 | "Not measured here: how often the ladder retried (the eval's throwaway subagent store isn't kept)" | L656-657 | admission | - | - |

### 1d. Phase 3 as built / measured

| # | Claim | GA line | Evidence | n | P/F |
|---|---|---|---|---|---|
| 42 | Snapshot cost: this repo 1.7 s first, 0.20 s after (1,247 tracked files; 2,787 untracked build files left out); ~/git/sugar 1.1 s then 0.15 s (664 tracked, 3,734 untracked, 21 GB, 12 MB stored); "a run gains about 0.3-0.4 s" | L739-742 | timings on two repos | 1 repo each | free |
| 43 | Live sed task (qwen3-coder-30b): run record carried both snapshot commits; `/diff` and app Changes tab listed sed's change | L742-746 | live | 1 | free |
| 44 | Revert by file and by hunk "unit-tested, not tried by hand"; three-button rewind dialog and Checkpoints list "built and compiled but not clicked through" | L746, L764-765 | unit tests | - | free |
| 45 | Files-only rewind live: notes.txt restored, "git status clean", note to model added, run got "rewound" judgment | L760-763 | live Debug app, qwen3-coder-30b | 1 | free |
| 46 | Review-sim, bank1 80 runs (8 real failures, 48 degraded copies, 24 passes), paid part $0.31 (cap $0.50). Haiku 5.5: real 8/8, all bad 56/56, 2 false alarms in 24, $0.0005, 4 s. gemini-3.8-flash: 6/8, 54/56, 0 FA, $0.0039, 8 s. deepseek-v4-flash-0731 reasoning off: 6/8, 51/55, 0 FA, $0.0001, 2 s. qwen3-coder-30b local: 5/8, 44/56, 0 FA, free, 3 s | L777-786 | eval-results/review-sim/ | 80 runs (8 real) | paid $0.31 + free local |
| 47 | "A review is cheap enough to run on every change: a hundredth of a cent for deepseek. Haiku missed nothing; its two 'false alarms' were cautions about things a diff can't show ..., and one pointed at a leftover path in the rebuilt diff headers (fixed since). Gemini flash is no better than deepseek here at 40 times the price" | L787-789 | same; the header fix not re-measured | 24 passes | paid |
| 48 | Reviewers miss "a rename left half done in a file the run never touched (undo-half on rename-total: qwen missed all four, deepseek one)" | L790-792 | same | 4 | paid/free |
| 49 | Live: `/review` in a local session refused remote reviewer; `-m lmstudio:qwen/qwen3-coder-30b` said "looks right" on a two-file change. Automatic subagent review "not run live" | L793-796 | live/mock | 1 | free |
| 50 | Trigger table, precision, recall: re-run check failed cf2 100%/3%, cf3a 100%/9%, bank1 100%/7% | L809-812 | `--trigger-sim`, eval-results/trigger-sim/offline.md | cf2 628 failures, cf3a 70, bank1 42 | free (replay) |
| 51 | Stopped early: cf2 96%/13%, cf3a 70%/20%, bank1 67%/10% | L812 | same | same | free |
| 52 | Last check failed after changing files: cf2 100%/1%, cf3a "-"/0%, bank1 67%/5% | L813 | same | bank1 about 3 firings | free |
| 53 | Any grounded signal: cf2 31%/16%, cf3a 10%/23%, bank1 54%/17% | L814 | same | same | free |
| 54 | Judge reading files (parent path) on bank1: argon 100%/71%, gemini-3.8-flash 100%/57%, Gemma 4 26B 67%/20% | L815 | stored judge verdicts | 42 failures | free (replay) |
| 55 | Grader without tools on bank1: argon 71%/36%, Gemma 57%/29% | L816 | same | same | free |
| 56 | A6 reviewer on 32 sampled code runs (8 failures, "an enriched sample, so precision reads high"): Haiku 80%/100%, deepseek 100%/75%, qwen3-coder 100%/63% | L817 | review-sim | 32 | paid/free |
| 57 | Ladder replay (bank1, 102 runs/model): Gemma alone 91/102 $0; ->ling->Haiku on grounded signals 94/102, $0.00001 a run; + Gemma's own grader <= 1 95/102; + gemini-3.8-flash reading files <= 1 96/102, $0.0033 a run, $0.0035 a success; oracle 102/102 $0.00003; Haiku alone 102/102 $0.00125 | L819-826 | `--ladder` replay on paired runs | 102 | free (replay) |
| 58 | Ladder replay (hard tier, 140 runs): mercury-2.5 alone 128/140 $0.00087 ($0.00095 a success); -> Haiku on grounded signals 129/140 $0.00109 ($0.00118); oracle 139/140 $0.00104; Haiku alone 139/140 $0.00154 ($0.00155) | L827-830 | same | 140 | free (replay) |
| 59 | "A perfect trigger would give Haiku's pass rate at 2% of its cost from a local model (bank1) and at 67% of it from mercury (hard tier). The grounded signals recover a quarter to a third of that gain for free" | L832-835 | derived from rows above | - | free (replay, oracle uses gold) |
| 60 | "Judges that read the files catch most failures with no false alarms, but cost more than the model they would save: gemini-3.8-flash checking every Gemma run costs $0.0033 a run against Haiku's $0.00125"; "A6's review is both cheap ($0.0001 with deepseek) and good (75-100% of the sampled code failures, no false alarms)" | L836-839 | tables above | - | free |
| 61 | "ling fails 9 of 479 bank runs and 1 of 140 hard ones, too few to escalate" | L841 | cf6, cf3a | 9, 1 | free |
| 62 | Replay "escalates to a fresh run of the stronger model, not a hand-over of the conversation and diff, so it approximates the real cascade" | L807-808 | admission | - | - |
| 63 | Mercury hard-tier judges (paid $0.35 list price; Haiku and deepseek judged all 140, qwen3-coder local judged 88 before being stopped): grounded signals catch 1/12, 7%, 129/140, $0.00109; Haiku grading <=1 7/12, 24%, 134/140, $0.00171; deepseek reading files <=1 4 of 9 judged, 67%, 132/140, $0.00140; qwen local grading <=1 3 of 11 judged, 21%, 131/140, $0.00115; perfect 12/12 139/140 $0.00104; Haiku alone 139/140 $0.00154 | L874-886 | mercury-2.5's runs in cf3 | 140 runs, 12 failures | paid $0.35 (list) + free |
| 64 | "No judge makes the cascade cheaper than the next model here: the best (Haiku grading every mercury run) costs more than running Haiku alone, because mercury is only half Haiku's price and the judge's request costs almost as much as a cheap model's run" | L888-890 | rows above | 12 failures | paid |
| 65 | "automatic escalation would need a judge that is both cheap and precise, which none of the six measured is"; "deepseek with reasoning off often gave no verdict as a grader (82 of 140)" | L892-894 | same | 140 | paid |
| 66 | Live escalation: CLI run capped at 3 steps offered "Escalate to ling-3.0-flash for about $0.0004? [y/N]" (declined); app showed card for a failed test; "Accepting ... is unit-tested with mock models, not tried live yet" | L853-856 | live qwen3-coder-30b | 1-2 | free |
| 67 | A7, Haiku parent via OpenRouter with pool subagents, 5 scenarios x 3 trials: unforced delegated survey 1/3, others 0, passed 14/15, 22 s a run; forced at threshold: delegated 0 of 15 ("the threshold never tripped"), 13/15, 18 s; paid about $0.08 | L896-902 | `--kk-delegation on|off|both`; no store named | 15 per arm | paid (about $0.08) |
| 68 | A7 on qwen3-coder (32k): off 0 of 6 delegated, 0/6 passed, survey 100 s, log-sweep 196 s; written by kurtkode: 3 of 6 delegated, 0/6 passed, survey 67 s, log-sweep 419 s | L903-904 | same | 6 per arm | free |
| 69 | "A7 changes nothing for hosted sessions as set"; "with Claude's real 200k context it would be reached even less"; "Delegating locally saves context, not time or money"; "a subagent on the same one-slot model doubled log-sweep's time" | L906-913 | rows above | 6-15 | mixed |
| 70 | Claude's forced `tool` choice only with thinking off, "which the newest models can't turn off"; Round 7: no forced or written call for Claude with thinking (note alone) | L863, L868-869 | API behavior; mock tests | - | - |
| 71 | LM Studio rejects named `tool_choice`; with "required" qwen3-coder-30b still answered in text "(tried 2026-10-26)" | L864 | one trial | 1 | free |
| 72 | Phase 3 paid total: "$0.31 (A6) + $0.35 (A4) + about $0.08 (A7) + $0.0002 (a live escalation to ling) = about $0.74", "under the $0.50 and $1.50 caps"; one mistaken Anthropic request refused, no charge | L915-917 | spend ledger | - | paid |
| 73 | "A threshold in tokens rather than in a share of the context would make it fire" (untested) | L909-910 | none | 0 | modeled |

### 1e. COST_ARCHITECTURE.md claims (for cross-reference)

| # | Claim | CA line | Evidence cited | n / notes |
|---|---|---|---|---|
| C1 | Cost entries calibrated "on existing keys $0.1124" | L25 | COST_TRACKING_DESIGN.md | not in GA |
| C2 | OpenRouter provider routing "made deepseek 2.4x dearer a run with no list-price change"; reconciliation: records lag minutes, "one in three after ten" | L26-27, L110-111 | COST_FLOOR_RESULTS.md re-run | not in GA |
| C3 | "cache share 64% on this Mac's paid runs"; "caching is 64% of paid input here" | L31, L108 | GA L636 (4 argon runs) / GA L634 (cf6 64%) | n=4 runs if this Mac |
| C4 | Pool: ling 474/480 at $0.0002 a run | L37 | cost-floor finalists | contradicts GA 470/479 (see Inconsistencies) |
| C5 | Auto subagents: "Haiku parent: pool subagents halved a run's cost (-48%) at the same pass rate (12/15 both)" | L38 | GA L637-652 | omits "told to delegate" |
| C6 | Retry ladder "catches 1 of ling's 9 bank failures (retry-sim over 1,439 runs)" | L39 | GA L621-624 | consistent |
| C7 | Default grader: "Haiku parent-path kappa 0.67 (catches 67% of failures, 2% false alarms)" | L40 | judge calibration | parent path, but default grader is tool-less path |
| C8 | Reasoning: "off cheaper per success for 61 of 85 models, but ling 99% -> 88%" | L41 | GA L51 | consistent |
| C9 | Prompt style: "Gemini long-doc 0/2 detailed vs 1/2 lean (tiny n)" | L42 | none | self-flagged tiny n |
| C10 | Grounded checks at subagent end: "14% of failures; with the re-run check 35%; all undone work, no stray edits" | L48 | EVAL_RESULTS.md | not in GA |
| C11 | Run signals as triggers: "16-23% of cheap models' failures pooled over about 12,000 stored runs, precise where they fire (re-run check 100%, stopped early 60-96%)" | L49 | `--trigger-sim` | GA L809-814 |
| C12 | Judges parent path: "argon 71%/100% precise, Haiku 67%, gemini flash 57% on bank1; deepseek 44% on mercury's hard runs" | L50 | JudgeCalibration | see Inconsistencies |
| C13 | Judges grader path: "29-58% recall at 21-71% precision" | L51 | AgentLoop.grade | GA L816, L881-884 |
| C14 | Review: "51-56 of 56 bad changes on the sampled code runs, 0-2 false alarms in 24", "$0.0001 (deepseek) - $0.0005 (Haiku)" | L52 | `--review-sim` | GA L782-785 |
| C15 | Escalation: "a perfect trigger would give Haiku's results at 2% of its cost from a local model; real triggers recover a quarter to a third of that; no judge measured makes it pay automatically" | L59 | replays | GA L832-835, L888 |
| C16 | Delegation: "no model delegates on its own (3 of 36); argon -63% cost with cheap subagents, Sonnet 1.7-2x dearer when forced; the threshold never tripped for a Haiku parent; locally it cost time, no gain" | L60 | EVAL_RESULTS.md; GA L902, L911 | argon/Sonnet figures not in GA |
| C17 | "Compaction and output budgets ... Phase 0-1 measurements (fewer steps, no growth)" | L61 | GA Phase 0-1 | contradicted by GA L497-498 |
| C18 | Money: "This Mac, last 30 days: 19 main runs, $0.218 ... gemini-4-argon (4 runs, $0.055 a run, 64% cached)" | L75-77 | session store | GA says 24 runs (L601), 16 runs/7 days (L636) |
| C19 | Stores: "about 19,000 stored runs" | L78 | on disk only | listed stores sum to about 17,500 + cf3b + cf5 |
| C20 | Typical prices: ling about $0.0002-0.0003 a task, deepseek-off about $0.0004, Haiku about $0.0013, frontier $0.02-0.05 (about 100x ling) "where they all pass" | L83-84 | cost floor | see Inconsistencies |
| C21 | Spent on measurement: cost floor $83.22 + re-run $1.69; Phase 2 $0.198; Phase 3 about $0.74 | L85 | ledger | GA L601, L640, L915 agree for last three |
| C22 | Lesson 1: "Hard-failure retries catch almost nothing (1 of 9); every cheap detector misses most wrong answers" | L89-91 | GA L624-630 | - |
| C23 | Lesson 2: judging every mercury run "costs more than just using the stronger model" | L92-95 | GA L888 | holds for Haiku-grader only |
| C24 | Lesson 7: "Cheap finalists pass 98-100% of the bank and hard tier; frontier models all pass" | L104-106 | cf6, cf3a/b | GA L634 cf6: 1,425/1,439 = 99.0%; ling 470/479 = 98.1% |
| C25 | Lesson 8: "20k in, 900 out"; "The built-in skills listing raised prompt tokens 32-103% with no skill loaded in 1,439 runs" | L107-109 | cf6 | GA attributes +31-37% to tool definitions (L505-508) |
| C26 | Lesson 12: "Real runs exposed eight gold bugs"; Lesson 13: "A fifth of OpenRouter configurations can't run at all" | L115-119 | cost floor | not in GA |

====================================================================
## 2. DECISIONS (user decisions recorded)
====================================================================

Theme A / pre-Phase:
- GA L55 (C9): local-model economics: no dollars for local models, time/tokens/machine recorded only ("user decision"). CA L131 still lists "local models free" as an open question.
- GA L111-113 (S2) / L255: earlier user decision "rules don't cover bash" (user declined deny rules covering bash); E2 reframes as a Settings toggle.
- GA L27/CA L26: list price is the comparison basis (user decision 2026-10-15, CA L26).
- GA L47-57 / L299: D1 (theta, value of an hour of waiting), D3 (retry on hard failure), D5 (embeddings in the app), D6 (stale pool), D8 (routing scoped to subagents) are referenced as prior decisions in SUBAGENT_ROUTING_DESIGN.md.

Decisions to take (options, recommendation first) L297-306, resolved at L308-314 (2026-10-25):
- GA L310: Decision 1 Routing scope: main agent too (D8 extended).
- GA L310-311: Decision 2 Escalation: advisory first, one-click card; automatic within budget only after trigger precision is measured.
- GA L311-313: Decision 3 Bash secrets (E2): seatbelt deny of withheld patterns when model is remote, default on, Settings toggle; local unaffected.
- GA L312-313: Decision 4 grep: bundle `rg` in app and CLI resources.
- GA L313: Decision 5 Responses API in Phase 4; Phase 0 fixes `max_completion_tokens`.
- GA L313-314: Decision 6 model for Phase 0: Claude Opus 5.5.

Phase 1 / 2:
- GA L405: user approved "a few cents" for gpt-oss-120b apply_patch check (spent $0.0024).
- GA L513-514 (and CA L108-109, L109): 2026-10-26, built-in skills stay offered to every agent ("small models have large contexts, so their listing's tokens aren't worth saving"), despite +prompt tokens.
- GA L541-542, L640: paid Phase 2 checks only with user's go-ahead; delegation scenarios run with go-ahead, $0.198.
- GA L576-577: A2 live check of defaults deferred pending user's go-ahead on cost (then done as the delegation run).

Phase 3 (stated at L720-725, 2026-10-26):
- GA L720-722: P3 decision 1: snapshots in a shadow repository per project under ~/.kurtkode/snapshots, non-git folders included (excludes + size cap).
- GA L722-723: P3 decision 2: automatic review only for subagent tasks with `importance: high` that changed files, in hosted sessions; main runs on request or as a cheap-first trigger.
- GA L723-724: P3 decision 3: escalation card offers the next tier up (cheap -> standard -> frontier), not straight to frontier.
- GA L724-725: P3 decision 4: at the delegation threshold kurtkode forces a `task` call, local sessions too (subagents on session's model).
- GA L911-913: user kept forced delegation on for local sessions (2026-10-26) after seeing the local A7 results (0/6 passed, log-sweep time doubled).
- GA L692, L707-708, L715-716: paid A6 sample, paid cheap-first run (only if replay says worth it), paid A7 run all "with the user's go-ahead"; caps $0.50 (A6) and $1.50 (later) set by user (L916-917).
- GA L663-664: local sessions send nothing to remote models that they didn't before (A2's rule, kept; CA L123-124 "local must mean surely local").
- GA L772: shipped pool: deepseek-v4-flash-0731 reasoning off is a reviewer; grader fallback still takes the strongest reviewer (Opus for a Haiku run), not the new cheap one (a build decision under P3 decision 2).

====================================================================
## 3. INCONSISTENCIES
====================================================================

I-1. Ling's bank pass count and failure count
- CA L37: "cost-floor finalists: ling 474/480 at $0.0002 a run" (6 failures).
- GA L621-622: "470 -> 472 of 479" / "470 -> 471 of 479" and "ling's 9 failures"; GA L841 "ling fails 9 of 479 bank runs".
- Different denominators (480 vs 479) and failure counts (6 vs 9). CA L39 itself says "1 of ling's 9 bank failures", so CA contradicts itself within the file.

I-2. Cost per run: Haiku and deepseek
- CA L83: "deepseek-off about $0.0004, Haiku about $0.0013".
- GA L601 (cf6 re-run, unlabeled): "$0.00025 / $0.00183 / $0.00144 a run" (cf6 total $1.690 / 1,439 = $0.00117). GA L827-830: Haiku $0.00125 (bank1), $0.00154 (hard tier).
- No cf6 figure is near $0.0004; if deepseek is $0.00144 or $0.00183 it is 3.6-4.6x the CA figure, more than the 2.4x provider-routing effect CA L26/L110 cites. GA L601 never labels which model each figure belongs to.

I-3. "Phase 0-1 measurements (fewer steps, no growth)" vs the Phase 1 measurement
- CA L61 (compaction and output budgets, evidence): "Phase 0-1 measurements (fewer steps, no growth)".
- GA L497: mean steps 6.4 -> 6.7 (more); GA L498: prompt tokens a run 15,036 -> 20,595 (+37%); GA L505: "Every request costs about 740 more input tokens"; GA L496: pass 93% -> 89%. Phase 0's planned "fewer steps per task" bank measure (GA L277) is never reported.

I-4. "A quarter to a third of that gain for free"
- GA L834-835 and CA L59: "real triggers recover a quarter to a third of that [oracle gain]".
- GA L819-830: bank1 Gemma 91 -> 94 (signals) is 3 of the 11 recoverable = 27%; 95 (+Gemma grader, free) = 36%; but hard tier mercury 128 -> 129 is 1 of 11 = 9%; GA L881 shows 1 of 12 failures caught at 7% precision. Only the bank1 row supports "a quarter to a third"; the hard tier is about a tenth. "For free" ignores that the false alarms cost money (mercury grounded-signals ladder $0.00109 vs $0.00087 alone, +25%).

I-5. "No judge makes the cascade cheaper than the next model"
- GA L888-890 / CA L59, L92-95.
- GA L881-885 and L827-830 per-success costs: grounded signals $0.00118, deepseek-reads $0.00140 a run (about $0.00148 per success), qwen local $0.00115 a run (about $0.00123 per success), all below Haiku alone $0.00155. Only Haiku grading ($0.00171 a run, about $0.00179 per success) exceeds Haiku alone. The claim holds only for pass-rate-matched comparisons or the single best-quality judge; the cheaper cascades are cheaper per success but pass 129-132 vs 139 of 140 (5-8 points less), a trade-off the summary does not state.

I-6. "No false alarms" for review
- GA L839: A6's review is "good (75-100% of the sampled code failures, no false alarms)".
- GA L782 / L787: Haiku had 2 false alarms in 24; GA L817: Haiku precision 80%; CA L52 says "0-2 false alarms in 24". The 2 are explained away (diff-invisible cautions; one from a diff-header artifact "fixed since", not re-measured).

I-7. Review headline blends synthetic with real failures
- CA L52: "51-56 of 56 bad changes on the sampled code runs".
- GA L777-785: of the 56 bad changes, 48 are synthetic degraded copies (stray edit/undo all/undo half/file gone); only 8 are real failures, where deepseek catches 6/8, gemini 6/8, qwen 5/8 (Haiku 8/8). CA's range also drops qwen's 44/56 and uses deepseek's 51/55 as "of 56".

I-8. Summary framing of detector landscape vs the review result
- CA L16 / L16-17: detectors "are either free and weak or strong and as expensive as the step up".
- GA L838-839, CA L52, lesson 5: diff review is "both cheap ($0.0001) and good". CA L59 lists the review as "off" by default and the cascade replay (GA L819-830) has no reviewer-triggered ladder though plan L698 promised "a judge's or reviewer's verdict where the store has one".

I-9. Run/judge numbers: argon/Haiku/gemini precision-recall
- CA L50: "argon 71%/100% precise, Haiku 67%, gemini flash 57% on bank1".
- GA L815: argon precision 100%, recall 71%; gemini-3.8-flash precision 100%, recall 57%; Gemma precision 67%, recall 20%. "Haiku 67%" has no GA counterpart on bank1 (GA's Haiku figures are kappa 0.67 at L156 and mercury grader 24%/7 of 12 at L881); "67%" matches Gemma's precision. CA's "71%/100% precise" has precision and recall swapped.

I-10. Stopped-early range
- CA L49: "stopped early 60-96%".
- GA L812: 96%, 70%, 67% (range 67-96%).

I-11. Grader recall range
- CA L51: "29-58% recall at 21-71% precision".
- GA L881-884: qwen local grading catches 3 of 11 = 27% (below 29%).

I-12. Default grader evidence is from the wrong path
- CA L40 default grader (Haiku) cites "parent-path kappa 0.67 (catches 67%, 2% false alarms)". CA L50-51 and GA L816: the grader path is tool-less with "29-58% recall at 21-71% precision"; GA L881 Haiku grader on mercury: 7/12, precision 24%. The shipped default is the grader path, whose measured quality is much lower than the cited figure.
- GA L571: the usual case (importance:high with no tier runs on Haiku, L569) is graded by Opus (first reviewer that isn't Haiku). Opus as grader has no measurement in either document and CA L40 says only "Haiku grades".

I-13. cf2 definition
- CA L80: "cf2 (the shortlist on the bank)". GA L809: "cf2 (9,958 runs of ~500 configurations, 628 failures)". 9,958 runs / about 500 configurations is not a shortlist.

I-14. This Mac's spending
- CA L75: "last 30 days: 19 main runs, $0.218".
- GA L601: "this Mac's last 30 days of sessions, 24 runs and $0.218". GA L636: "last 7 days: 16 runs, $0.218". Same $0.218 over 30 days and 7 days is possible only if all spend is within 7 days; 19 vs 24 vs 16 runs are unreconciled (main vs all runs?).

I-15. "Accepting is not tried live" vs paid live escalation
- GA L855-856: "Accepting (a paid OpenRouter request) is unit-tested with mock models, not tried live yet."
- GA L915-916: "$0.0002 (a live escalation to ling)" counted in Phase 3 paid spend.

I-16. warn-count result
- GA L379-380: warn-count eval "1 of 6 trials passed" (5 failures counted "warning").
- GA L503: "Fixed by Phase 1: warn-count passed both trials (count mode; it failed one before)". Not reconciled (different runs/stores?).

I-17. Skills listing vs tool definitions as cause of prompt growth
- CA L108-109: "built-in skills listing raised prompt tokens 32-103% with no skill loaded in 1,439 runs". GA L505-508 attributes +31% a request / +37% a run to "Phase 1's larger tool definitions". Both claim the same observed growth (Gemma vs cf6 stores are different), but no decomposition exists; neither GA nor CA gives the numbers for the cf6 re-run that GA L506-507 says "measures it".

I-18. Re-run check recall
- CA L48: grounded checks catch "14% of failures; with the re-run check 35%".
- GA L811: the re-run check alone catches 3% (cf2), 9% (cf3a), 7% (bank1) of failures. A +21-point gain from the re-run check cannot be reconciled with 3-9% recall unless it is a different store (EVAL_RESULTS.md subagent runs, not cited in GA).

I-19. Output budget: plan vs built
- GA L177: "3% with a 16 KB floor and a 200 KB ceiling". GA L322: "~8% of the context". (Not flagged as a decision change.)

I-20. Roles in the shipped pool
- CA L37 lists ling as "(cheap)" with no main role and omits Haiku's summarizer role. GA L848: "The shipped pool now gives ling-3.0-flash and Haiku 5.5 the main role"; GA L553: Haiku judge, reviewer, summarizer; GA L772: deepseek reviewer.

I-21. Delegation saving presented without "forced" qualifier
- CA L38 "Haiku parent: pool subagents halved a run's cost (-48%)" as evidence for automatic routing. GA L641-642: those runs were "told to delegate (`--force-delegation`; models don't on their own)". GA L901: unforced, Haiku delegated in 1 of 15 runs.

I-22. Stale statements in GA header/footer
- GA L3-5: "Phase 1 is being built item by item (session 14)" and GA L921-925 "No live runs; everything is from reading code ..." although the doc now contains Phases 0-3 with live runs and spend. CA L3 calls GA the record of "Phases 0-3 as built and measured".

I-23. Weak-vs-strong wording on retry
- GA L625-626: "the retry is now cheap and rarely wrong". GA L621-622: after fixes it fires on 4 runs of which 1 is a gold failure (3 of 4 firings are on gold passes, i.e., 75% false alarm rate; each undoes edits). "rarely wrong" refers to rare firing, not precision.

I-24. bank1 cost columns
- GA L632: "bank1 $0.020 / $0.011": spent a run ($0.020) is larger than spent a passing run ($0.011), impossible if the second column is cost per success (every other row has per-passing >= per-run: cf1 $0.013/$0.014, cf2 $0.0024/$0.0025). Unexplained.

====================================================================
## 4. GAPS
====================================================================

### 4a. Planned measures not reported in the "measured" sections

G-1. Phase 0 measure (GA L277): bank + hard tier on ling and a local model, steps per task / regressions. Not reported; only 8 live Gemma -p runs (L344-354) and a mock check (L336-342). Phase 0's claim "no regressions" has no bank measurement; Phase 1's bank before/after (L489-498) starts at 45a83da (before Phase 1), so Phase 0 is in both arms.
G-2. Phase 1 measure (GA L278): "plan-then-execute" and "long build in background" eval scenarios were named; no eval-scenario results for either (live single runs only, L424-429, L445-454); `nested-rules` 3/3 has no baseline (L467-468); long-doc 2 trials vs earlier 4 (L479-485).
G-3. Phase 2 measure (GA L279, L541-542): `cost report` "over ... a week of real sessions" gives 16 runs, 4 paid, "too few labeled runs yet" (L636-638). Retry ladder's rescue rate is a replay (substitutes deepseek's stored run for the second attempt; the real hand-in message and undo are not exercised); how often the live ladder retried is "not measured" (L656-657).
G-4. Phase 2 A1 live checks: Ollama and vLLM capability reading "Not checked live" (L562-563); cache notice only on a priced mock (L610-611), never against a real provider; the claim in plan C7 that subagents "evict" a single-slot local model's cache (GA L53, "inferred, untested") and D6 "measure the single-slot cache eviction" (L247) are never measured.
G-5. Phase 3 A4 measure (GA L680-708): (a) wall time is planned for the ladder replay (L280, L698-701) but absent from the ladder tables (L819-830); (b) "how often escalation was offered against needed" (escalation precision per ladder) not reported as such, only per-trigger precision; (c) planned hard-tier ladder "a cheap model, then Haiku, then Opus 5.5 ... cf3a and cf3b" (L698-700) reported only as mercury -> Haiku; Opus/frontier-alone never appears as a comparator although the plan says "against the stronger models alone" and the thesis is cost versus frontier; (d) "a task [Gemma] gets wrong, a card offered; one declined, one escalation to a paid model" planned on Gemma (L706-708) was done on qwen3-coder-30b, accepting not live (L855-856, but cf. I-15); (e) "a paid cheap-first eval run on the hard tier only if replay says it's worth it" not run (no statement either way).
G-6. A7 measure (GA L713-716): planned columns "delegations made, pass rate, cost and wall time" and "free on Gemma 4 26B"; the A7 table (L899-904) has delegations, pass, wall time but no cost column, and the local runs used qwen3-coder-30b, not Gemma. Forcing was never exercised on any hosted model (0 of 15 trips); Gemini `ANY` and OpenAI named `tool_choice` forcing are mock-tested only (L867-869); Claude forced call is disabled with thinking (L863, L868).
G-7. A6 measure (GA L689-692): "its false alarms on passing runs ... then the shipped candidates on a paid sample" done on bank1 only, one sample of 24 passes; automatic subagent review "not run live" (L796). The review as an escalation trigger is "off" by default and never put in a cascade replay (L698 promised reviewer verdicts in the replay).
G-8. C1/C3 measures: revert by hand not tried (L746); rewind dialog/checkpoint list not clicked (L764-765); snapshot timing on two repos, once each (L739-742).
G-9. Escalation records (L850) exist "to measure how often offers are taken and right in real use before anything goes automatic"; no real-use data is reported, and Decision 2's condition ("automatic only after trigger precision is measured") is satisfied only offline (CA L70 "measured, not good enough yet").
G-10. The A1 pool "Delegation scenarios with the shipped ladder vs today" (GA L279): the Phase 2 delegation run does not report ladder retries (L656) so the ladder was not part of the measured result.
G-11. Phase 1 cost effect: GA L506-508 says "the cost-floor re-run measures it" and "A follow-up could tighten those descriptions"; no number for the paid cost increase of +740 tokens/request is given; no ablation separating tool definitions from skills listing (cf. I-17); CA L109 says the skills-listing decision stands.
G-12. Local models are priced at $0 (GA L55; ladder rows $0 for Gemma, L821-825); wall time and theta are unbuilt (CA L68-69). The "2% of Haiku's cost" figure (CA L59, L95-96) is therefore a dollar-only number that treats Gemma's runs and electricity/time as free and excludes extra wall time of a failing local first attempt.

### 4b. Small-n results presented as findings

- Reasoning live check: one trial each (GA L558-559), and presented as "The difference showed".
- Phase 0 saved-output fix: 4 of 4 runs, with the fixture's script containing the failure text (L353).
- Gemma plan workflow: 0 of 4 runs called `present_plan` (L447); fallback verified in 2 runs.
- B5 apply_patch on gpt-oss-120b: 2 paid runs (L405-412); edit tooling on Gemma: 3 runs (L396-403).
- `nested-rules` 3 of 3 with no baseline; `long-doc` 2 of 2 (L467-485).
- warn-count: 1 of 6 (L379), 5 failures of one kind.
- Phase 1 bank before/after: 89/96 vs 85/96, 2 trials per task; CI overlap read as "No measurable change" while the point estimate is -4 points and tokens +37% (L496-500).
- Delegation: 15 runs per arm, 3 trials per scenario, survey 0/3 vs 0/3, 12/15 vs 12/15 (L644-648); the -48% is from 15 runs with no variance reported; the parent's own cost actually rose (computed: $0.0088-$0.0059 = $0.0029 vs $0.0045-$0.0012 = $0.0033, +14%) while subagent cost fell.
- A7 hosted: 15 runs per arm; 1 delegation unforced; qwen3-coder 6 runs per arm (L899-904).
- Review: 8 real failures, 24 good runs; 51/55 vs 56/56 differences are 1-5 runs (L782-785); deepseek 6/8 and qwen 5/8 "75-100%" (L839).
- Trigger tables: bank1 "last check failed" precision 67% on about 3 firings (5% of 42 failures = 2 hits); "re-run check failed" 100% on about 3 (bank1: 7% of 42) and about 6 (cf3a: 9% of 70) firings (L809-814); cf2/cf3a include around 500 configurations of mixed quality, not the shipped cheap tier; ling has 9 and 1 failures (L841).
- Mercury judges: 12 failures; deepseek's recall is "4 of 9 judged" (the rest had no verdict, 82 of 140 runs), qwen "3 of 11 judged", and qwen judged only 88 of 140 before being stopped (L874-886).
- Live escalation: CLI offer once, declined; app card once (L853-856).
- This Mac's spending: 4 paid runs, one model (gemini-4-argon), is the basis for "64% cached" and "$0.055 a run" (L636, CA L75-77, L108).
- Cost-floor re-run: the ladder table's "$0.00001" and "$0.00003" costs rest on 102 runs/arm with a handful of escalations.

### 4c. Savings claims resting on modeled rather than measured numbers

- Automatic subagent routing -48% (GA L649; CA L38): measured only under `--force-delegation` with a Haiku parent; unforced Haiku delegated 1 of 15 runs (L901); the threshold that triggers delegation "never tripped" for hosted models (L906-909); so the realized hosted-session saving at default settings is not measured and may be about zero.
- "With a dearer parent the saving grows" (L654-655): no Sonnet/Opus parent measured in Phase 2; relies on stage 4 numbers outside GA; CA L60 quotes "argon -63%" and "Sonnet 1.7-2x dearer when forced" from EVAL_RESULTS.md (not in GA).
- Cascade ceilings ("2% of Haiku's cost", "67%" for mercury): oracle trigger using gold labels (L824, L829, L832); local Gemma costed at $0; replay uses fresh stronger-model runs, not the built hand-over (L807-808).
- What-if repricing ($0.37 vs $1.69, L602) is "a first approximation" that ignores verbosity and provider routing (L150-151, CA L26 shows 2.4x provider effect).
- Model-menu "approximately $X a task" and "approximately $X to switch" (L554, L849) use TypicalTask (one benchmark's average) and list price (OpenRouter switch cost assumes the history read once at the listed input price); no validation against charged cost reported. Benchmarks saturate (CA L104-106) so TypicalTask may not represent real sessions.
- Escalation card price "Escalate to X for about $Y" is modeled; "never offered for cost limit" etc. are design.
- "Defaults would save on real work" has no real-workload estimate (CA L127-128, open question 1); real-session data "too thin to estimate savings" (CA L77-78).
- Retry ladder benefit: replay with substituted runs; +1 pass of 479 for +1% cost.
- Price staleness: table asOf 2026-10-14 (L54); warning only after 60 days (L333); CA L132 says introductory Gemini prices end 2026-11-30/12-31, i.e., before the 60-day warning would fire (about 2026-12-13); GA does not say whether `until` dates are read (L54 says only `asOf` was never read before Phase 0).
- Cache savings: "cache share 64%" for this Mac is 4 runs of one model; cf6 64% and the TypicalTask 13k/20k (65%) are coincident figures, not shown to be the same measure.
- Spend totals: A4 judges "$0.35 of list price" (L874) and A7 "about $0.08" are not charged amounts; the $0.74 total mixes list price and key counts (L915); provider-routing means list price can understate charge by 2.4x (CA L26).

====================================================================
## 5. MECHANISM DEFAULTS
====================================================================

| Mechanism | Default as stated | Where stated |
|---|---|---|
| Pool tiers | local < cheap < standard < frontier. Shipped: ling-3.0-flash (cheap; retry rung 1; subagent, main), deepseek-v4-flash-0731 reasoning off (cheap; rung 2; reviewer), Claude Haiku 5.5 (standard; rung 3; judge, reviewer, summarizer, main), Claude Opus 5.5 (frontier); OpenRouter ones with `data_collection: deny` | GA L553 (Phase 2); GA L772 (deepseek reviewer, Haiku reviews deepseek's); GA L848 (ling and Haiku main role); CA L37 (omits ling main role and Haiku summarizer) |
| Typical-task basis for price display | 20k prompt tokens, 13k cached, 900 out, 8 requests | GA L554 (plan: "two-thirds cached, 1k out", L524-525) |
| Automatic subagent model | "Automatic (the model pool)" is the default (unset or "auto"); "" = session's own model; only for hosted main models (`Endpoint.isCloudAPI`); local/LAN session subagents stay on its model; card tier cheap/standard/strong(=frontier, stays on main model); no tier: standard for `importance: high`, else cheap; pool's lowest subagent entry at or above tier (ling default, Haiku for important/standard) | GA L569; GA L527-529 (plan: also requires an OpenRouter key); CA L38 |
| Retry ladder (D3) | On: a hard failure (no report, stopped on error, made-up citations; not a failed `verify`) retried once on `ModelPool.next` (ling -> deepseek-off -> Haiku), never lower tier, within spending limits, never after stop/denial, never a retry of a retry; edits undone first | GA L572; CA L39 ("on"); GA L530-533 (plan) |
| Default grader | "Automatic (the pool's judge)": Haiku 5.5 grades `importance: high` subagent runs of hosted sessions; if the run was on Haiku the first reviewer that isn't (Opus); fallback "strongest reviewer", not the cheap deepseek reviewer | GA L571, L772; CA L40 |
| Reasoning setting | `ModelProfile.reasoning` nil = "the model's default" (none sent); "none" or effort level selectable; shipped deepseek entry reasoning off; `--reasoning LEVEL` CLI; eval's own object wins | GA L552, L553; CA L41 |
| Escalation card (A4) | Offers on (default); the cheap review of changes off (default, hosted only); never automatic; target = next tier up from the session model's tier (local -> ling -> Haiku -> Opus); fires on stopped early, last check failed after changing files, unfinished todos, thumbs-down/`/bad`, (opt-in) review finds problems; never for cost limit/stop/denial | GA L847-851, L705-706, L723-724; CA L59 |
| Delegation nudge / A7 threshold | Threshold: six broad reads in a row that put a fifth of the context in; at threshold the next step is a forced `task` call, "on by default" including local sessions (kurtkode writes the call for LM Studio; note only for Claude with thinking); Settings -> Subagents "...and have it delegate then" | GA L862-864, L868-869, L911-913; CA L60 ("on, local included") |
| Review (A6) | `/review` on request; automatic only for subagent tasks with `importance: high` that changed files in hosted sessions; reviewer = pool's first reviewer entry of a vendor different from the writers, lowest tier first (deepseek-off reviews Claude/Gemini; Haiku reviews deepseek's); local sessions only reviewers surely local, none shipped; diff cut at 60 KB | GA L722-723, L772-774; CA L52 |
| Compaction | Structured summary template; length 400 words under 20k context, 550 under 48k, 750 under 120k, 900 above; on (not an option); `SessionFacts.lastCheck` recorded | GA L475-476; CA L61 |
| Tool output budget | about 8% of context, 16 KB floor, 200 KB ceiling; `read_file` default 2000 lines; three truncated replies in a row stop the run | GA L322-323 (plan said 3%, L177); CA L61 |
| Limits | Run limit $2; session limit exists (default not stated in GA; CA says off); daily and per-project limits in Settings -> Generation -> Spending, default not stated in GA (CA: "others off"); a run stops at any limit; daily spend read only when a daily limit is set | GA L52, L603; CA L30 |
| Cache care | `CacheWatch` notice on: once a run, when a paid request of >= 8k prompt tokens reads < 10% from cache after one that read >= half; Claude 1-hour cache option off; "approximately $X to switch" before a model switch (OpenRouter too) | GA L604, L554; CA L31 |
| Snapshots (C1/C3) | On by default; shadow repository per project; caps: untracked folders > 200 files or 20 MB, files > 5 MB, no snapshots past 10,000 files or 200 MB; sessions' snapshots dropped when trashed, others after 30 days | GA L733, L736 |
| Price staleness | Warning when Claude/Gemini table is over 60 days old (table asOf 2026-10-14) | GA L333, L54 |
| Skills listing / skill router | Built-in skills listed to every agent (user decision 2026-10-26); router skips pure acknowledgements | GA L514, L332; CA L109 |
| Prompt style | detailed (lean for some) | CA L42 |
| Cost reporting basis | List price for comparisons; `spent` = charge where known else list price; OpenRouter reconciliation at run end | CA L26-27 |
| Automatic escalation / router P3 / theta | Not built (designed only) | GA L160-161, L849; CA L63-71 |
