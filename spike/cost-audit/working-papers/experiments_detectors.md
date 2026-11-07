# Detector and cost experiments on stored kurtkode eval runs (E1–E4)

Offline, free, stdlib-only analysis of `~/git/kurtkode/eval-results/runs` (read-only). Scripts: `scratchpad/scripts2/` — `extract.py` (compact per-run records, no transcript text, → `data2/<store>.jsonl`), `sim.py` (scores + PR utilities), `e1.py`, `e1b.py`, `e2.py`, `e3.py`, `e4.py`. All rates exclude degraded copies and infra failures. Label = `gold.passed`. Detectors never see gold. "Fire" = score ≤ threshold t. PR-AUC is average precision (step-wise, ties grouped). Base rates are tiny (ling cf6 9/479, Haiku cf6 4/480, deepseek cf6 1/480, mercury cf3a 12/140), so every recall/precision figure has wide error bars; one run moves recall by 8–100 points.

## Summary

**E1, cross-model agreement (no gold).** Text agreement between two cheap models' reports is a weak failure detector. On cf6 (ling as A), the best deployable score (word Jaccard) has AP 0.077–0.078 against a 1.9% base rate (4×). But its whole best-F1 operating point (t = 0, recall 2/9, precision 25%, fire 1.7%) consists of the two **empty reports**, which the existing free `emptyReport` check already catches with the same recall and precision. On ling's non-empty reports, AP is 0.012–0.021 against a 1.5% base rate, i.e. ≤1.4×: no useful signal. For Haiku as A, AP is about the base rate. On cf3a (mercury-2.5 as A, base rate 8.6%), the signal is real but weak: identifier Jaccard gives AP 0.17 (vs ling), 0.23 (vs Haiku) and 0.25 (mean score, vs deepseek#off), 2–3× the base rate. Operating points: vs ling, recall 75% / precision 15% at a 42% fire rate; vs deepseek#off, recall 25% / precision 43% at 5% fire. A task-centered variant (an oracle that subtracts the pair's typical agreement on that task) raises cf3a AP to 0.31–0.33. That shows most of the raw-score variance is task and style, not correctness.

**Cascade economics.**
- **cf6, ling + deepseek#off (corrected $0.00045), escalating to Haiku on disagreement.** At best F1 it costs $0.00073 for 98.54% pass. Matching Haiku's 99.16% means escalating 44% of runs: $0.00134/run, only 7% cheaper than always-Haiku ($0.00144). The free "escalate if the report is empty" rule gets the same 98.54% for $0.00028.
- **Ceiling.** An oracle escalation of exactly ling's 9 failures would give 100% for $0.00028: Haiku passes the same trial in 9/9 cases.
- **cf3a, mercury.** mercury + ling already costs $0.00118 before any escalation, and matching Haiku's 99.29% needs 81% escalation: $0.00243, 58% more than always-Haiku ($0.00154). Every mercury cascade is dominated by always-Haiku.

**E2, self-consistency.** These results are no better.
- **ling cf6, one extra trial (`pair1`):** AP 0.064 (3.4×). Best F1 again equals the empty reports (recall 22%, precision 18%). Non-empty AP is ≤0.025. The cascade costs $0.00054 for 98.54%, and matching Haiku's pass rate needs 81% escalation: $0.00167.
- **10 trials (mean9):** AP 0.094–0.099, still mostly the empty reports.
- **mercury cf3a:** pair1 AP 0.16 (1.9×); mean9 path agreement AP 0.28 (3.3×), with recall 58% / precision 26% at 19% fire. Two mercury trials alone ($0.00174) already exceed Haiku's cost.
- **Haiku cf6:** about base rate.
- **Where self-consistency works:** for models whose failures are mostly empty or garbled reports (step-3.5-flash, deepseek-v4-flash-0731 in cf3a), mean9 AP is 0.3–0.4 (9–15×). Most of that is again the empty reports.

**E3, where the money goes.**
- **First request.** The first request (fixed overhead plus task) is 36% of ling's list cost on cf6, 30% of deepseek's, 46% of Haiku's, 33–34% of Opus/Sonnet's (cf3b). On the hard tier it is 16–21% for non-Anthropic models and 29% for Haiku.
- **Haiku cache writes.** Haiku's cache writes are 54% of its cf6 cost: every run writes its first prompt (5-minute cache write at 1.25×), and no first request ever reads a cache from an earlier run (0/480).
- **Cross-run caching for ling and deepseek** stops at 256–512 tokens of a 1.7k/4.9k first prompt. A run-specific element early in the system prompt is the likely cause (the temporary project root path in the Environment block, plus date and git facts); this is not verified.
- **No caching for mercury and argon.** mercury-2.5 and gemini-4-argon get almost no cache reads: 13% and 4–7% of prompt tokens, against about 70–80% for ideal prefix caching at their step counts. Ideal caching would roughly halve argon's per-run cost at 4 requests ($0.0074 vs $0.0154, no-cache model).
- **Extrapolation.** With ideal caching, the cached share of prompt tokens is 61–82% at the observed 3–7 steps, then 84–87% at 10, 91–92% at 20 and 95–96% at 40. The first request's share of cost falls to 13–23%, 5–12% and 1–6% (for ling, Haiku, argon, mercury and Opus).

**Seconds (mean / median).**
- **cf6:** ling 16.9/15.1, deepseek#off 19.4/16.9, Haiku 17.1/15.9.
- **cf3a:** ling 21.6/18.9, mercury 17.8/16.1, Haiku 19.0/17.7.
- **cf3b:** Opus 25.5/24.2, Sonnet 18.9/17.5, argon 36.3/32.0.
- **bank1:** argon (direct API) 18.7/14.0; local Gemma 26B 57.7/39.5 (p90 127); qwen3.5-9b (LAN) 32.5/25.0; Gemma e4b 80.4/49.2.

**E4, clustering.** Failures cluster on a few tasks far more than independence predicts.
- **ling cf6:** 9 failures on 4 of 48 tasks, against about 8.3 expected (p < 0.0001).
- **Haiku cf6:** 4 failures on 2 tasks, against 3.9 expected (p = 0.002).
- **mercury cf3a:** 12 failures on 5 of 14 tasks, against 8.4 expected (p = 0.002); 7 of the 12 are on h-aliased-calls.
- **Pooled:** all cf6 failures sit on 6 of 48 tasks (about 12 expected). All 42 failures of the 12 main cf3a models sit on 8 of 14 tasks (about 13 expected), and h-discount-code plus h-aliased-calls hold 28 of the 42.
- **Where escalation can help:** the tasks where ling fails and Haiku passes all 10 are h-discount-code, importers-of-storage and review-diff.
- **Haiku's own cf6 failures:** h-aliased-calls (3/10; Haiku answered in a table without the `path:line` citations the gold check parses, so these are format failures with correct content) and review-clean (1/10).

**Caveats.**
- cf6 deepseek list prices are inflated (stored uncached input is $0.44/M vs $0.042/M in cf3a), so its E3 shares are indicative only. The economics use $0.00045.
- The cascade pass rates use Haiku's actual run of the same task and trial, so they include Haiku's own failures.
- The task-centered (`-tc`) scores need other runs of the same task and are not deployable as-is.
- `last`-sentence agreement is near useless everywhere, because models phrase their closing lines differently.

## E1. Cross-model agreement as a failure detector

### cf6: per-model mean cost per run (from the store)

| model | runs | gold failures | mean listPrice | mean charged |
|---|---|---|---|---|
| ling | 479 | 9 | $0.00025 | $0.00025 |
| deepseek#off | 480 | 1 | $0.00285 | $0.00183 |
| Haiku | 480 | 4 | $0.00144 | $0.00144 |

Costs used in the economics: ling $0.00025, deepseek#off $0.00045, Haiku $0.00144 (deepseek: corrected list price; cf6 stored list is inflated ~6×, charged is $0.00183)

### cf6: A = ling, B = deepseek#off (479 matched (task, trial) pairs, 9 A failures, base rate 1.9%)

Scores: Jaccard of `words` (stop words removed), `idents` (numbers, paths, snake/Camel tokens, quoted strings), `paths` (file paths only), `last` (words of the last sentence), `mean` of the four; `-tc` = task-centered (minus the median of the same pair's score on the task's 9 other trials; needs other runs of the task, so it is an oracle-calibrated variant). AP(non-empty) = AP over the 471 pairs whose A report is non-empty (7 failures), i.e. what the detector adds beyond the existing emptyReport check.

| score | PR-AUC (AP) | AP / base rate | AP (non-empty A) | best-F1 threshold (fire if score ≤ t) | recall | precision | fire rate | recall @ fire ≤10% | precision there |
|---|---|---|---|---|---|---|---|---|---|
| words | 0.077 | 4.1× | 0.018 | 0.000 | 22% (2/9) | 25% (2/8) | 1.7% | 22% (t=0.000) | 25% |
| idents | 0.069 | 3.7× | 0.016 | 0.000 | 22% (2/9) | 22% (2/9) | 1.9% | 22% (t=0.000) | 22% |
| paths | 0.030 | 1.6× | 0.020 | 0.400 | 56% (5/9) | 3% (5/144) | 30.1% | – | – |
| last | 0.017 | 0.9× | 0.012 | 0.267 | 89% (8/9) | 2% (8/368) | 76.8% | – | – |
| mean | 0.074 | 4.0× | 0.016 | 0.000 | 22% (2/9) | 25% (2/8) | 1.7% | 22% (t=0.000) | 25% |
| words-tc | 0.021 | 1.1× | 0.018 | 0.064 | 100% (9/9) | 3% (9/358) | 74.7% | 0% (t=-0.833) | 0% |
| idents-tc | 0.026 | 1.4× | 0.024 | 0.024 | 89% (8/9) | 3% (8/266) | 55.5% | 0% (t=-0.507) | 0% |
| paths-tc | 0.024 | 1.3× | 0.023 | -0.050 | 44% (4/9) | 3% (4/116) | 24.2% | 0% (t=-1.000) | 0% |
| last-tc | 0.018 | 0.9× | 0.014 | 0.130 | 89% (8/9) | 2% (8/373) | 77.9% | 0% (t=-0.857) | 0% |
| mean-tc | 0.021 | 1.1× | 0.018 | 0.030 | 100% (9/9) | 3% (9/302) | 63.0% | 0% (t=-0.492) | 0% |

Sweep for the best-AP deployable (non-task-centered) score (`words`), each row a threshold where recall rises (fire if score ≤ t):

| t | fire rate | recall | precision | cascade $/run | cascade pass | extra $/run of false alarms |
|---|---|---|---|---|---|---|
| 0.000 | 1.7% | 22% (2) | 25.0% | $0.00073 | 98.54% | $0.00002 |
| 0.258 | 23.0% | 33% (3) | 2.7% | $0.00103 | 98.54% | $0.00032 |
| 0.292 | 31.9% | 44% (4) | 2.6% | $0.00116 | 98.75% | $0.00045 |
| 0.328 | 38.4% | 56% (5) | 2.7% | $0.00126 | 98.96% | $0.00054 |
| 0.333 | 42.2% | 67% (6) | 3.0% | $0.00131 | 98.96% | $0.00059 |
| 0.341 | 44.1% | 78% (7) | 3.3% | $0.00134 | 99.16% | $0.00062 |
| 0.414 | 64.5% | 89% (8) | 2.6% | $0.00163 | 99.37% | $0.00091 |
| 0.467 | 75.4% | 100% (9) | 2.5% | $0.00179 | 99.37% | $0.00106 |
| 1.000 | 100.0% | 100% (9) | 1.9% | $0.00215 | 99.16% | $0.00142 |

Reference: always ling $0.00025/run, pass 98.12%; always Haiku $0.00144/run, pass 99.16%; (ling+deepseek#off, never escalate) $0.00070/run.

### cf6: A = ling, B = Haiku (479 matched (task, trial) pairs, 9 A failures, base rate 1.9%)

Scores: Jaccard of `words` (stop words removed), `idents` (numbers, paths, snake/Camel tokens, quoted strings), `paths` (file paths only), `last` (words of the last sentence), `mean` of the four; `-tc` = task-centered (minus the median of the same pair's score on the task's 9 other trials; needs other runs of the task, so it is an oracle-calibrated variant). AP(non-empty) = AP over the 471 pairs whose A report is non-empty (7 failures), i.e. what the detector adds beyond the existing emptyReport check.

| score | PR-AUC (AP) | AP / base rate | AP (non-empty A) | best-F1 threshold (fire if score ≤ t) | recall | precision | fire rate | recall @ fire ≤10% | precision there |
|---|---|---|---|---|---|---|---|---|---|
| words | 0.078 | 4.2× | 0.019 | 0.000 | 22% (2/9) | 25% (2/8) | 1.7% | 22% (t=0.000) | 25% |
| idents | 0.068 | 3.6× | 0.015 | 0.000 | 22% (2/9) | 22% (2/9) | 1.9% | 22% (t=0.000) | 22% |
| paths | 0.032 | 1.7× | 0.021 | 0.400 | 56% (5/9) | 4% (5/140) | 29.2% | – | – |
| last | 0.020 | 1.1× | 0.014 | 0.038 | 67% (6/9) | 2% (6/267) | 55.7% | – | – |
| mean | 0.075 | 4.0× | 0.016 | 0.000 | 22% (2/9) | 25% (2/8) | 1.7% | 22% (t=0.000) | 25% |
| words-tc | 0.032 | 1.7× | 0.031 | -0.055 | 56% (5/9) | 5% (5/107) | 22.3% | 0% (t=-0.359) | 0% |
| idents-tc | 0.034 | 1.8× | 0.034 | -0.167 | 22% (2/9) | 6% (2/33) | 6.9% | 22% (t=-0.167) | 6% |
| paths-tc | 0.027 | 1.5× | 0.028 | -0.050 | 44% (4/9) | 4% (4/89) | 18.6% | 0% (t=-1.000) | 0% |
| last-tc | 0.017 | 0.9× | 0.012 | 0.158 | 100% (9/9) | 2% (9/443) | 92.5% | 0% (t=-0.286) | 0% |
| mean-tc | 0.026 | 1.4× | 0.023 | 0.000 | 89% (8/9) | 3% (8/242) | 50.5% | 0% (t=-0.296) | 0% |

Sweep for the best-AP deployable (non-task-centered) score (`words`), each row a threshold where recall rises (fire if score ≤ t):

| t | fire rate | recall | precision |
|---|---|---|---|
| 0.000 | 1.7% | 22% (2) | 25.0% |
| 0.226 | 18.4% | 33% (3) | 3.4% |
| 0.288 | 35.9% | 56% (5) | 2.9% |
| 0.295 | 37.8% | 67% (6) | 3.3% |
| 0.365 | 59.7% | 78% (7) | 2.4% |
| 0.387 | 66.2% | 89% (8) | 2.5% |
| 0.394 | 67.4% | 100% (9) | 2.8% |
| 0.758 | 100.0% | 100% (9) | 1.9% |

### cf6: A = deepseek#off, B = ling (479 matched (task, trial) pairs, 1 A failures, base rate 0.2%)

Scores: Jaccard of `words` (stop words removed), `idents` (numbers, paths, snake/Camel tokens, quoted strings), `paths` (file paths only), `last` (words of the last sentence), `mean` of the four; `-tc` = task-centered (minus the median of the same pair's score on the task's 9 other trials; needs other runs of the task, so it is an oracle-calibrated variant). AP(non-empty) = AP over the 479 pairs whose A report is non-empty (1 failures), i.e. what the detector adds beyond the existing emptyReport check.

| score | PR-AUC (AP) | AP / base rate | AP (non-empty A) | best-F1 threshold (fire if score ≤ t) | recall | precision | fire rate | recall @ fire ≤10% | precision there |
|---|---|---|---|---|---|---|---|---|---|
| words | 0.083 | 39.9× | 0.083 | 0.059 | 100% (1/1) | 8% (1/12) | 2.5% | 100% (t=0.059) | 8% |
| idents | 0.111 | 53.2× | 0.111 | 0.000 | 100% (1/1) | 11% (1/9) | 1.9% | 100% (t=0.000) | 11% |
| paths | 0.010 | 4.7× | 0.010 | 0.000 | 100% (1/1) | 1% (1/101) | 21.1% | – | – |
| last | 0.007 | 3.2× | 0.007 | 0.000 | 100% (1/1) | 1% (1/149) | 31.1% | – | – |
| mean | 0.111 | 53.2× | 0.111 | 0.020 | 100% (1/1) | 11% (1/9) | 1.9% | 100% (t=0.020) | 11% |
| words-tc | 0.056 | 26.6× | 0.056 | -0.233 | 100% (1/1) | 6% (1/18) | 3.8% | 100% (t=-0.233) | 6% |
| idents-tc | 0.067 | 31.9× | 0.067 | -0.273 | 100% (1/1) | 7% (1/15) | 3.1% | 100% (t=-0.273) | 7% |
| paths-tc | 0.050 | 24.0× | 0.050 | -1.000 | 100% (1/1) | 5% (1/20) | 4.2% | 100% (t=-1.000) | 5% |
| last-tc | 0.004 | 1.8× | 0.004 | 0.000 | 100% (1/1) | 0% (1/272) | 56.8% | 0% (t=-0.857) | 0% |
| mean-tc | 0.030 | 14.5× | 0.030 | -0.166 | 100% (1/1) | 3% (1/33) | 6.9% | 100% (t=-0.166) | 3% |

Sweep for the best-AP deployable (non-task-centered) score (`idents`), each row a threshold where recall rises (fire if score ≤ t):

| t | fire rate | recall | precision | cascade $/run | cascade pass | extra $/run of false alarms |
|---|---|---|---|---|---|---|
| 0.000 | 1.9% | 100% (1) | 11.1% | $0.00073 | 100.00% | $0.00002 |
| 1.000 | 100.0% | 100% (1) | 0.2% | $0.00215 | 99.16% | $0.00144 |

Reference: always deepseek#off $0.00045/run, pass 99.79%; always Haiku $0.00144/run, pass 99.16%; (deepseek#off+ling, never escalate) $0.00070/run.

### cf6: A = deepseek#off, B = Haiku (480 matched (task, trial) pairs, 1 A failures, base rate 0.2%)

Scores: Jaccard of `words` (stop words removed), `idents` (numbers, paths, snake/Camel tokens, quoted strings), `paths` (file paths only), `last` (words of the last sentence), `mean` of the four; `-tc` = task-centered (minus the median of the same pair's score on the task's 9 other trials; needs other runs of the task, so it is an oracle-calibrated variant). AP(non-empty) = AP over the 480 pairs whose A report is non-empty (1 failures), i.e. what the detector adds beyond the existing emptyReport check.

| score | PR-AUC (AP) | AP / base rate | AP (non-empty A) | best-F1 threshold (fire if score ≤ t) | recall | precision | fire rate | recall @ fire ≤10% | precision there |
|---|---|---|---|---|---|---|---|---|---|
| words | 1.000 | 480.0× | 1.000 | 0.070 | 100% (1/1) | 100% (1/1) | 0.2% | 100% (t=0.070) | 100% |
| idents | 1.000 | 480.0× | 1.000 | 0.042 | 100% (1/1) | 100% (1/1) | 0.2% | 100% (t=0.042) | 100% |
| paths | 0.111 | 53.3× | 0.111 | 0.000 | 100% (1/1) | 11% (1/9) | 1.9% | 100% (t=0.000) | 11% |
| last | 0.004 | 1.9× | 0.004 | 0.000 | 100% (1/1) | 0% (1/249) | 51.9% | – | – |
| mean | 1.000 | 480.0× | 1.000 | 0.037 | 100% (1/1) | 100% (1/1) | 0.2% | 100% (t=0.037) | 100% |
| words-tc | 1.000 | 480.0× | 1.000 | -0.326 | 100% (1/1) | 100% (1/1) | 0.2% | 100% (t=-0.326) | 100% |
| idents-tc | 1.000 | 480.0× | 1.000 | -0.396 | 100% (1/1) | 100% (1/1) | 0.2% | 100% (t=-0.396) | 100% |
| paths-tc | 0.013 | 6.1× | 0.013 | -0.333 | 100% (1/1) | 1% (1/79) | 16.5% | 0% (t=-1.000) | 0% |
| last-tc | 0.003 | 1.7× | 0.003 | 0.000 | 100% (1/1) | 0% (1/290) | 60.4% | 0% (t=-0.333) | 0% |
| mean-tc | 0.500 | 240.0× | 0.500 | -0.256 | 100% (1/1) | 50% (1/2) | 0.4% | 100% (t=-0.256) | 50% |

Sweep for the best-AP deployable (non-task-centered) score (`words`), each row a threshold where recall rises (fire if score ≤ t):

| t | fire rate | recall | precision |
|---|---|---|---|
| 0.070 | 0.2% | 100% (1) | 100.0% |
| 0.846 | 100.0% | 100% (1) | 0.2% |

### cf6: A = Haiku, B = ling (479 matched (task, trial) pairs, 4 A failures, base rate 0.8%)

Scores: Jaccard of `words` (stop words removed), `idents` (numbers, paths, snake/Camel tokens, quoted strings), `paths` (file paths only), `last` (words of the last sentence), `mean` of the four; `-tc` = task-centered (minus the median of the same pair's score on the task's 9 other trials; needs other runs of the task, so it is an oracle-calibrated variant). AP(non-empty) = AP over the 479 pairs whose A report is non-empty (4 failures), i.e. what the detector adds beyond the existing emptyReport check.

| score | PR-AUC (AP) | AP / base rate | AP (non-empty A) | best-F1 threshold (fire if score ≤ t) | recall | precision | fire rate | recall @ fire ≤10% | precision there |
|---|---|---|---|---|---|---|---|---|---|
| words | 0.012 | 1.5× | 0.012 | 0.181 | 25% (1/4) | 2% (1/44) | 9.2% | 25% (t=0.181) | 2% |
| idents | 0.008 | 1.0× | 0.008 | 0.652 | 100% (4/4) | 1% (4/430) | 89.8% | 0% (t=0.000) | 0% |
| paths | 0.010 | 1.2× | 0.010 | 0.800 | 75% (3/4) | 1% (3/283) | 59.1% | – | – |
| last | 0.011 | 1.3× | 0.011 | 0.000 | 75% (3/4) | 1% (3/259) | 54.1% | – | – |
| mean | 0.010 | 1.1× | 0.010 | 0.157 | 25% (1/4) | 1% (1/77) | 16.1% | 0% (t=0.000) | 0% |
| words-tc | 0.007 | 0.8× | 0.007 | 0.107 | 100% (4/4) | 1% (4/421) | 87.9% | 0% (t=-0.359) | 0% |
| idents-tc | 0.009 | 1.1× | 0.009 | -0.101 | 25% (1/4) | 2% (1/64) | 13.4% | 0% (t=-0.509) | 0% |
| paths-tc | 0.007 | 0.8× | 0.007 | 0.400 | 100% (4/4) | 1% (4/427) | 89.1% | 0% (t=-1.000) | 0% |
| last-tc | 0.021 | 2.5× | 0.021 | -0.062 | 50% (2/4) | 3% (2/60) | 12.5% | 0% (t=-0.286) | 0% |
| mean-tc | 0.007 | 0.8× | 0.007 | 0.121 | 100% (4/4) | 1% (4/447) | 93.3% | 0% (t=-0.296) | 0% |

Sweep for the best-AP deployable (non-task-centered) score (`words`), each row a threshold where recall rises (fire if score ≤ t):

| t | fire rate | recall | precision |
|---|---|---|---|
| 0.000 | 1.7% | 0% (0) | 0.0% |
| 0.181 | 9.2% | 25% (1) | 2.3% |
| 0.350 | 54.9% | 50% (2) | 0.8% |
| 0.429 | 77.0% | 75% (3) | 0.8% |
| 0.447 | 79.1% | 100% (4) | 1.1% |
| 0.758 | 100.0% | 100% (4) | 0.8% |

### cf6: A = Haiku, B = deepseek#off (480 matched (task, trial) pairs, 4 A failures, base rate 0.8%)

Scores: Jaccard of `words` (stop words removed), `idents` (numbers, paths, snake/Camel tokens, quoted strings), `paths` (file paths only), `last` (words of the last sentence), `mean` of the four; `-tc` = task-centered (minus the median of the same pair's score on the task's 9 other trials; needs other runs of the task, so it is an oracle-calibrated variant). AP(non-empty) = AP over the 480 pairs whose A report is non-empty (4 failures), i.e. what the detector adds beyond the existing emptyReport check.

| score | PR-AUC (AP) | AP / base rate | AP (non-empty A) | best-F1 threshold (fire if score ≤ t) | recall | precision | fire rate | recall @ fire ≤10% | precision there |
|---|---|---|---|---|---|---|---|---|---|
| words | 0.013 | 1.6× | 0.013 | 0.279 | 25% (1/4) | 2% (1/52) | 10.8% | 0% (t=0.070) | 0% |
| idents | 0.017 | 2.0× | 0.017 | 0.324 | 50% (2/4) | 2% (2/93) | 19.4% | 25% (t=0.265) | 2% |
| paths | 0.015 | 1.7× | 0.015 | 0.600 | 75% (3/4) | 2% (3/154) | 32.1% | 0% (t=0.000) | 0% |
| last | 0.009 | 1.1× | 0.009 | 0.087 | 100% (4/4) | 1% (4/362) | 75.4% | – | – |
| mean | 0.016 | 1.9× | 0.016 | 0.223 | 50% (2/4) | 2% (2/85) | 17.7% | 0% (t=0.037) | 0% |
| words-tc | 0.010 | 1.2× | 0.010 | -0.072 | 25% (1/4) | 2% (1/61) | 12.7% | 0% (t=-0.326) | 0% |
| idents-tc | 0.048 | 5.7× | 0.048 | -0.276 | 25% (1/4) | 11% (1/9) | 1.9% | 25% (t=-0.276) | 11% |
| paths-tc | 0.021 | 2.5× | 0.021 | -0.400 | 50% (2/4) | 3% (2/64) | 13.3% | 0% (t=-1.000) | 0% |
| last-tc | 0.026 | 3.1× | 0.026 | -0.056 | 50% (2/4) | 3% (2/59) | 12.3% | 0% (t=-0.333) | 0% |
| mean-tc | 0.024 | 2.9× | 0.024 | -0.124 | 25% (1/4) | 6% (1/16) | 3.3% | 25% (t=-0.124) | 6% |

Sweep for the best-AP deployable (non-task-centered) score (`idents`), each row a threshold where recall rises (fire if score ≤ t):

| t | fire rate | recall | precision |
|---|---|---|---|
| 0.042 | 0.2% | 0% (0) | 0.0% |
| 0.265 | 10.0% | 25% (1) | 2.1% |
| 0.324 | 19.4% | 50% (2) | 2.2% |
| 0.444 | 43.3% | 75% (3) | 1.4% |
| 0.600 | 75.2% | 100% (4) | 1.1% |
| 1.000 | 100.0% | 100% (4) | 0.8% |

### cf3a: per-model mean cost per run (from the store)

| model | runs | gold failures | mean listPrice | mean charged |
|---|---|---|---|---|
| ling | 140 | 1 | $0.00031 | $0.00031 |
| deepseek#off | 140 | 1 | $0.00068 | $0.00069 |
| Haiku | 140 | 1 | $0.00154 | $0.00154 |
| mercury-2.5 | 140 | 12 | $0.00087 | $0.00087 |

Costs used in the economics: ling $0.00031, deepseek#off $0.00068, Haiku $0.00154, mercury-2.5 $0.00087

### cf3a: A = mercury-2.5, B = ling (140 matched (task, trial) pairs, 12 A failures, base rate 8.6%)

Scores: Jaccard of `words` (stop words removed), `idents` (numbers, paths, snake/Camel tokens, quoted strings), `paths` (file paths only), `last` (words of the last sentence), `mean` of the four; `-tc` = task-centered (minus the median of the same pair's score on the task's 9 other trials; needs other runs of the task, so it is an oracle-calibrated variant). AP(non-empty) = AP over the 139 pairs whose A report is non-empty (11 failures), i.e. what the detector adds beyond the existing emptyReport check.

| score | PR-AUC (AP) | AP / base rate | AP (non-empty A) | best-F1 threshold (fire if score ≤ t) | recall | precision | fire rate | recall @ fire ≤10% | precision there |
|---|---|---|---|---|---|---|---|---|---|
| words | 0.115 | 1.3× | 0.067 | 0.488 | 83% (10/12) | 10% (10/103) | 73.6% | 8% (t=0.000) | 50% |
| idents | 0.168 | 2.0× | 0.113 | 0.389 | 75% (9/12) | 15% (9/59) | 42.1% | 17% (t=0.136) | 17% |
| paths | 0.119 | 1.4× | 0.103 | 0.750 | 92% (11/12) | 13% (11/82) | 58.6% | – | – |
| last | 0.070 | 0.8× | 0.063 | 0.353 | 100% (12/12) | 10% (12/121) | 86.4% | – | – |
| mean | 0.137 | 1.6× | 0.085 | 0.317 | 67% (8/12) | 12% (8/67) | 47.9% | 8% (t=0.000) | 50% |
| words-tc | 0.149 | 1.7× | 0.094 | -0.047 | 50% (6/12) | 14% (6/43) | 30.7% | 17% (t=-0.125) | 20% |
| idents-tc | 0.309 | 3.6× | 0.273 | -0.116 | 67% (8/12) | 32% (8/25) | 17.9% | 42% (t=-0.233) | 42% |
| paths-tc | 0.199 | 2.3× | 0.206 | -0.150 | 75% (9/12) | 26% (9/35) | 25.0% | 17% (t=-1.000) | 15% |
| last-tc | 0.134 | 1.6× | 0.121 | -0.051 | 50% (6/12) | 21% (6/29) | 20.7% | 8% (t=-0.151) | 7% |
| mean-tc | 0.288 | 3.4× | 0.238 | -0.165 | 33% (4/12) | 50% (4/8) | 5.7% | 42% (t=-0.116) | 36% |

Sweep for the best-AP deployable (non-task-centered) score (`idents`), each row a threshold where recall rises (fire if score ≤ t):

| t | fire rate | recall | precision | cascade $/run | cascade pass | extra $/run of false alarms |
|---|---|---|---|---|---|---|
| 0.000 | 1.4% | 8% (1) | 50.0% | $0.00120 | 92.14% | $0.00001 |
| 0.136 | 8.6% | 17% (2) | 16.7% | $0.00131 | 92.86% | $0.00011 |
| 0.167 | 12.1% | 25% (3) | 17.6% | $0.00137 | 93.57% | $0.00015 |
| 0.265 | 24.3% | 33% (4) | 11.8% | $0.00155 | 94.29% | $0.00033 |
| 0.300 | 28.6% | 42% (5) | 12.5% | $0.00162 | 95.00% | $0.00038 |
| 0.312 | 29.3% | 50% (6) | 14.6% | $0.00163 | 95.71% | $0.00038 |
| 0.342 | 35.0% | 58% (7) | 14.3% | $0.00172 | 96.43% | $0.00046 |
| 0.368 | 40.7% | 67% (8) | 14.0% | $0.00181 | 97.14% | $0.00054 |
| 0.389 | 42.1% | 75% (9) | 15.3% | $0.00183 | 97.86% | $0.00055 |
| 0.462 | 56.4% | 83% (10) | 12.7% | $0.00205 | 98.57% | $0.00076 |
| 0.533 | 70.0% | 92% (11) | 11.2% | $0.00226 | 98.57% | $0.00096 |
| 0.600 | 81.4% | 100% (12) | 10.5% | $0.00243 | 99.29% | $0.00112 |
| 0.944 | 100.0% | 100% (12) | 8.6% | $0.00272 | 99.29% | $0.00141 |

Reference: always mercury-2.5 $0.00087/run, pass 91.43%; always Haiku $0.00154/run, pass 99.29%; (mercury-2.5+ling, never escalate) $0.00118/run.

### cf3a: A = mercury-2.5, B = Haiku (140 matched (task, trial) pairs, 12 A failures, base rate 8.6%)

Scores: Jaccard of `words` (stop words removed), `idents` (numbers, paths, snake/Camel tokens, quoted strings), `paths` (file paths only), `last` (words of the last sentence), `mean` of the four; `-tc` = task-centered (minus the median of the same pair's score on the task's 9 other trials; needs other runs of the task, so it is an oracle-calibrated variant). AP(non-empty) = AP over the 139 pairs whose A report is non-empty (11 failures), i.e. what the detector adds beyond the existing emptyReport check.

| score | PR-AUC (AP) | AP / base rate | AP (non-empty A) | best-F1 threshold (fire if score ≤ t) | recall | precision | fire rate | recall @ fire ≤10% | precision there |
|---|---|---|---|---|---|---|---|---|---|
| words | 0.156 | 1.8× | 0.064 | 0.538 | 100% (12/12) | 9% (12/140) | 100.0% | 8% (t=0.000) | 100% |
| idents | 0.232 | 2.7× | 0.129 | 0.304 | 50% (6/12) | 18% (6/34) | 24.3% | 17% (t=0.133) | 50% |
| paths | 0.193 | 2.3× | 0.151 | 0.250 | 50% (6/12) | 30% (6/20) | 14.3% | 25% (t=0.167) | 21% |
| last | 0.072 | 0.8× | 0.063 | 0.286 | 100% (12/12) | 9% (12/138) | 98.6% | – | – |
| mean | 0.170 | 2.0× | 0.075 | 0.148 | 17% (2/12) | 20% (2/10) | 7.1% | 17% (t=0.148) | 20% |
| words-tc | 0.156 | 1.8× | 0.064 | -0.087 | 17% (2/12) | 17% (2/12) | 8.6% | 17% (t=-0.087) | 17% |
| idents-tc | 0.332 | 3.9× | 0.272 | -0.183 | 33% (4/12) | 44% (4/9) | 6.4% | 33% (t=-0.183) | 44% |
| paths-tc | 0.261 | 3.0× | 0.237 | -0.350 | 50% (6/12) | 46% (6/13) | 9.3% | 50% (t=-0.350) | 46% |
| last-tc | 0.278 | 3.2× | 0.254 | -0.053 | 25% (3/12) | 43% (3/7) | 5.0% | 25% (t=-0.053) | 43% |
| mean-tc | 0.309 | 3.6× | 0.221 | -0.110 | 25% (3/12) | 50% (3/6) | 4.3% | 33% (t=-0.061) | 29% |

Sweep for the best-AP deployable (non-task-centered) score (`idents`), each row a threshold where recall rises (fire if score ≤ t):

| t | fire rate | recall | precision |
|---|---|---|---|
| 0.000 | 0.7% | 8% (1) | 100.0% |
| 0.133 | 2.9% | 17% (2) | 50.0% |
| 0.214 | 12.1% | 25% (3) | 17.6% |
| 0.250 | 15.7% | 33% (4) | 18.2% |
| 0.296 | 23.6% | 42% (5) | 15.2% |
| 0.304 | 24.3% | 50% (6) | 17.6% |
| 0.345 | 36.4% | 58% (7) | 13.7% |
| 0.433 | 57.9% | 67% (8) | 9.9% |
| 0.462 | 70.7% | 75% (9) | 9.1% |
| 0.500 | 80.0% | 83% (10) | 8.9% |
| 0.522 | 82.1% | 92% (11) | 9.6% |
| 0.793 | 100.0% | 100% (12) | 8.6% |

### cf3a: A = mercury-2.5, B = deepseek#off (140 matched (task, trial) pairs, 12 A failures, base rate 8.6%)

Scores: Jaccard of `words` (stop words removed), `idents` (numbers, paths, snake/Camel tokens, quoted strings), `paths` (file paths only), `last` (words of the last sentence), `mean` of the four; `-tc` = task-centered (minus the median of the same pair's score on the task's 9 other trials; needs other runs of the task, so it is an oracle-calibrated variant). AP(non-empty) = AP over the 139 pairs whose A report is non-empty (11 failures), i.e. what the detector adds beyond the existing emptyReport check.

| score | PR-AUC (AP) | AP / base rate | AP (non-empty A) | best-F1 threshold (fire if score ≤ t) | recall | precision | fire rate | recall @ fire ≤10% | precision there |
|---|---|---|---|---|---|---|---|---|---|
| words | 0.200 | 2.3× | 0.101 | 0.226 | 25% (3/12) | 21% (3/14) | 10.0% | 25% (t=0.226) | 21% |
| idents | 0.246 | 2.9× | 0.142 | 0.294 | 58% (7/12) | 21% (7/33) | 23.6% | 17% (t=0.091) | 50% |
| paths | 0.157 | 1.8× | 0.126 | 0.200 | 42% (5/12) | 22% (5/23) | 16.4% | 17% (t=0.000) | 20% |
| last | 0.101 | 1.2× | 0.088 | 0.250 | 100% (12/12) | 10% (12/115) | 82.1% | – | – |
| mean | 0.247 | 2.9× | 0.143 | 0.149 | 25% (3/12) | 43% (3/7) | 5.0% | 25% (t=0.149) | 43% |
| words-tc | 0.136 | 1.6× | 0.093 | -0.114 | 25% (3/12) | 23% (3/13) | 9.3% | 25% (t=-0.114) | 23% |
| idents-tc | 0.254 | 3.0× | 0.225 | -0.152 | 58% (7/12) | 33% (7/21) | 15.0% | 33% (t=-0.217) | 40% |
| paths-tc | 0.212 | 2.5× | 0.189 | -0.400 | 50% (6/12) | 38% (6/16) | 11.4% | 33% (t=-0.400) | 29% |
| last-tc | 0.117 | 1.4× | 0.105 | -0.049 | 42% (5/12) | 18% (5/28) | 20.0% | 0% (t=-0.615) | 0% |
| mean-tc | 0.151 | 1.8× | 0.124 | -0.149 | 25% (3/12) | 25% (3/12) | 8.6% | 25% (t=-0.149) | 25% |

Sweep for the best-AP deployable (non-task-centered) score (`mean`), each row a threshold where recall rises (fire if score ≤ t):

| t | fire rate | recall | precision | cascade $/run | cascade pass | extra $/run of false alarms |
|---|---|---|---|---|---|---|
| 0.000 | 0.7% | 8% (1) | 100.0% | $0.00156 | 92.14% | $0.00000 |
| 0.092 | 2.9% | 17% (2) | 50.0% | $0.00160 | 92.86% | $0.00002 |
| 0.149 | 5.0% | 25% (3) | 42.9% | $0.00163 | 93.57% | $0.00004 |
| 0.222 | 20.0% | 33% (4) | 14.3% | $0.00186 | 94.29% | $0.00026 |
| 0.252 | 35.7% | 42% (5) | 10.0% | $0.00210 | 95.00% | $0.00049 |
| 0.261 | 37.9% | 50% (6) | 11.3% | $0.00214 | 95.71% | $0.00052 |
| 0.274 | 41.4% | 58% (7) | 12.1% | $0.00219 | 96.43% | $0.00056 |
| 0.279 | 43.6% | 67% (8) | 13.1% | $0.00222 | 97.14% | $0.00058 |
| 0.291 | 50.7% | 75% (9) | 12.7% | $0.00233 | 97.86% | $0.00068 |
| 0.355 | 72.1% | 83% (10) | 9.9% | $0.00266 | 98.57% | $0.00100 |
| 0.363 | 74.3% | 92% (11) | 10.6% | $0.00270 | 98.57% | $0.00102 |
| 0.433 | 87.1% | 100% (12) | 9.8% | $0.00290 | 99.29% | $0.00121 |
| 0.625 | 100.0% | 100% (12) | 8.6% | $0.00309 | 99.29% | $0.00141 |

Reference: always mercury-2.5 $0.00087/run, pass 91.43%; always Haiku $0.00154/run, pass 99.29%; (mercury-2.5+deepseek#off, never escalate) $0.00155/run.

### cf3a: A = ling, B = mercury-2.5 (140 matched (task, trial) pairs, 1 A failures, base rate 0.7%)

Scores: Jaccard of `words` (stop words removed), `idents` (numbers, paths, snake/Camel tokens, quoted strings), `paths` (file paths only), `last` (words of the last sentence), `mean` of the four; `-tc` = task-centered (minus the median of the same pair's score on the task's 9 other trials; needs other runs of the task, so it is an oracle-calibrated variant). AP(non-empty) = AP over the 139 pairs whose A report is non-empty (1 failures), i.e. what the detector adds beyond the existing emptyReport check.

| score | PR-AUC (AP) | AP / base rate | AP (non-empty A) | best-F1 threshold (fire if score ≤ t) | recall | precision | fire rate | recall @ fire ≤10% | precision there |
|---|---|---|---|---|---|---|---|---|---|
| words | 0.008 | 1.2× | 0.009 | 0.536 | 100% (1/1) | 1% (1/118) | 84.3% | 0% (t=0.000) | 0% |
| idents | 0.013 | 1.8× | 0.013 | 0.462 | 100% (1/1) | 1% (1/79) | 56.4% | 0% (t=0.000) | 0% |
| paths | 0.016 | 2.3× | 0.017 | 0.500 | 100% (1/1) | 2% (1/61) | 43.6% | – | – |
| last | 0.010 | 1.4× | 0.010 | 0.222 | 100% (1/1) | 1% (1/103) | 73.6% | – | – |
| mean | 0.009 | 1.3× | 0.009 | 0.406 | 100% (1/1) | 1% (1/109) | 77.9% | 0% (t=0.000) | 0% |
| words-tc | 0.008 | 1.1× | 0.008 | 0.124 | 100% (1/1) | 1% (1/129) | 92.1% | 0% (t=-0.435) | 0% |
| idents-tc | 0.026 | 3.7× | 0.027 | -0.072 | 100% (1/1) | 3% (1/38) | 27.1% | 0% (t=-0.464) | 0% |
| paths-tc | 0.031 | 4.4× | 0.032 | -0.250 | 100% (1/1) | 3% (1/32) | 22.9% | 0% (t=-1.000) | 0% |
| last-tc | 0.011 | 1.5× | 0.011 | 0.068 | 100% (1/1) | 1% (1/95) | 67.9% | 0% (t=-0.357) | 0% |
| mean-tc | 0.012 | 1.6× | 0.012 | 0.034 | 100% (1/1) | 1% (1/85) | 60.7% | 0% (t=-0.366) | 0% |

Sweep for the best-AP deployable (non-task-centered) score (`paths`), each row a threshold where recall rises (fire if score ≤ t):

| t | fire rate | recall | precision | cascade $/run | cascade pass | extra $/run of false alarms |
|---|---|---|---|---|---|---|
| 0.000 | 21.4% | 0% (0) | 0.0% | $0.00151 | 99.29% | $0.00033 |
| 0.500 | 43.6% | 100% (1) | 1.6% | $0.00185 | 100.00% | $0.00066 |
| 1.000 | 100.0% | 100% (1) | 0.7% | $0.00272 | 99.29% | $0.00153 |

Reference: always ling $0.00031/run, pass 99.29%; always Haiku $0.00154/run, pass 99.29%; (ling+mercury-2.5, never escalate) $0.00118/run.

### Baselines for the cascade economics

`empty` = escalate to Haiku only when the cheap run's report is empty (free; the existing emptyReport check). `oracle` = escalate exactly the gold failures (upper bound for any detector). Final answer on escalation = Haiku's run of the same task/trial.

| store | cheap model | $/run cheap | Haiku $/run | policy | fire rate | recall | precision | cascade $/run | cascade pass | always-cheap pass | always-Haiku pass |
|---|---|---|---|---|---|---|---|---|---|---|---|
| cf6 | ling-3.0-flash | $0.00025 | $0.00144 | empty | 1.7% | 2/9 | 25% | $0.00028 | 98.54% | 98.12% | 99.16% |
| cf6 | ling-3.0-flash | $0.00025 | $0.00144 | oracle | 1.9% | 9/9 | 100% | $0.00028 | 100.00% | 98.12% | 99.16% |
| cf6 | deepseek-v4-flash-0731#off | $0.00045 | $0.00144 | empty | 0.0% | 0/1 | – | $0.00045 | 99.79% | 99.79% | 99.17% |
| cf6 | deepseek-v4-flash-0731#off | $0.00045 | $0.00144 | oracle | 0.2% | 1/1 | 100% | $0.00045 | 100.00% | 99.79% | 99.17% |
| cf3a | mercury-2.5 | $0.00087 | $0.00154 | empty | 0.7% | 1/12 | 100% | $0.00088 | 92.14% | 91.43% | 99.29% |
| cf3a | mercury-2.5 | $0.00087 | $0.00154 | oracle | 8.6% | 12/12 | 100% | $0.00100 | 99.29% | 91.43% | 99.29% |
| cf3a | ling-3.0-flash | $0.00031 | $0.00154 | empty | 0.7% | 0/1 | 0% | $0.00032 | 99.29% | 99.29% | 99.29% |
| cf3a | ling-3.0-flash | $0.00031 | $0.00154 | oracle | 0.7% | 1/1 | 100% | $0.00032 | 100.00% | 99.29% | 99.29% |

## E2. Self-consistency as a failure detector

For each run, agreement with the same model's other trials of the same task (scores as in E1). Variants: `mean9` = mean similarity to the other 9 trials (needs 10 runs per task: ~10× cost); `medoid` = similarity to the task's medoid trial (the trial with the highest mean similarity; the medoid itself uses its mean9); `pair1` = similarity to ONE other trial, averaged over the 9 possible partners (the realistic deployment: one extra trial, 2× cost). Fire when the score ≤ t. Empty reports score 0 against everything.

### cf6: inclusionai/ling-3.0-flash — 479 runs, 9 failures (base rate 1.9%), 2 of them empty reports; cost/run $0.00025

| variant | score | PR-AUC (AP) | AP / base | AP (non-empty) | best-F1 t | recall | precision | fire rate | recall @ fire ≤10% (precision) |
|---|---|---|---|---|---|---|---|---|---|
| mean9 | words | 0.086 | 4.6× | 0.023 | 0.000 | 22% (2.0/9) | 25% | 1.7% | 33% (8%) |
| mean9 | idents | 0.088 | 4.7× | 0.027 | 0.000 | 22% (2.0/9) | 25% | 1.7% | 22% (25%) |
| mean9 | paths | 0.094 | 5.0× | 0.046 | 0.000 | 33% (3.0/9) | 20% | 3.1% | 33% (20%) |
| mean9 | last | 0.059 | 3.1× | 0.019 | 0.000 | 22% (2.0/9) | 15% | 2.7% | 22% (15%) |
| mean9 | mean | 0.094 | 5.0× | 0.030 | 0.000 | 22% (2.0/9) | 25% | 1.7% | 44% (11%) |
| medoid | words | 0.085 | 4.5× | 0.024 | 0.000 | 22% (2.0/9) | 25% | 1.7% | 22% (25%) |
| medoid | idents | 0.092 | 4.9× | 0.030 | 0.000 | 22% (2.0/9) | 25% | 1.7% | 22% (25%) |
| medoid | paths | 0.053 | 2.8× | 0.037 | 0.750 | 89% (8.0/9) | 7% | 23.6% | – |
| medoid | last | 0.031 | 1.7× | 0.020 | 0.067 | 44% (4.0/9) | 4% | 18.6% | – |
| medoid | mean | 0.099 | 5.2× | 0.035 | 0.000 | 22% (2.0/9) | 25% | 1.7% | 44% (12%) |
| pair1 | words | 0.064 | 3.4× | 0.017 | 0.000 | 22% (2.0/9) | 18% | 2.4% | 30% (6%) |
| pair1 | idents | 0.055 | 2.9× | 0.019 | 0.000 | 22% (2.0/9) | 13% | 3.2% | 23% (4%) |
| pair1 | paths | 0.036 | 1.9× | 0.025 | 0.750 | 85% (7.7/9) | 5% | 32.0% | – |
| pair1 | last | 0.022 | 1.2× | 0.013 | 0.188 | 60% (5.4/9) | 3% | 43.8% | – |
| pair1 | mean | 0.064 | 3.4× | 0.017 | 0.000 | 22% (2.0/9) | 18% | 2.4% | 28% (6%) |

Economics, `pair1` with `words` (one extra trial of the same model, escalate to Haiku when the pair disagrees; final answer = Haiku's run of the same task/trial). Haiku $0.00144/run. Rows: first threshold reaching each 10% recall step.

| t | fire rate | recall | precision | cascade $/run | cascade pass |
|---|---|---|---|---|---|
| 0.000 | 2.4% | 22% | 17.6% | $0.00054 | 98.54% |
| 0.327 | 12.3% | 31% | 4.7% | $0.00068 | 98.56% |
| 0.400 | 22.3% | 41% | 3.4% | $0.00082 | 98.68% |
| 0.476 | 34.3% | 53% | 2.9% | $0.00100 | 98.84% |
| 0.542 | 46.4% | 60% | 2.4% | $0.00117 | 98.86% |
| 0.571 | 53.4% | 72% | 2.5% | $0.00127 | 99.05% |
| 0.667 | 68.1% | 81% | 2.2% | $0.00149 | 98.96% |
| 0.714 | 74.0% | 91% | 2.3% | $0.00157 | 99.07% |
| 0.875 | 87.2% | 100% | 2.2% | $0.00176 | 99.16% |
| 1.000 | 100.0% | 100% | 1.9% | $0.00195 | 99.16% |

Reference: always ling-3.0-flash $0.00025, pass 98.12%; always Haiku $0.00144, pass 99.16%; two trials without escalation $0.00050.

### cf6: deepseek/deepseek-v4-flash-0731#off — 480 runs, 1 failures (base rate 0.2%), 0 of them empty reports; cost/run $0.00045

| variant | score | PR-AUC (AP) | AP / base | AP (non-empty) | best-F1 t | recall | precision | fire rate | recall @ fire ≤10% (precision) |
|---|---|---|---|---|---|---|---|---|---|
| mean9 | words | 1.000 | 480.0× | 1.000 | 0.117 | 100% (1.0/1) | 100% | 0.2% | 100% (100%) |
| mean9 | idents | 1.000 | 480.0× | 1.000 | 0.049 | 100% (1.0/1) | 100% | 0.2% | 100% (100%) |
| mean9 | paths | 0.333 | 160.0× | 0.333 | 0.000 | 100% (1.0/1) | 33% | 0.6% | 100% (33%) |
| mean9 | last | 0.040 | 19.2× | 0.040 | 0.020 | 100% (1.0/1) | 4% | 5.2% | 100% (4%) |
| mean9 | mean | 1.000 | 480.0× | 1.000 | 0.062 | 100% (1.0/1) | 100% | 0.2% | 100% (100%) |
| medoid | words | 1.000 | 480.0× | 1.000 | 0.140 | 100% (1.0/1) | 100% | 0.2% | 100% (100%) |
| medoid | idents | 1.000 | 480.0× | 1.000 | 0.048 | 100% (1.0/1) | 100% | 0.2% | 100% (100%) |
| medoid | paths | 0.143 | 68.6× | 0.143 | 0.000 | 100% (1.0/1) | 14% | 1.5% | 100% (14%) |
| medoid | last | 0.009 | 4.3× | 0.009 | 0.067 | 100% (1.0/1) | 1% | 23.1% | – |
| medoid | mean | 1.000 | 480.0× | 1.000 | 0.068 | 100% (1.0/1) | 100% | 0.2% | 100% (100%) |
| pair1 | words | 0.323 | 155.2× | 0.323 | 0.140 | 100% (1.0/1) | 38% | 0.6% | 100% (38%) |
| pair1 | idents | 0.464 | 222.6× | 0.464 | 0.048 | 89% (0.9/1) | 50% | 0.4% | 100% (17%) |
| pair1 | paths | 0.076 | 36.6× | 0.076 | 0.000 | 100% (1.0/1) | 8% | 2.7% | 100% (8%) |
| pair1 | last | 0.005 | 2.4× | 0.005 | 0.067 | 100% (1.0/1) | 1% | 40.8% | – |
| pair1 | mean | 0.494 | 237.3× | 0.494 | 0.072 | 89% (0.9/1) | 50% | 0.4% | 100% (45%) |

Economics, `pair1` with `mean` (one extra trial of the same model, escalate to Haiku when the pair disagrees; final answer = Haiku's run of the same task/trial). Haiku $0.00144/run. Rows: first threshold reaching each 10% recall step.

| t | fire rate | recall | precision | cascade $/run | cascade pass |
|---|---|---|---|---|---|
| 0.044 | 0.0% | 11% | 50.0% | $0.00090 | 99.81% |
| 0.048 | 0.1% | 22% | 50.0% | $0.00090 | 99.84% |
| 0.054 | 0.1% | 33% | 50.0% | $0.00090 | 99.86% |
| 0.059 | 0.2% | 44% | 50.0% | $0.00090 | 99.88% |
| 0.061 | 0.2% | 56% | 50.0% | $0.00090 | 99.91% |
| 0.063 | 0.3% | 67% | 50.0% | $0.00090 | 99.93% |
| 0.068 | 0.3% | 78% | 50.0% | $0.00090 | 99.95% |
| 0.072 | 0.4% | 89% | 50.0% | $0.00091 | 99.98% |
| 0.088 | 0.5% | 100% | 45.0% | $0.00091 | 100.00% |
| 1.000 | 100.0% | 100% | 0.2% | $0.00234 | 99.17% |

Reference: always deepseek-v4-flash-0731#off $0.00045, pass 99.79%; always Haiku $0.00144, pass 99.17%; two trials without escalation $0.00090.

### cf6: anthropic/claude-haiku-5.5 — 480 runs, 4 failures (base rate 0.8%), 0 of them empty reports; cost/run $0.00144

| variant | score | PR-AUC (AP) | AP / base | AP (non-empty) | best-F1 t | recall | precision | fire rate | recall @ fire ≤10% (precision) |
|---|---|---|---|---|---|---|---|---|---|
| mean9 | words | 0.024 | 2.9× | 0.024 | 0.362 | 25% (1.0/4) | 7% | 3.1% | 25% (7%) |
| mean9 | idents | 0.012 | 1.4× | 0.012 | 0.667 | 100% (4.0/4) | 1% | 56.0% | 0% (0%) |
| mean9 | paths | 0.013 | 1.6× | 0.013 | 0.620 | 25% (1.0/4) | 3% | 7.3% | 25% (3%) |
| mean9 | last | 0.020 | 2.4× | 0.020 | 0.011 | 25% (1.0/4) | 3% | 8.1% | 25% (3%) |
| mean9 | mean | 0.014 | 1.7× | 0.014 | 0.422 | 100% (4.0/4) | 2% | 50.2% | 0% (0%) |
| medoid | words | 0.036 | 4.3× | 0.036 | 0.333 | 25% (1.0/4) | 11% | 1.9% | 25% (11%) |
| medoid | idents | 0.017 | 2.0× | 0.017 | 0.667 | 100% (4.0/4) | 2% | 40.8% | 0% (0%) |
| medoid | paths | 0.010 | 1.2× | 0.010 | 0.667 | 25% (1.0/4) | 1% | 14.6% | 0% (0%) |
| medoid | last | 0.009 | 1.1× | 0.009 | 0.318 | 100% (4.0/4) | 1% | 72.1% | – |
| medoid | mean | 0.013 | 1.5× | 0.013 | 0.474 | 100% (4.0/4) | 2% | 51.0% | 0% (0%) |
| pair1 | words | 0.011 | 1.3× | 0.011 | 0.342 | 14% (0.6/4) | 2% | 5.0% | 19% (2%) |
| pair1 | idents | 0.009 | 1.1× | 0.009 | 0.680 | 86% (3.4/4) | 1% | 57.0% | 0% (0%) |
| pair1 | paths | 0.009 | 1.1× | 0.009 | 0.250 | 3% (0.1/4) | 3% | 0.7% | 6% (2%) |
| pair1 | last | 0.012 | 1.4× | 0.012 | 0.000 | 64% (2.6/4) | 1% | 42.0% | – |
| pair1 | mean | 0.010 | 1.2× | 0.010 | 0.435 | 83% (3.3/4) | 1% | 55.7% | 8% (1%) |

Economics, `pair1` with `last` (one extra trial of the same model, escalate to Haiku when the pair disagrees; final answer = Haiku's run of the same task/trial). Haiku $0.00144/run. Rows: first threshold reaching each 10% recall step.

| t | fire rate | recall | precision | cascade $/run | cascade pass |
|---|---|---|---|---|---|
| 0.000 | 42.0% | 64% | 1.3% | $0.00350 | 99.17% |
| 0.077 | 54.9% | 72% | 1.1% | $0.00368 | 99.17% |
| 0.143 | 66.1% | 83% | 1.1% | $0.00384 | 99.17% |
| 0.211 | 74.2% | 92% | 1.0% | $0.00396 | 99.17% |
| 0.333 | 84.1% | 100% | 1.0% | $0.00410 | 99.17% |
| 1.000 | 100.0% | 100% | 0.8% | $0.00433 | 99.17% |

Reference: always claude-haiku-5.5 $0.00144, pass 99.17%; always Haiku $0.00144, pass 99.17%; two trials without escalation $0.00289.

### cf3a: inception/mercury-2.5 — 140 runs, 12 failures (base rate 8.6%), 1 of them empty reports; cost/run $0.00087

| variant | score | PR-AUC (AP) | AP / base | AP (non-empty) | best-F1 t | recall | precision | fire rate | recall @ fire ≤10% (precision) |
|---|---|---|---|---|---|---|---|---|---|
| mean9 | words | 0.176 | 2.1× | 0.086 | 0.478 | 67% (8.0/12) | 14% | 42.1% | 8% (100%) |
| mean9 | idents | 0.221 | 2.6× | 0.126 | 0.455 | 75% (9.0/12) | 18% | 35.0% | 8% (100%) |
| mean9 | paths | 0.283 | 3.3× | 0.184 | 0.452 | 58% (7.0/12) | 26% | 19.3% | 17% (29%) |
| mean9 | last | 0.106 | 1.2× | 0.071 | 0.250 | 100% (12.0/12) | 11% | 77.1% | 8% (33%) |
| mean9 | mean | 0.206 | 2.4× | 0.113 | 0.387 | 83% (10.0/12) | 16% | 45.7% | 8% (100%) |
| medoid | words | 0.186 | 2.2× | 0.092 | 0.563 | 83% (10.0/12) | 13% | 54.3% | 8% (100%) |
| medoid | idents | 0.241 | 2.8× | 0.140 | 0.478 | 58% (7.0/12) | 18% | 27.1% | 25% (21%) |
| medoid | paths | 0.253 | 3.0× | 0.213 | 0.333 | 58% (7.0/12) | 35% | 14.3% | 17% (29%) |
| medoid | last | 0.091 | 1.1× | 0.080 | 0.250 | 75% (9.0/12) | 10% | 62.9% | – |
| medoid | mean | 0.245 | 2.9× | 0.140 | 0.374 | 58% (7.0/12) | 18% | 27.9% | 25% (27%) |
| pair1 | words | 0.134 | 1.6× | 0.079 | 0.560 | 84% (10.1/12) | 10% | 70.6% | 12% (12%) |
| pair1 | idents | 0.160 | 1.9× | 0.103 | 0.316 | 40% (4.8/12) | 16% | 21.1% | 16% (14%) |
| pair1 | paths | 0.154 | 1.8× | 0.126 | 0.333 | 56% (6.8/12) | 20% | 23.8% | 18% (17%) |
| pair1 | last | 0.075 | 0.9× | 0.064 | 0.211 | 78% (9.3/12) | 9% | 71.0% | – |
| pair1 | mean | 0.148 | 1.7× | 0.090 | 0.270 | 33% (4.0/12) | 16% | 18.1% | 16% (14%) |

Economics, `pair1` with `idents` (one extra trial of the same model, escalate to Haiku when the pair disagrees; final answer = Haiku's run of the same task/trial). Haiku $0.00154/run. Rows: first threshold reaching each 10% recall step.

| t | fire rate | recall | precision | cascade $/run | cascade pass |
|---|---|---|---|---|---|
| 0.000 | 1.4% | 8% | 50.0% | $0.00177 | 92.14% |
| 0.167 | 7.0% | 10% | 12.5% | $0.00185 | 92.30% |
| 0.235 | 12.2% | 20% | 14.3% | $0.00193 | 93.10% |
| 0.278 | 17.0% | 31% | 15.4% | $0.00201 | 93.89% |
| 0.333 | 23.5% | 41% | 14.9% | $0.00211 | 94.68% |
| 0.389 | 29.8% | 50% | 14.4% | $0.00220 | 95.32% |
| 0.463 | 40.5% | 60% | 12.7% | $0.00237 | 96.19% |
| 0.500 | 49.0% | 74% | 12.9% | $0.00250 | 97.30% |
| 0.588 | 66.7% | 81% | 10.5% | $0.00277 | 97.86% |
| 0.667 | 83.3% | 94% | 9.6% | $0.00303 | 98.89% |
| 0.808 | 96.0% | 100% | 8.9% | $0.00322 | 99.29% |
| 1.000 | 100.0% | 100% | 8.6% | $0.00328 | 99.29% |

Reference: always mercury-2.5 $0.00087, pass 91.43%; always Haiku $0.00154, pass 99.29%; two trials without escalation $0.00174.

### cf3a: stepfun/step-3.5-flash — 140 runs, 6 failures (base rate 4.3%), 4 of them empty reports; cost/run $0.00299

| variant | score | PR-AUC (AP) | AP / base | AP (non-empty) | best-F1 t | recall | precision | fire rate | recall @ fire ≤10% (precision) |
|---|---|---|---|---|---|---|---|---|---|
| mean9 | words | 0.400 | 9.3× | 0.071 | 0.000 | 67% (4.0/6) | 50% | 5.7% | 67% (50%) |
| mean9 | idents | 0.388 | 9.1× | 0.053 | 0.000 | 67% (4.0/6) | 50% | 5.7% | 67% (50%) |
| mean9 | paths | 0.398 | 9.3× | 0.147 | 0.000 | 83% (5.0/6) | 45% | 7.9% | 83% (45%) |
| mean9 | last | 0.320 | 7.5× | 0.085 | 0.000 | 67% (4.0/6) | 36% | 7.9% | 67% (36%) |
| mean9 | mean | 0.419 | 9.8× | 0.100 | 0.000 | 67% (4.0/6) | 50% | 5.7% | 67% (50%) |
| medoid | words | 0.380 | 8.9× | 0.046 | 0.000 | 67% (4.0/6) | 50% | 5.7% | 67% (50%) |
| medoid | idents | 0.405 | 9.4× | 0.078 | 0.000 | 67% (4.0/6) | 50% | 5.7% | 67% (50%) |
| medoid | paths | 0.174 | 4.1× | 0.048 | 0.000 | 83% (5.0/6) | 19% | 19.3% | – |
| medoid | last | 0.121 | 2.8× | 0.041 | 0.062 | 100% (6.0/6) | 14% | 31.4% | – |
| medoid | mean | 0.432 | 10.1× | 0.129 | 0.000 | 67% (4.0/6) | 50% | 5.7% | 83% (38%) |
| pair1 | words | 0.263 | 6.1× | 0.034 | 0.000 | 67% (4.0/6) | 32% | 9.0% | 67% (32%) |
| pair1 | idents | 0.250 | 5.8× | 0.025 | 0.000 | 67% (4.0/6) | 32% | 9.0% | 67% (32%) |
| pair1 | paths | 0.125 | 2.9× | 0.034 | 0.000 | 87% (5.2/6) | 13% | 28.3% | – |
| pair1 | last | 0.091 | 2.1× | 0.023 | 0.045 | 89% (5.3/6) | 9% | 40.3% | – |
| pair1 | mean | 0.268 | 6.3× | 0.040 | 0.000 | 67% (4.0/6) | 32% | 9.0% | 67% (32%) |

Economics, `pair1` with `mean` (one extra trial of the same model, escalate to Haiku when the pair disagrees; final answer = Haiku's run of the same task/trial). Haiku $0.00154/run. Rows: first threshold reaching each 10% recall step.

| t | fire rate | recall | precision | cascade $/run | cascade pass |
|---|---|---|---|---|---|
| 0.000 | 9.0% | 67% | 31.6% | $0.00613 | 98.57% |
| 0.171 | 12.2% | 70% | 24.7% | $0.00617 | 98.73% |
| 0.226 | 19.5% | 81% | 17.9% | $0.00629 | 99.21% |
| 0.255 | 26.0% | 91% | 14.9% | $0.00639 | 99.60% |
| 0.502 | 87.9% | 100% | 4.9% | $0.00734 | 99.52% |
| 0.824 | 100.0% | 100% | 4.3% | $0.00753 | 99.29% |

Reference: always step-3.5-flash $0.00299, pass 95.71%; always Haiku $0.00154, pass 99.29%; two trials without escalation $0.00599.

### cf3a: deepseek/deepseek-v4-flash-0731 — 140 runs, 4 failures (base rate 2.9%), 1 of them empty reports; cost/run $0.00086

| variant | score | PR-AUC (AP) | AP / base | AP (non-empty) | best-F1 t | recall | precision | fire rate | recall @ fire ≤10% (precision) |
|---|---|---|---|---|---|---|---|---|---|
| mean9 | words | 0.322 | 11.3× | 0.065 | 0.000 | 25% (1.0/4) | 100% | 0.7% | 25% (100%) |
| mean9 | idents | 0.314 | 11.0× | 0.055 | 0.000 | 25% (1.0/4) | 100% | 0.7% | 25% (100%) |
| mean9 | paths | 0.289 | 10.1× | 0.035 | 0.000 | 25% (1.0/4) | 100% | 0.7% | 25% (100%) |
| mean9 | last | 0.317 | 11.1× | 0.201 | 0.000 | 50% (2.0/4) | 40% | 3.6% | 75% (23%) |
| mean9 | mean | 0.420 | 14.7× | 0.160 | 0.277 | 100% (4.0/4) | 27% | 10.7% | 75% (21%) |
| medoid | words | 0.317 | 11.1× | 0.056 | 0.000 | 25% (1.0/4) | 100% | 0.7% | 25% (100%) |
| medoid | idents | 0.306 | 10.7× | 0.049 | 0.000 | 25% (1.0/4) | 100% | 0.7% | 25% (100%) |
| medoid | paths | 0.275 | 9.6× | 0.022 | 0.000 | 25% (1.0/4) | 100% | 0.7% | 25% (100%) |
| medoid | last | 0.123 | 4.3× | 0.090 | 0.040 | 100% (4.0/4) | 13% | 21.4% | – |
| medoid | mean | 0.352 | 12.3× | 0.087 | 0.000 | 25% (1.0/4) | 100% | 0.7% | 50% (22%) |
| pair1 | words | 0.266 | 9.3× | 0.069 | 0.000 | 33% (1.3/4) | 67% | 1.4% | 42% (21%) |
| pair1 | idents | 0.258 | 9.0× | 0.064 | 0.000 | 33% (1.3/4) | 67% | 1.4% | 42% (13%) |
| pair1 | paths | 0.246 | 8.6× | 0.058 | 0.000 | 33% (1.3/4) | 67% | 1.4% | 33% (67%) |
| pair1 | last | 0.089 | 3.1× | 0.065 | 0.000 | 89% (3.6/4) | 9% | 27.5% | – |
| pair1 | mean | 0.294 | 10.3× | 0.091 | 0.000 | 33% (1.3/4) | 67% | 1.4% | 42% (37%) |

Economics, `pair1` with `mean` (one extra trial of the same model, escalate to Haiku when the pair disagrees; final answer = Haiku's run of the same task/trial). Haiku $0.00154/run. Rows: first threshold reaching each 10% recall step.

| t | fire rate | recall | precision | cascade $/run | cascade pass |
|---|---|---|---|---|---|
| 0.000 | 1.4% | 33% | 66.7% | $0.00175 | 98.10% |
| 0.182 | 3.2% | 42% | 37.5% | $0.00177 | 98.33% |
| 0.291 | 19.7% | 50% | 7.3% | $0.00203 | 98.33% |
| 0.303 | 23.7% | 61% | 7.4% | $0.00209 | 98.65% |
| 0.321 | 30.2% | 75% | 7.1% | $0.00219 | 98.97% |
| 0.329 | 34.0% | 81% | 6.8% | $0.00225 | 98.97% |
| 0.360 | 49.5% | 92% | 5.3% | $0.00249 | 99.21% |
| 0.370 | 53.5% | 100% | 5.3% | $0.00255 | 99.29% |
| 0.757 | 100.0% | 100% | 2.9% | $0.00326 | 99.29% |

Reference: always deepseek-v4-flash-0731 $0.00086, pass 97.14%; always Haiku $0.00154, pass 99.29%; two trials without escalation $0.00172.

### cf3a: deepseek/deepseek-v4-flash — 140 runs, 4 failures (base rate 2.9%), 0 of them empty reports; cost/run $0.00132

| variant | score | PR-AUC (AP) | AP / base | AP (non-empty) | best-F1 t | recall | precision | fire rate | recall @ fire ≤10% (precision) |
|---|---|---|---|---|---|---|---|---|---|
| mean9 | words | 0.027 | 0.9× | 0.027 | 0.535 | 100% (4.0/4) | 3% | 83.6% | 0% (0%) |
| mean9 | idents | 0.045 | 1.6× | 0.045 | 0.404 | 50% (2.0/4) | 6% | 24.3% | 0% (0%) |
| mean9 | paths | 0.245 | 8.6× | 0.245 | 0.185 | 75% (3.0/4) | 38% | 5.7% | 75% (38%) |
| mean9 | last | 0.104 | 3.6× | 0.104 | 0.012 | 50% (2.0/4) | 17% | 8.6% | 50% (17%) |
| mean9 | mean | 0.047 | 1.6× | 0.047 | 0.267 | 25% (1.0/4) | 6% | 11.4% | 0% (0%) |
| medoid | words | 0.027 | 0.9× | 0.027 | 0.600 | 100% (4.0/4) | 3% | 85.7% | 0% (0%) |
| medoid | idents | 0.055 | 1.9× | 0.055 | 0.556 | 100% (4.0/4) | 7% | 43.6% | 0% (0%) |
| medoid | paths | 0.382 | 13.4× | 0.382 | 0.000 | 75% (3.0/4) | 50% | 4.3% | 75% (50%) |
| medoid | last | 0.063 | 2.2× | 0.063 | 0.000 | 50% (2.0/4) | 8% | 17.9% | – |
| medoid | mean | 0.052 | 1.8× | 0.052 | 0.367 | 75% (3.0/4) | 7% | 32.9% | 0% (0%) |
| pair1 | words | 0.022 | 0.8× | 0.022 | 0.635 | 100% (4.0/4) | 3% | 90.8% | 3% (1%) |
| pair1 | idents | 0.031 | 1.1× | 0.031 | 0.500 | 75% (3.0/4) | 4% | 54.3% | 3% (1%) |
| pair1 | paths | 0.132 | 4.6× | 0.132 | 0.000 | 56% (2.2/4) | 20% | 8.1% | 61% (18%) |
| pair1 | last | 0.038 | 1.3× | 0.038 | 0.059 | 64% (2.6/4) | 4% | 43.3% | – |
| pair1 | mean | 0.030 | 1.0× | 0.030 | 0.379 | 81% (3.2/4) | 4% | 59.8% | 6% (2%) |

Economics, `pair1` with `paths` (one extra trial of the same model, escalate to Haiku when the pair disagrees; final answer = Haiku's run of the same task/trial). Haiku $0.00154/run. Rows: first threshold reaching each 10% recall step.

| t | fire rate | recall | precision | cascade $/run | cascade pass |
|---|---|---|---|---|---|
| 0.000 | 8.1% | 56% | 19.6% | $0.00276 | 98.73% |
| 0.167 | 9.8% | 61% | 17.7% | $0.00279 | 98.89% |
| 1.000 | 100.0% | 100% | 2.9% | $0.00418 | 99.29% |

Reference: always deepseek-v4-flash $0.00132, pass 97.14%; always Haiku $0.00154, pass 99.29%; two trials without escalation $0.00264.

### cf3a: deepseek/deepseek-v4-flash#off — 140 runs, 4 failures (base rate 2.9%), 0 of them empty reports; cost/run $0.00113

| variant | score | PR-AUC (AP) | AP / base | AP (non-empty) | best-F1 t | recall | precision | fire rate | recall @ fire ≤10% (precision) |
|---|---|---|---|---|---|---|---|---|---|
| mean9 | words | 0.036 | 1.3× | 0.036 | 0.320 | 25% (1.0/4) | 6% | 12.1% | 0% (0%) |
| mean9 | idents | 0.048 | 1.7× | 0.048 | 0.236 | 25% (1.0/4) | 7% | 10.7% | 0% (0%) |
| mean9 | paths | 0.416 | 14.6× | 0.416 | 0.265 | 75% (3.0/4) | 33% | 6.4% | 75% (33%) |
| mean9 | last | 0.040 | 1.4× | 0.040 | 0.279 | 100% (4.0/4) | 5% | 60.7% | 0% (0%) |
| mean9 | mean | 0.045 | 1.6× | 0.045 | 0.229 | 25% (1.0/4) | 7% | 10.7% | 0% (0%) |
| medoid | words | 0.034 | 1.2× | 0.034 | 0.359 | 25% (1.0/4) | 5% | 14.3% | 0% (0%) |
| medoid | idents | 0.054 | 1.9× | 0.054 | 0.263 | 25% (1.0/4) | 8% | 9.3% | 25% (8%) |
| medoid | paths | 0.215 | 7.5× | 0.215 | 0.000 | 50% (2.0/4) | 33% | 4.3% | 50% (33%) |
| medoid | last | 0.052 | 1.8× | 0.052 | 0.000 | 25% (1.0/4) | 6% | 11.4% | – |
| medoid | mean | 0.053 | 1.8× | 0.053 | 0.274 | 25% (1.0/4) | 7% | 10.0% | 25% (7%) |
| pair1 | words | 0.025 | 0.9× | 0.025 | 0.714 | 100% (4.0/4) | 3% | 94.8% | 6% (2%) |
| pair1 | idents | 0.034 | 1.2× | 0.034 | 0.278 | 25% (1.0/4) | 4% | 15.9% | 8% (3%) |
| pair1 | paths | 0.108 | 3.8× | 0.108 | 0.000 | 39% (1.6/4) | 15% | 7.3% | 42% (15%) |
| pair1 | last | 0.031 | 1.1× | 0.031 | 0.353 | 89% (3.6/4) | 4% | 67.0% | – |
| pair1 | mean | 0.032 | 1.1× | 0.032 | 0.528 | 94% (3.8/4) | 3% | 79.2% | 8% (3%) |

Economics, `pair1` with `paths` (one extra trial of the same model, escalate to Haiku when the pair disagrees; final answer = Haiku's run of the same task/trial). Haiku $0.00154/run. Rows: first threshold reaching each 10% recall step.

| t | fire rate | recall | precision | cascade $/run | cascade pass |
|---|---|---|---|---|---|
| 0.000 | 7.3% | 39% | 15.2% | $0.00238 | 98.25% |
| 0.091 | 8.1% | 42% | 14.7% | $0.00239 | 98.33% |
| 0.200 | 14.4% | 58% | 11.5% | $0.00249 | 98.81% |
| 0.250 | 15.7% | 61% | 11.1% | $0.00251 | 98.89% |
| 0.333 | 21.3% | 72% | 9.7% | $0.00259 | 99.13% |
| 0.667 | 41.4% | 81% | 5.6% | $0.00290 | 99.05% |
| 1.000 | 100.0% | 100% | 2.9% | $0.00380 | 99.29% |

Reference: always deepseek-v4-flash#off $0.00113, pass 97.14%; always Haiku $0.00154, pass 99.29%; two trials without escalation $0.00226.

### cf3a: inception/mercury-3 — 140 runs, 4 failures (base rate 2.9%), 0 of them empty reports; cost/run $0.00137

| variant | score | PR-AUC (AP) | AP / base | AP (non-empty) | best-F1 t | recall | precision | fire rate | recall @ fire ≤10% (precision) |
|---|---|---|---|---|---|---|---|---|---|
| mean9 | words | 0.092 | 3.2× | 0.092 | 0.419 | 100% (4.0/4) | 12% | 23.6% | 25% (8%) |
| mean9 | idents | 0.081 | 2.8× | 0.081 | 0.441 | 100% (4.0/4) | 11% | 25.0% | 0% (0%) |
| mean9 | paths | 0.043 | 1.5× | 0.043 | 0.872 | 100% (4.0/4) | 4% | 66.4% | 0% (0%) |
| mean9 | last | 0.155 | 5.4× | 0.155 | 0.029 | 75% (3.0/4) | 21% | 10.0% | 75% (21%) |
| mean9 | mean | 0.135 | 4.7× | 0.135 | 0.295 | 100% (4.0/4) | 17% | 17.1% | 25% (9%) |
| medoid | words | 0.092 | 3.2× | 0.092 | 0.419 | 50% (2.0/4) | 14% | 10.0% | 50% (14%) |
| medoid | idents | 0.062 | 2.2× | 0.062 | 0.521 | 75% (3.0/4) | 7% | 30.0% | 0% (0%) |
| medoid | paths | 0.034 | 1.2× | 0.034 | 0.600 | 25% (1.0/4) | 4% | 17.1% | 0% (0%) |
| medoid | last | 0.072 | 2.5× | 0.072 | 0.083 | 100% (4.0/4) | 9% | 33.6% | – |
| medoid | mean | 0.104 | 3.6× | 0.104 | 0.291 | 50% (2.0/4) | 13% | 10.7% | 25% (8%) |
| pair1 | words | 0.092 | 3.2× | 0.092 | 0.239 | 11% (0.4/4) | 29% | 1.1% | 22% (6%) |
| pair1 | idents | 0.053 | 1.8× | 0.053 | 0.480 | 86% (3.4/4) | 6% | 37.9% | 11% (4%) |
| pair1 | paths | 0.030 | 1.1× | 0.030 | 0.600 | 42% (1.7/4) | 4% | 29.8% | 0% (0%) |
| pair1 | last | 0.053 | 1.9× | 0.053 | 0.043 | 75% (3.0/4) | 6% | 34.3% | – |
| pair1 | mean | 0.100 | 3.5× | 0.100 | 0.272 | 50% (2.0/4) | 11% | 12.9% | 19% (7%) |

Economics, `pair1` with `mean` (one extra trial of the same model, escalate to Haiku when the pair disagrees; final answer = Haiku's run of the same task/trial). Haiku $0.00154/run. Rows: first threshold reaching each 10% recall step.

| t | fire rate | recall | precision | cascade $/run | cascade pass |
|---|---|---|---|---|---|
| 0.135 | 0.2% | 3% | 50.0% | $0.00274 | 97.22% |
| 0.200 | 3.3% | 11% | 9.5% | $0.00279 | 97.46% |
| 0.253 | 10.5% | 22% | 6.1% | $0.00290 | 97.78% |
| 0.264 | 11.6% | 33% | 8.2% | $0.00292 | 98.10% |
| 0.270 | 12.4% | 42% | 9.6% | $0.00293 | 98.33% |
| 0.272 | 12.9% | 50% | 11.1% | $0.00293 | 98.57% |
| 0.299 | 19.2% | 61% | 9.1% | $0.00303 | 98.89% |
| 0.315 | 23.0% | 75% | 9.3% | $0.00309 | 99.29% |
| 0.329 | 27.9% | 83% | 8.5% | $0.00317 | 99.52% |
| 0.349 | 33.7% | 92% | 7.8% | $0.00325 | 99.76% |
| 0.416 | 57.3% | 100% | 5.0% | $0.00362 | 99.92% |
| 0.816 | 100.0% | 100% | 2.9% | $0.00428 | 99.29% |

Reference: always mercury-3 $0.00137, pass 97.14%; always Haiku $0.00154, pass 99.29%; two trials without escalation $0.00274.

### cf3a: deepseek/deepseek-v4.1-flash — 140 runs, 2 failures (base rate 1.4%), 0 of them empty reports; cost/run $0.00239

| variant | score | PR-AUC (AP) | AP / base | AP (non-empty) | best-F1 t | recall | precision | fire rate | recall @ fire ≤10% (precision) |
|---|---|---|---|---|---|---|---|---|---|
| mean9 | words | 0.025 | 1.7× | 0.025 | 0.350 | 50% (1.0/2) | 3% | 22.1% | 0% (0%) |
| mean9 | idents | 0.043 | 3.0× | 0.043 | 0.285 | 50% (1.0/2) | 7% | 10.7% | 0% (0%) |
| mean9 | paths | 0.026 | 1.8× | 0.026 | 0.456 | 50% (1.0/2) | 4% | 19.3% | 0% (0%) |
| mean9 | last | 0.012 | 0.8× | 0.012 | 0.213 | 100% (2.0/2) | 2% | 90.7% | 0% (0%) |
| mean9 | mean | 0.020 | 1.4× | 0.020 | 0.283 | 50% (1.0/2) | 2% | 30.7% | 0% (0%) |
| medoid | words | 0.046 | 3.2× | 0.046 | 0.345 | 50% (1.0/2) | 8% | 9.3% | 50% (8%) |
| medoid | idents | 0.048 | 3.4× | 0.048 | 0.307 | 50% (1.0/2) | 8% | 9.3% | 50% (8%) |
| medoid | paths | 0.014 | 1.0× | 0.014 | 0.750 | 50% (1.0/2) | 1% | 48.6% | 0% (0%) |
| medoid | last | 0.013 | 0.9× | 0.013 | 0.310 | 100% (2.0/2) | 2% | 86.4% | – |
| medoid | mean | 0.015 | 1.1× | 0.015 | 0.467 | 100% (2.0/2) | 2% | 88.6% | 0% (0%) |
| pair1 | words | 0.017 | 1.2× | 0.017 | 0.362 | 44% (0.9/2) | 2% | 29.8% | 11% (2%) |
| pair1 | idents | 0.022 | 1.6× | 0.022 | 0.314 | 50% (1.0/2) | 4% | 17.1% | 17% (3%) |
| pair1 | paths | 0.017 | 1.2× | 0.017 | 0.375 | 22% (0.4/2) | 2% | 13.5% | 0% (0%) |
| pair1 | last | 0.009 | 0.6× | 0.009 | 0.409 | 100% (2.0/2) | 1% | 96.5% | – |
| pair1 | mean | 0.012 | 0.9× | 0.012 | 0.231 | 17% (0.3/2) | 2% | 13.3% | 0% (0%) |

Economics, `pair1` with `idents` (one extra trial of the same model, escalate to Haiku when the pair disagrees; final answer = Haiku's run of the same task/trial). Haiku $0.00154/run. Rows: first threshold reaching each 10% recall step.

| t | fire rate | recall | precision | cascade $/run | cascade pass |
|---|---|---|---|---|---|
| 0.127 | 0.2% | 0% | 0.0% | $0.00478 | 98.57% |
| 0.259 | 8.7% | 11% | 1.8% | $0.00492 | 98.73% |
| 0.288 | 12.9% | 22% | 2.5% | $0.00498 | 98.89% |
| 0.300 | 14.4% | 33% | 3.3% | $0.00500 | 99.05% |
| 0.307 | 15.7% | 44% | 4.0% | $0.00502 | 99.21% |
| 0.314 | 17.1% | 50% | 4.2% | $0.00504 | 99.29% |
| 0.532 | 66.2% | 67% | 1.4% | $0.00580 | 99.52% |
| 0.545 | 69.7% | 72% | 1.5% | $0.00585 | 99.52% |
| 0.558 | 72.1% | 83% | 1.7% | $0.00589 | 99.68% |
| 0.625 | 85.9% | 94% | 1.6% | $0.00610 | 99.76% |
| 0.641 | 87.8% | 100% | 1.6% | $0.00613 | 99.68% |
| 0.836 | 100.0% | 100% | 1.4% | $0.00632 | 99.29% |

Reference: always deepseek-v4.1-flash $0.00239, pass 98.57%; always Haiku $0.00154, pass 99.29%; two trials without escalation $0.00478.

### cf3a: poolside/laguna-s-2.1#off — 140 runs, 2 failures (base rate 1.4%), 0 of them empty reports; cost/run $0.00112

| variant | score | PR-AUC (AP) | AP / base | AP (non-empty) | best-F1 t | recall | precision | fire rate | recall @ fire ≤10% (precision) |
|---|---|---|---|---|---|---|---|---|---|
| mean9 | words | 0.033 | 2.3× | 0.033 | 0.427 | 100% (2.0/2) | 4% | 36.4% | 0% (0%) |
| mean9 | idents | 0.040 | 2.8× | 0.040 | 0.407 | 100% (2.0/2) | 5% | 27.1% | 0% (0%) |
| mean9 | paths | 0.023 | 1.6× | 0.023 | 0.548 | 50% (1.0/2) | 2% | 29.3% | 0% (0%) |
| mean9 | last | 0.096 | 6.7× | 0.096 | 0.013 | 50% (1.0/2) | 14% | 5.0% | 50% (14%) |
| mean9 | mean | 0.063 | 4.4× | 0.063 | 0.301 | 100% (2.0/2) | 7% | 21.4% | 0% (0%) |
| medoid | words | 0.037 | 2.6× | 0.037 | 0.458 | 100% (2.0/2) | 4% | 35.0% | 0% (0%) |
| medoid | idents | 0.041 | 2.9× | 0.041 | 0.444 | 100% (2.0/2) | 5% | 27.9% | 0% (0%) |
| medoid | paths | 0.019 | 1.3× | 0.019 | 0.600 | 50% (1.0/2) | 2% | 30.0% | 0% (0%) |
| medoid | last | 0.025 | 1.7× | 0.025 | 0.161 | 100% (2.0/2) | 3% | 49.3% | – |
| medoid | mean | 0.042 | 3.0× | 0.042 | 0.349 | 100% (2.0/2) | 5% | 30.7% | 0% (0%) |
| pair1 | words | 0.018 | 1.3× | 0.018 | 0.460 | 100% (2.0/2) | 2% | 57.6% | 0% (0%) |
| pair1 | idents | 0.020 | 1.4× | 0.020 | 0.432 | 78% (1.6/2) | 3% | 39.8% | 0% (0%) |
| pair1 | paths | 0.016 | 1.1× | 0.016 | 0.600 | 61% (1.2/2) | 2% | 43.2% | 0% (0%) |
| pair1 | last | 0.023 | 1.6× | 0.023 | 0.040 | 67% (1.3/2) | 3% | 37.3% | – |
| pair1 | mean | 0.027 | 1.9× | 0.027 | 0.282 | 56% (1.1/2) | 3% | 24.0% | 11% (2%) |

Economics, `pair1` with `mean` (one extra trial of the same model, escalate to Haiku when the pair disagrees; final answer = Haiku's run of the same task/trial). Haiku $0.00154/run. Rows: first threshold reaching each 10% recall step.

| t | fire rate | recall | precision | cascade $/run | cascade pass |
|---|---|---|---|---|---|
| 0.145 | 0.2% | 0% | 0.0% | $0.00223 | 98.57% |
| 0.235 | 8.4% | 11% | 1.9% | $0.00236 | 98.73% |
| 0.251 | 12.4% | 22% | 2.6% | $0.00242 | 98.89% |
| 0.271 | 17.9% | 33% | 2.7% | $0.00251 | 99.05% |
| 0.276 | 20.6% | 44% | 3.1% | $0.00255 | 99.21% |
| 0.279 | 22.9% | 50% | 3.1% | $0.00258 | 99.29% |
| 0.291 | 27.0% | 61% | 3.2% | $0.00265 | 99.44% |
| 0.308 | 36.2% | 72% | 2.9% | $0.00279 | 99.60% |
| 0.322 | 40.2% | 83% | 3.0% | $0.00285 | 99.76% |
| 0.343 | 50.0% | 94% | 2.7% | $0.00300 | 99.92% |
| 0.349 | 52.4% | 100% | 2.7% | $0.00304 | 100.00% |
| 0.773 | 100.0% | 100% | 1.4% | $0.00377 | 99.29% |

Reference: always laguna-s-2.1#off $0.00112, pass 98.57%; always Haiku $0.00154, pass 99.29%; two trials without escalation $0.00223.

### cf3a: anthropic/claude-haiku-5.5 — 140 runs, 1 failures (base rate 0.7%), 0 of them empty reports; cost/run $0.00154

| variant | score | PR-AUC (AP) | AP / base | AP (non-empty) | best-F1 t | recall | precision | fire rate | recall @ fire ≤10% (precision) |
|---|---|---|---|---|---|---|---|---|---|
| mean9 | words | 0.015 | 2.1× | 0.015 | 0.484 | 100% (1.0/1) | 2% | 47.1% | 0% (0%) |
| mean9 | idents | 0.019 | 2.6× | 0.019 | 0.571 | 100% (1.0/1) | 2% | 37.9% | 0% (0%) |
| mean9 | paths | 0.010 | 1.4× | 0.010 | 0.978 | 100% (1.0/1) | 1% | 71.4% | 0% (0%) |
| mean9 | last | 0.011 | 1.6× | 0.011 | 0.131 | 100% (1.0/1) | 1% | 62.9% | – |
| mean9 | mean | 0.016 | 2.3× | 0.016 | 0.395 | 100% (1.0/1) | 2% | 44.3% | 0% (0%) |
| medoid | words | 0.021 | 2.9× | 0.021 | 0.491 | 100% (1.0/1) | 2% | 34.3% | 0% (0%) |
| medoid | idents | 0.024 | 3.3× | 0.024 | 0.586 | 100% (1.0/1) | 2% | 30.0% | 0% (0%) |
| medoid | paths | 0.007 | 1.0× | 0.007 | 1.000 | 100% (1.0/1) | 1% | 100.0% | 0% (0%) |
| medoid | last | 0.013 | 1.8× | 0.013 | 0.158 | 100% (1.0/1) | 1% | 57.1% | – |
| medoid | mean | 0.014 | 2.0× | 0.014 | 0.444 | 100% (1.0/1) | 1% | 49.3% | 0% (0%) |
| pair1 | words | 0.008 | 1.1× | 0.008 | 0.519 | 89% (0.9/1) | 1% | 61.7% | 0% (0%) |
| pair1 | idents | 0.010 | 1.5× | 0.010 | 0.586 | 89% (0.9/1) | 1% | 44.4% | 0% (0%) |
| pair1 | paths | 0.007 | 0.9× | 0.007 | 1.000 | 100% (1.0/1) | 1% | 100.0% | 0% (0%) |
| pair1 | last | 0.005 | 0.8× | 0.005 | 0.222 | 100% (1.0/1) | 1% | 83.5% | – |
| pair1 | mean | 0.007 | 1.0× | 0.007 | 0.444 | 100% (1.0/1) | 1% | 70.2% | 0% (0%) |

Economics, `pair1` with `idents` (one extra trial of the same model, escalate to Haiku when the pair disagrees; final answer = Haiku's run of the same task/trial). Haiku $0.00154/run. Rows: first threshold reaching each 10% recall step.

| t | fire rate | recall | precision | cascade $/run | cascade pass |
|---|---|---|---|---|---|
| 0.188 | 0.2% | 0% | 0.0% | $0.00308 | 99.29% |
| 0.484 | 24.3% | 11% | 0.3% | $0.00345 | 99.29% |
| 0.548 | 36.2% | 22% | 0.4% | $0.00364 | 99.29% |
| 0.567 | 39.8% | 44% | 0.8% | $0.00369 | 99.29% |
| 0.586 | 44.4% | 89% | 1.4% | $0.00376 | 99.29% |
| 0.630 | 55.4% | 100% | 1.3% | $0.00393 | 99.29% |
| 1.000 | 100.0% | 100% | 0.7% | $0.00462 | 99.29% |

Reference: always claude-haiku-5.5 $0.00154, pass 99.29%; always Haiku $0.00154, pass 99.29%; two trials without escalation $0.00308.

### cf3a: anthropic/claude-haiku-5.5#off — 140 runs, 1 failures (base rate 0.7%), 0 of them empty reports; cost/run $0.00130

| variant | score | PR-AUC (AP) | AP / base | AP (non-empty) | best-F1 t | recall | precision | fire rate | recall @ fire ≤10% (precision) |
|---|---|---|---|---|---|---|---|---|---|
| mean9 | words | 0.018 | 2.5× | 0.018 | 0.474 | 100% (1.0/1) | 2% | 40.7% | 0% (0%) |
| mean9 | idents | 0.015 | 2.1× | 0.015 | 0.594 | 100% (1.0/1) | 2% | 47.1% | 0% (0%) |
| mean9 | paths | 0.007 | 1.0× | 0.007 | 1.000 | 100% (1.0/1) | 1% | 100.0% | 0% (0%) |
| mean9 | last | 0.009 | 1.3× | 0.009 | 0.199 | 100% (1.0/1) | 1% | 78.6% | 0% (0%) |
| mean9 | mean | 0.012 | 1.6× | 0.012 | 0.422 | 100% (1.0/1) | 1% | 61.4% | 0% (0%) |
| medoid | words | 0.028 | 3.9× | 0.028 | 0.475 | 100% (1.0/1) | 3% | 25.7% | 0% (0%) |
| medoid | idents | 0.019 | 2.6× | 0.019 | 0.607 | 100% (1.0/1) | 2% | 37.9% | 0% (0%) |
| medoid | paths | 0.007 | 1.0× | 0.007 | 1.000 | 100% (1.0/1) | 1% | 100.0% | 0% (0%) |
| medoid | last | 0.008 | 1.1× | 0.008 | 0.833 | 100% (1.0/1) | 1% | 92.1% | – |
| medoid | mean | 0.008 | 1.1× | 0.008 | 0.679 | 100% (1.0/1) | 1% | 91.4% | 0% (0%) |
| pair1 | words | 0.009 | 1.3× | 0.009 | 0.484 | 89% (0.9/1) | 1% | 46.5% | 0% (0%) |
| pair1 | idents | 0.007 | 1.0× | 0.007 | 0.630 | 89% (0.9/1) | 1% | 62.4% | 0% (0%) |
| pair1 | paths | 0.007 | 1.0× | 0.007 | 1.000 | 100% (1.0/1) | 1% | 100.0% | 0% (0%) |
| pair1 | last | 0.005 | 0.8× | 0.005 | 0.250 | 89% (0.9/1) | 1% | 84.6% | – |
| pair1 | mean | 0.007 | 0.9× | 0.007 | 0.435 | 89% (0.9/1) | 1% | 70.2% | 0% (0%) |

Economics, `pair1` with `words` (one extra trial of the same model, escalate to Haiku when the pair disagrees; final answer = Haiku's run of the same task/trial). Haiku $0.00154/run. Rows: first threshold reaching each 10% recall step.

| t | fire rate | recall | precision | cascade $/run | cascade pass |
|---|---|---|---|---|---|
| 0.296 | 0.2% | 0% | 0.0% | $0.00260 | 99.29% |
| 0.426 | 24.6% | 11% | 0.3% | $0.00298 | 99.21% |
| 0.446 | 31.0% | 22% | 0.5% | $0.00308 | 99.29% |
| 0.446 | 31.4% | 33% | 0.8% | $0.00308 | 99.37% |
| 0.448 | 31.9% | 44% | 1.0% | $0.00309 | 99.44% |
| 0.464 | 38.1% | 56% | 1.0% | $0.00319 | 99.52% |
| 0.475 | 42.7% | 67% | 1.1% | $0.00326 | 99.60% |
| 0.483 | 46.2% | 78% | 1.2% | $0.00331 | 99.60% |
| 0.484 | 46.5% | 89% | 1.4% | $0.00331 | 99.68% |
| 0.596 | 84.4% | 100% | 0.8% | $0.00390 | 99.29% |
| 0.780 | 100.0% | 100% | 0.7% | $0.00414 | 99.29% |

Reference: always claude-haiku-5.5#off $0.00130, pass 99.29%; always Haiku $0.00154, pass 99.29%; two trials without escalation $0.00260.

### cf3a: deepseek/deepseek-v4-flash-0731#off — 140 runs, 1 failures (base rate 0.7%), 0 of them empty reports; cost/run $0.00068

| variant | score | PR-AUC (AP) | AP / base | AP (non-empty) | best-F1 t | recall | precision | fire rate | recall @ fire ≤10% (precision) |
|---|---|---|---|---|---|---|---|---|---|
| mean9 | words | 1.000 | 140.0× | 1.000 | 0.139 | 100% (1.0/1) | 100% | 0.7% | 100% (100%) |
| mean9 | idents | 0.500 | 70.0× | 0.500 | 0.161 | 100% (1.0/1) | 50% | 1.4% | 100% (50%) |
| mean9 | paths | 0.250 | 35.0× | 0.250 | 0.139 | 100% (1.0/1) | 25% | 2.9% | 100% (25%) |
| mean9 | last | 0.125 | 17.5× | 0.125 | 0.016 | 100% (1.0/1) | 12% | 5.7% | 100% (12%) |
| mean9 | mean | 0.500 | 70.0× | 0.500 | 0.106 | 100% (1.0/1) | 50% | 1.4% | 100% (50%) |
| medoid | words | 1.000 | 140.0× | 1.000 | 0.133 | 100% (1.0/1) | 100% | 0.7% | 100% (100%) |
| medoid | idents | 0.333 | 46.7× | 0.333 | 0.179 | 100% (1.0/1) | 33% | 2.1% | 100% (33%) |
| medoid | paths | 0.200 | 28.0× | 0.200 | 0.143 | 100% (1.0/1) | 20% | 3.6% | 100% (20%) |
| medoid | last | 0.034 | 4.8× | 0.034 | 0.034 | 100% (1.0/1) | 3% | 20.7% | – |
| medoid | mean | 0.500 | 70.0× | 0.500 | 0.116 | 100% (1.0/1) | 50% | 1.4% | 100% (50%) |
| pair1 | words | 0.390 | 54.7× | 0.390 | 0.178 | 100% (1.0/1) | 32% | 2.2% | 100% (32%) |
| pair1 | idents | 0.146 | 20.4× | 0.146 | 0.180 | 89% (0.9/1) | 13% | 4.9% | 100% (7%) |
| pair1 | paths | 0.068 | 9.5× | 0.068 | 0.143 | 89% (0.9/1) | 9% | 7.3% | 100% (7%) |
| pair1 | last | 0.015 | 2.1× | 0.015 | 0.034 | 89% (0.9/1) | 2% | 34.3% | – |
| pair1 | mean | 0.231 | 32.4× | 0.231 | 0.150 | 100% (1.0/1) | 26% | 2.7% | 100% (26%) |

Economics, `pair1` with `words` (one extra trial of the same model, escalate to Haiku when the pair disagrees; final answer = Haiku's run of the same task/trial). Haiku $0.00154/run. Rows: first threshold reaching each 10% recall step.

| t | fire rate | recall | precision | cascade $/run | cascade pass |
|---|---|---|---|---|---|
| 0.112 | 0.2% | 11% | 50.0% | $0.00137 | 99.37% |
| 0.115 | 0.3% | 22% | 50.0% | $0.00137 | 99.44% |
| 0.127 | 0.6% | 33% | 37.5% | $0.00137 | 99.52% |
| 0.133 | 0.8% | 44% | 40.0% | $0.00138 | 99.60% |
| 0.133 | 1.0% | 56% | 41.7% | $0.00138 | 99.68% |
| 0.134 | 1.3% | 67% | 37.5% | $0.00138 | 99.76% |
| 0.148 | 1.7% | 78% | 31.8% | $0.00139 | 99.84% |
| 0.171 | 2.1% | 89% | 30.8% | $0.00139 | 99.92% |
| 0.178 | 2.2% | 100% | 32.1% | $0.00140 | 100.00% |
| 0.844 | 100.0% | 100% | 0.7% | $0.00290 | 99.29% |

Reference: always deepseek-v4-flash-0731#off $0.00068, pass 99.29%; always Haiku $0.00154, pass 99.29%; two trials without escalation $0.00136.

### cf3a: inclusionai/ling-3.0-flash — 140 runs, 1 failures (base rate 0.7%), 0 of them empty reports; cost/run $0.00031

| variant | score | PR-AUC (AP) | AP / base | AP (non-empty) | best-F1 t | recall | precision | fire rate | recall @ fire ≤10% (precision) |
|---|---|---|---|---|---|---|---|---|---|
| mean9 | words | 0.019 | 2.6× | 0.019 | 0.472 | 100% (1.0/1) | 2% | 38.6% | 0% (0%) |
| mean9 | idents | 0.013 | 1.8× | 0.013 | 0.506 | 100% (1.0/1) | 1% | 57.1% | 0% (0%) |
| mean9 | paths | 0.019 | 2.6× | 0.019 | 0.570 | 100% (1.0/1) | 2% | 38.6% | 0% (0%) |
| mean9 | last | 0.500 | 70.0× | 1.000 | 0.009 | 100% (1.0/1) | 50% | 1.4% | 100% (50%) |
| mean9 | mean | 0.043 | 6.1× | 0.045 | 0.329 | 100% (1.0/1) | 4% | 16.4% | 0% (0%) |
| medoid | words | 0.019 | 2.6× | 0.019 | 0.556 | 100% (1.0/1) | 2% | 38.6% | 0% (0%) |
| medoid | idents | 0.011 | 1.5× | 0.011 | 0.688 | 100% (1.0/1) | 1% | 65.0% | 0% (0%) |
| medoid | paths | 0.020 | 2.8× | 0.020 | 0.667 | 100% (1.0/1) | 2% | 35.7% | – |
| medoid | last | 0.071 | 10.0× | 0.077 | 0.000 | 100% (1.0/1) | 7% | 10.0% | 100% (7%) |
| medoid | mean | 0.062 | 8.8× | 0.067 | 0.306 | 100% (1.0/1) | 6% | 11.4% | 0% (0%) |
| pair1 | words | 0.009 | 1.3× | 0.009 | 0.517 | 89% (0.9/1) | 1% | 51.7% | 0% (0%) |
| pair1 | idents | 0.007 | 1.0× | 0.007 | 0.533 | 78% (0.8/1) | 1% | 55.9% | 0% (0%) |
| pair1 | paths | 0.013 | 1.8× | 0.013 | 0.667 | 100% (1.0/1) | 2% | 43.3% | – |
| pair1 | last | 0.034 | 4.7× | 0.035 | 0.000 | 89% (0.9/1) | 3% | 18.4% | – |
| pair1 | mean | 0.014 | 2.0× | 0.015 | 0.354 | 89% (0.9/1) | 2% | 31.1% | 0% (0%) |

Economics, `pair1` with `last` (one extra trial of the same model, escalate to Haiku when the pair disagrees; final answer = Haiku's run of the same task/trial). Haiku $0.00154/run. Rows: first threshold reaching each 10% recall step.

| t | fire rate | recall | precision | cascade $/run | cascade pass |
|---|---|---|---|---|---|
| 0.000 | 18.4% | 89% | 3.4% | $0.00090 | 99.84% |
| 0.077 | 25.7% | 100% | 2.8% | $0.00101 | 99.92% |
| 1.000 | 100.0% | 100% | 0.7% | $0.00216 | 99.29% |

Reference: always ling-3.0-flash $0.00031, pass 99.29%; always Haiku $0.00154, pass 99.29%; two trials without escalation $0.00062.

## E3. Where the money goes inside a run

Per run, from `runRecord.totals.listPrice` (component split) and the transcript's per-request `meta.usage` (request 0 = the first request, whose prompt is the fixed overhead: system prompt + tool schemas + skills listing + task). Shares are means of per-run shares (each run weighted equally). (a) cuts across (b)–(e); (b)+(c)+(d)+(e) = 100% (the stored `reasoning` component is a part of `output`, not added to it). The cf6 deepseek list price is inflated ~6× (its stored unit prices are not the provider's), so its shares are indicative only; charged is shown for reference.

| store | model | runs | mean steps (requests) | mean list $/run | mean charged $/run | (a) first request | (b) cache reads | (c) uncached prompt | (d) cache writes | (e) output (incl. reasoning) | first-request prompt tok, median (explore / general agent) | of which cached from earlier runs (median) | first-request prompt / all prompt tokens | cached / all prompt tokens |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| cf6 | inclusionai/ling-3.0-flash | 479 | 4.0 | $0.00025 | $0.00025 | 36.1% | 17.8% | 57.6% | 0.0% | 24.7% | 1,754 (1,746 / 4,954) | 384 | 27.0% | 55.3% |
| cf6 | deepseek/deepseek-v4-flash-0731#off | 480 | 4.6 | $0.00285 | $0.00183 | 29.7% | 3.5% | 72.1% | 0.0% | 24.3% | 1,716 (1,703 / 4,841) | 256 | 24.7% | 50.1% |
| cf6 | anthropic/claude-haiku-5.5 | 480 | 3.4 | $0.00144 | $0.00144 | 45.8% | 8.0% | 0.1% | 54.4% | 37.6% | 2,306 (2,295 / 6,746) | 0 | 27.8% | 61.0% |
| cf3a | inclusionai/ling-3.0-flash | 140 | 5.5 | $0.00031 | $0.00031 | 21.0% | 16.7% | 46.3% | 0.0% | 37.0% | 1,736 (1,334 / 2,176) | 320 | 17.4% | 56.1% |
| cf3a | deepseek/deepseek-v4-flash-0731#off | 140 | 4.7 | $0.00068 | $0.00069 | 20.2% | 28.2% | 42.7% | 0.0% | 29.2% | 1,643 (1,294 / 2,064) | 256 | 17.9% | 46.9% |
| cf3a | anthropic/claude-haiku-5.5 | 140 | 3.9 | $0.00154 | $0.00154 | 29.3% | 6.7% | 0.1% | 44.0% | 49.3% | 2,258 (1,747 / 2,815) | 0 | 20.0% | 63.4% |
| cf3a | inception/mercury-2.5 | 140 | 6.7 | $0.00087 | $0.00087 | 19.0% | 1.3% | 70.4% | 0.0% | 28.3% | 1,657 (1,290 / 2,074) | 0 | 15.8% | 13.0% |
| cf3b | anthropic/claude-opus-5.5 | 42 | 3.7 | $0.04582 | $0.04582 | 32.7% | 3.7% | 0.1% | 48.6% | 47.6% | 2,258 (1,746 / 2,815) | 0 | 21.6% | 64.2% |
| cf3b | anthropic/claude-sonnet-5.5 | 42 | 3.5 | $0.02286 | $0.02286 | 34.3% | 3.7% | 0.1% | 51.1% | 45.1% | 2,258 (1,747 / 2,816) | 0 | 22.0% | 62.7% |
| cf3b | google/gemini-4-argon | 42 | 4.7 | $0.03488 | $0.03488 | 16.2% | 0.4% | 71.9% | 0.0% | 27.6% | 1,491 (1,117 / 1,905) | 0 | 18.6% | 7.4% |
| bank1 | gemini-4-argon | 102 | 3.6 | $0.02066 | – | 21.4% | 0.2% | 73.3% | 0.0% | 26.4% | 1,106 (1,100 / 1,878) | 0 | 24.6% | 4.2% |

### Cache-read share of each request's prompt, by request index (mean over runs that reached that index; n in parentheses)

| store | model | req 0 | req 1 | req 2 | req 3 | req 4 | req 5 | req 6 | req 7 | req 8 | req 9 | req 10 | req 12 | req 15 | req 20 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| cf6 | inclusionai/ling-3.0-flash | 16% (479) | 64% (479) | 67% (353) | 77% (199) | 88% (145) | 92% (86) | 96% (38) | 94% (31) | 87% (26) | 94% (20) | 97% (12) | 95% (5) | 95% (1) | 94% (1) |
| cf6 | deepseek/deepseek-v4-flash-0731#off | 20% (480) | 52% (480) | 59% (407) | 68% (240) | 75% (145) | 78% (98) | 82% (60) | 75% (44) | 86% (36) | 81% (31) | 88% (27) | 95% (21) | 97% (15) | 96% (5) |
| cf6 | anthropic/claude-haiku-5.5 | 0% (480) | 88% (480) | 83% (391) | 86% (162) | 93% (85) | 94% (37) | 95% (8) | 93% (1) | 96% (1) | – | – | – | – | – |
| cf3a | inclusionai/ling-3.0-flash | 18% (140) | 55% (140) | 63% (133) | 70% (82) | 81% (60) | 85% (36) | 91% (26) | 95% (21) | 87% (19) | 90% (18) | 89% (16) | 92% (12) | 95% (7) | 98% (1) |
| cf3a | deepseek/deepseek-v4-flash-0731#off | 15% (140) | 44% (140) | 49% (140) | 63% (92) | 77% (57) | 83% (31) | 88% (16) | 91% (12) | 96% (9) | 95% (5) | 65% (3) | 98% (1) | – | – |
| cf3a | anthropic/claude-haiku-5.5 | 0% (140) | 79% (140) | 77% (139) | 86% (66) | 91% (43) | 86% (14) | 96% (5) | 97% (1) | – | – | – | – | – | – |
| cf3a | inception/mercury-2.5 | 1% (140) | 7% (140) | 7% (136) | 11% (103) | 15% (87) | 23% (64) | 28% (48) | 32% (37) | 33% (33) | 35% (29) | 43% (25) | 45% (17) | 54% (12) | 46% (1) |
| cf3b | anthropic/claude-opus-5.5 | 0% (42) | 81% (42) | 81% (42) | 90% (19) | 85% (6) | 97% (2) | 95% (1) | – | – | – | – | – | – | – |
| cf3b | anthropic/claude-sonnet-5.5 | 0% (42) | 80% (42) | 81% (42) | 86% (15) | 88% (6) | 98% (2) | – | – | – | – | – | – | – | – |
| cf3b | google/gemini-4-argon | 0% (42) | 0% (42) | 2% (40) | 14% (22) | 21% (12) | 25% (12) | 32% (7) | 38% (7) | 48% (5) | 68% (1) | 70% (1) | 78% (1) | 81% (1) | – |
| bank1 | gemini-4-argon | 0% (102) | 0% (102) | 2% (79) | 6% (47) | 28% (25) | 37% (7) | 46% (1) | 53% (1) | 59% (1) | 63% (1) | 72% (1) | – | – | – |

### Run-level cached share of prompt tokens (and cache-read share of list cost) by number of requests in the run

| store | model | 1–2 req | 3 req | 4 req | 5 req | 6–7 req | 8–10 req | 11–15 req | 16–99 req |
|---|---|---|---|---|---|---|---|---|---|
| cf6 | inclusionai/ling-3.0-flash | 44% / 12% (n=126) | 51% / 14% (n=154) | 56% / 19% (n=54) | 62% / 22% (n=59) | 69% / 27% (n=55) | 82% / 36% (n=19) | 86% / 41% (n=11) | 91% / 57% (n=1) |
| cf6 | deepseek/deepseek-v4-flash-0731#off | 42% / 3% (n=73) | 42% / 2% (n=167) | 49% / 3% (n=95) | 61% / 5% (n=47) | 60% / 4% (n=54) | 64% / 5% (n=17) | 69% / 8% (n=12) | 89% / 17% (n=15) |
| cf6 | anthropic/claude-haiku-5.5 | 47% / 4% (n=89) | 59% / 6% (n=229) | 68% / 10% (n=77) | 72% / 13% (n=48) | 79% / 15% (n=36) | 85% / 14% (n=1) | – | – |
| cf3a | inclusionai/ling-3.0-flash | 52% / 9% (n=7) | 38% / 8% (n=51) | 53% / 13% (n=22) | 66% / 21% (n=24) | 70% / 23% (n=15) | 74% / 26% (n=5) | 82% / 35% (n=9) | 89% / 41% (n=7) |
| cf3a | deepseek/deepseek-v4-flash-0731#off | – | 34% / 18% (n=48) | 41% / 25% (n=35) | 53% / 30% (n=26) | 61% / 40% (n=19) | 76% / 55% (n=9) | 83% / 60% (n=3) | – |
| cf3a | anthropic/claude-haiku-5.5 | 43% / 2% (n=1) | 58% / 5% (n=73) | 66% / 7% (n=23) | 72% / 10% (n=29) | 73% / 9% (n=13) | 81% / 10% (n=1) | – | – |
| cf3a | inception/mercury-2.5 | 6% / 0% (n=4) | 3% / 0% (n=33) | 4% / 0% (n=16) | 7% / 1% (n=23) | 16% / 2% (n=27) | 17% / 2% (n=12) | 32% / 3% (n=13) | 36% / 5% (n=12) |
| cf3b | anthropic/claude-opus-5.5 | – | 59% / 3% (n=23) | 69% / 4% (n=13) | 72% / 5% (n=4) | 80% / 7% (n=2) | – | – | – |
| cf3b | anthropic/claude-sonnet-5.5 | – | 58% / 3% (n=27) | 68% / 5% (n=9) | 74% / 6% (n=4) | 76% / 5% (n=2) | – | – | – |
| cf3b | google/gemini-4-argon | 0% / 0% (n=2) | 1% / 0% (n=18) | 4% / 0% (n=10) | – | 11% / 1% (n=5) | 22% / 1% (n=6) | – | 67% / 6% (n=1) |
| bank1 | gemini-4-argon | 0% / 0% (n=23) | 1% / 0% (n=32) | 4% / 0% (n=22) | 9% / 1% (n=18) | 14% / 1% (n=6) | – | 46% / 4% (n=1) | – |

### Extrapolation: an ideally cached run of N requests

Model per store/model: request i's prompt = P0 + g·i, with P0 = median first-request prompt and g = median growth per request ((last − first prompt)/(requests − 1), runs with ≥3 requests); every later request reads the whole previous prompt from the cache (cached_i = prompt_{i−1}); request 0 reads the median cross-run cached prefix h0; the new suffix is uncached (or a cache write at the write rate, for models that write, i.e. Anthropic); output per request = median completion tokens per request. Unit prices = medians of the per-run component price ÷ tokens. 'Observed' = mean measured cached share for runs with that many requests (±1), where any exist. Shares in the cost columns are of the extrapolated list cost.

| store | model | P0 | g (tok/request) | out/request | h0 | caching? | N | ideal cached share of prompt tokens | observed (runs with N±1 requests) | ideal $/run | same N, no cache $/run | first-request share of $ | cache-read share of $ | uncached+write share of $ | output share of $ |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| cf6 | inclusionai/ling-3.0-flash | 1,754 | 276 | 139 | 384 | read | 4 (obs. mean) | 75% | 55% (n=267) | $0.00011 | $0.00022 | 36% | 25% | 43% | 32% |
| cf6 | inclusionai/ling-3.0-flash | 1,754 | 276 | 139 | 384 | read | 10 | 87% | 83% (n=17) | $0.00028 | $0.00072 | 14% | 39% | 29% | 31% |
| cf6 | inclusionai/ling-3.0-flash | 1,754 | 276 | 139 | 384 | read | 20 | 92% | – | $0.00065 | $0.00201 | 6% | 52% | 21% | 27% |
| cf6 | inclusionai/ling-3.0-flash | 1,754 | 276 | 139 | 384 | read | 40 | 96% | – | $0.00175 | $0.00635 | 2% | 65% | 15% | 20% |
| | unit prices $/M tok: uncached 0.021, cache read 0.0042, write 0.000, output 0.063; observed mean list $/run 0.00025 at mean 4.0 requests | | | | | | | | | | | | | | |
| cf6 | deepseek/deepseek-v4-flash-0731#off | 1,716 | 252 | 102 | 256 | read | 5 (obs. mean) | 78% | 54% (n=180) | $0.00188 | $0.00556 | 42% | 6% | 58% | 36% |
| cf6 | deepseek/deepseek-v4-flash-0731#off | 1,716 | 252 | 102 | 256 | read | 10 | 87% | 62% (n=10) | $0.00333 | $0.01389 | 23% | 10% | 49% | 40% |
| cf6 | deepseek/deepseek-v4-flash-0731#off | 1,716 | 252 | 102 | 256 | read | 20 | 92% | 88% (n=2) | $0.00651 | $0.03886 | 12% | 16% | 42% | 41% |
| cf6 | deepseek/deepseek-v4-flash-0731#off | 1,716 | 252 | 102 | 256 | read | 40 | 96% | – | $0.01391 | $0.12207 | 6% | 26% | 36% | 39% |
| | unit prices $/M tok: uncached 0.440, cache read 0.0140, write 0.000, output 1.320; observed mean list $/run 0.00285 at mean 4.6 requests | | | | | | | | | | | | | | |
| cf6 | anthropic/claude-haiku-5.5 | 2,306 | 488 | 190 | 0 | read+write | 3 (obs. mean) | 61% | 58% (n=395) | $0.00075 | $0.00112 | 51% | 7% | 55% | 38% |
| cf6 | anthropic/claude-haiku-5.5 | 2,306 | 488 | 190 | 0 | read+write | 10 | 85% | 85% (n=1) | $0.00217 | $0.00545 | 18% | 18% | 39% | 44% |
| cf6 | anthropic/claude-haiku-5.5 | 2,306 | 488 | 190 | 0 | read+write | 20 | 92% | – | $0.00462 | $0.01579 | 8% | 28% | 31% | 41% |
| cf6 | anthropic/claude-haiku-5.5 | 2,306 | 488 | 190 | 0 | read+write | 40 | 95% | – | $0.01099 | $0.05110 | 3% | 41% | 24% | 35% |
| | unit prices $/M tok: uncached 0.100, cache read 0.0100, write 0.125, output 0.500; observed mean list $/run 0.00144 at mean 3.4 requests | | | | | | | | | | | | | | |
| cf3a | inclusionai/ling-3.0-flash | 1,736 | 339 | 173 | 320 | read | 5 (obs. mean) | 77% | 61% (n=56) | $0.00015 | $0.00031 | 28% | 26% | 38% | 36% |
| cf3a | inclusionai/ling-3.0-flash | 1,736 | 339 | 173 | 320 | read | 10 | 86% | 77% (n=6) | $0.00032 | $0.00079 | 13% | 37% | 29% | 34% |
| cf3a | inclusionai/ling-3.0-flash | 1,736 | 339 | 173 | 320 | read | 20 | 92% | 90% (n=3) | $0.00077 | $0.00230 | 5% | 50% | 22% | 28% |
| cf3a | inclusionai/ling-3.0-flash | 1,736 | 339 | 173 | 320 | read | 40 | 96% | – | $0.00208 | $0.00745 | 2% | 64% | 15% | 21% |
| | unit prices $/M tok: uncached 0.021, cache read 0.0042, write 0.000, output 0.063; observed mean list $/run 0.00031 at mean 5.5 requests | | | | | | | | | | | | | | |
| cf3a | deepseek/deepseek-v4-flash-0731#off | 1,643 | 292 | 131 | 256 | read | 5 (obs. mean) | 77% | 49% (n=76) | $0.00046 | $0.00058 | 19% | 52% | 23% | 24% |
| cf3a | deepseek/deepseek-v4-flash-0731#off | 1,643 | 292 | 131 | 256 | read | 10 | 86% | 82% (n=6) | $0.00111 | $0.00147 | 8% | 65% | 15% | 20% |
| cf3a | deepseek/deepseek-v4-flash-0731#off | 1,643 | 292 | 131 | 256 | read | 20 | 92% | – | $0.00302 | $0.00417 | 3% | 76% | 10% | 15% |
| cf3a | deepseek/deepseek-v4-flash-0731#off | 1,643 | 292 | 131 | 256 | read | 40 | 96% | – | $0.00928 | $0.01327 | 1% | 85% | 6% | 10% |
| | unit prices $/M tok: uncached 0.042, cache read 0.0280, write 0.000, output 0.169; observed mean list $/run 0.00068 at mean 4.7 requests | | | | | | | | | | | | | | |
| cf3a | anthropic/claude-haiku-5.5 | 2,258 | 615 | 260 | 0 | read+write | 4 (obs. mean) | 68% | 62% (n=125) | $0.00112 | $0.00179 | 37% | 8% | 46% | 47% |
| cf3a | anthropic/claude-haiku-5.5 | 2,258 | 615 | 260 | 0 | read+write | 10 | 84% | – | $0.00270 | $0.00633 | 15% | 16% | 36% | 48% |
| cf3a | anthropic/claude-haiku-5.5 | 2,258 | 615 | 260 | 0 | read+write | 20 | 91% | – | $0.00583 | $0.01880 | 7% | 25% | 30% | 45% |
| cf3a | anthropic/claude-haiku-5.5 | 2,258 | 615 | 260 | 0 | read+write | 40 | 95% | – | $0.01393 | $0.06219 | 3% | 39% | 24% | 37% |
| | unit prices $/M tok: uncached 0.100, cache read 0.0100, write 0.125, output 0.500; observed mean list $/run 0.00154 at mean 3.9 requests | | | | | | | | | | | | | | |
| cf3a | inception/mercury-2.5 | 1,657 | 183 | 109 | 0 | read | 7 (obs. mean) | 82% | 16% (n=31) | $0.00028 | $0.00073 | 30% | 18% | 40% | 42% |
| cf3a | inception/mercury-2.5 | 1,657 | 183 | 109 | 0 | read | 10 | 87% | 23% (n=13) | $0.00038 | $0.00116 | 22% | 23% | 35% | 43% |
| cf3a | inception/mercury-2.5 | 1,657 | 183 | 109 | 0 | read | 20 | 92% | 36% (n=3) | $0.00078 | $0.00304 | 11% | 32% | 26% | 42% |
| cf3a | inception/mercury-2.5 | 1,657 | 183 | 109 | 0 | read | 40 | 96% | – | $0.00181 | $0.00901 | 5% | 44% | 19% | 36% |
| | unit prices $/M tok: uncached 0.040, cache read 0.0040, write 0.000, output 0.150; observed mean list $/run 0.00087 at mean 6.7 requests | | | | | | | | | | | | | | |
| cf3b | anthropic/claude-opus-5.5 | 2,258 | 491 | 172 | 0 | read+write | 4 (obs. mean) | 69% | 63% (n=40) | $0.03403 | $0.06163 | 43% | 5% | 55% | 40% |
| cf3b | anthropic/claude-opus-5.5 | 2,258 | 491 | 172 | 0 | read+write | 10 | 85% | – | $0.07530 | $0.21305 | 20% | 10% | 44% | 46% |
| cf3b | anthropic/claude-opus-5.5 | 2,258 | 491 | 172 | 0 | read+write | 20 | 92% | – | $0.15196 | $0.62268 | 10% | 17% | 38% | 45% |
| cf3b | anthropic/claude-opus-5.5 | 2,258 | 491 | 172 | 0 | read+write | 40 | 95% | – | $0.33475 | $2.03162 | 4% | 27% | 32% | 41% |
| | unit prices $/M tok: uncached 4.000, cache read 0.2000, write 5.000, output 20.000; observed mean list $/run 0.04582 at mean 3.7 requests | | | | | | | | | | | | | | |
| cf3b | anthropic/claude-sonnet-5.5 | 2,258 | 578 | 222 | 0 | read+write | 4 (obs. mean) | 68% | 62% (n=40) | $0.01971 | $0.03388 | 40% | 4% | 51% | 45% |
| cf3b | anthropic/claude-sonnet-5.5 | 2,258 | 578 | 222 | 0 | read+write | 10 | 85% | – | $0.04496 | $0.11938 | 17% | 9% | 41% | 49% |
| cf3b | anthropic/claude-sonnet-5.5 | 2,258 | 578 | 222 | 0 | read+write | 20 | 91% | – | $0.09167 | $0.35433 | 9% | 15% | 36% | 48% |
| cf3b | anthropic/claude-sonnet-5.5 | 2,258 | 578 | 222 | 0 | read+write | 40 | 95% | – | $0.20242 | $1.17097 | 4% | 26% | 31% | 44% |
| | unit prices $/M tok: uncached 2.000, cache read 0.1000, write 2.500, output 10.000; observed mean list $/run 0.02286 at mean 3.5 requests | | | | | | | | | | | | | | |
| cf3b | google/gemini-4-argon | 1,491 | 302 | 83 | 0 | read | 5 (obs. mean) | 74% | 7% (n=15) | $0.01032 | $0.02509 | 37% | 8% | 52% | 40% |
| cf3b | google/gemini-4-argon | 1,491 | 302 | 83 | 0 | read | 10 | 85% | 21% (n=4) | $0.01914 | $0.06528 | 20% | 13% | 44% | 43% |
| cf3b | google/gemini-4-argon | 1,491 | 302 | 83 | 0 | read | 20 | 92% | – | $0.03904 | $0.19090 | 10% | 20% | 37% | 43% |
| cf3b | google/gemini-4-argon | 1,491 | 302 | 83 | 0 | read | 40 | 96% | – | $0.08789 | $0.62321 | 4% | 32% | 30% | 38% |
| | unit prices $/M tok: uncached 2.000, cache read 0.1000, write 0.000, output 10.000; observed mean list $/run 0.03488 at mean 4.7 requests | | | | | | | | | | | | | | |
| bank1 | gemini-4-argon | 1,106 | 303 | 73 | 0 | read | 4 (obs. mean) | 68% | 4% (n=72) | $0.00737 | $0.01540 | 40% | 6% | 55% | 40% |
| bank1 | gemini-4-argon | 1,106 | 303 | 73 | 0 | read | 10 | 84% | 46% (n=1) | $0.01705 | $0.05667 | 17% | 12% | 45% | 43% |
| bank1 | gemini-4-argon | 1,106 | 303 | 73 | 0 | read | 20 | 91% | – | $0.03560 | $0.17390 | 8% | 20% | 39% | 41% |
| bank1 | gemini-4-argon | 1,106 | 303 | 73 | 0 | read | 40 | 95% | – | $0.08178 | $0.59005 | 4% | 33% | 32% | 36% |
| | unit prices $/M tok: uncached 2.000, cache read 0.1000, write 0.000, output 10.000; observed mean list $/run 0.02066 at mean 3.6 requests | | | | | | | | | | | | | | |

### Wall-clock seconds per run (users' waiting time)

`seconds` = run.json wall time; model s = `runRecord.totals.modelSeconds` (time inside model requests). Different stores hold different task sets: cf6 = 48 bank tasks, bank1 = 34 bank tasks (the only store with local models; compare within it), cf3a/cf3b = the 14 hard tasks.

| store | model | runs | pass | mean s | median s | p90 s | mean model s | mean steps | s per step (mean) |
|---|---|---|---|---|---|---|---|---|---|
| cf6 | openrouter:inclusionai/ling-3.0-flash | 479 | 98.1% | 16.9 | 15.1 | 22.2 | 6.0 | 4.0 | 4.86 |
| cf6 | openrouter:deepseek/deepseek-v4-flash-0731#off | 480 | 99.8% | 19.4 | 16.9 | 28.7 | 8.5 | 4.6 | 5.01 |
| cf6 | openrouter:anthropic/claude-haiku-5.5 | 480 | 99.2% | 17.1 | 15.9 | 22.1 | 6.3 | 3.4 | 5.28 |
| cf3a | openrouter:inclusionai/ling-3.0-flash | 140 | 99.3% | 21.6 | 18.9 | 29.9 | 10.8 | 5.5 | 4.73 |
| cf3a | openrouter:deepseek/deepseek-v4-flash-0731#off | 140 | 99.3% | 19.6 | 17.2 | 25.4 | 8.9 | 4.7 | 4.44 |
| cf3a | openrouter:anthropic/claude-haiku-5.5 | 140 | 99.3% | 19.0 | 17.7 | 25.7 | 8.3 | 3.9 | 4.99 |
| cf3a | openrouter:inception/mercury-2.5 | 140 | 91.4% | 17.8 | 16.1 | 25.4 | 6.9 | 6.7 | 3.33 |
| cf3b | openrouter:anthropic/claude-opus-5.5 | 42 | 100.0% | 25.5 | 24.2 | 32.6 | 14.8 | 3.7 | 7.12 |
| cf3b | openrouter:anthropic/claude-sonnet-5.5 | 42 | 100.0% | 18.9 | 17.5 | 21.5 | 8.3 | 3.5 | 5.44 |
| cf3b | openrouter:google/gemini-4-argon | 42 | 100.0% | 36.3 | 32.0 | 50.3 | 25.5 | 4.7 | 8.47 |
| cf3b | openrouter:openai/gpt-5.6-sol | 42 | 100.0% | 29.1 | 26.3 | 39.9 | 18.3 | 7.5 | 4.47 |
| cf3b | openrouter:moonshotai/kimi-k3.1-pro | 42 | 100.0% | 57.6 | 46.3 | 85.3 | 46.8 | 7.9 | 7.97 |
| bank1 | google-gemini:gemini-4-argon | 102 | 100.0% | 18.7 | 14.0 | 31.4 | 18.6 | 3.6 | 4.89 |
| bank1 | google-gemini:gemini-3.6-flash | 102 | 100.0% | 12.1 | 11.6 | 21.4 | 11.7 | 7.3 | 1.80 |
| bank1 | google-gemini:gemini-3.8-flash | 102 | 100.0% | 17.0 | 15.1 | 28.3 | 16.6 | 7.3 | 2.42 |
| bank1 | lmstudio:google/gemma-4-26b-a4b-qat | 102 | 89.2% | 57.7 | 39.5 | 127.1 | 57.5 | 5.6 | 10.51 |
| bank1 | bang:qwen/qwen3.5-9b | 102 | 88.2% | 32.5 | 25.0 | 56.3 | 32.2 | 5.7 | 6.16 |
| bank1 | lmstudio:gemma-4-e4b-it | 102 | 81.4% | 80.4 | 49.2 | 126.6 | 80.1 | 5.0 | 15.10 |
## E4. Task-level failure structure

Clustering test: given a model's k failures over its runs (n_t trials of task t), how many distinct tasks would hold them if failures were independent of the task? `binomial` = Σ_t 1−(1−p)^{n_t} with p = k/N; `random placement` = Monte Carlo (20,000 draws) of k failures placed uniformly among the model's N runs, with P(distinct ≤ observed) as a one-sided p-value for clustering.

### cf6: 48 tasks

| model | runs | failures | tasks with ≥1 failure (observed) | expected, binomial | expected, random placement | P(distinct ≤ observed) | max failures on one task |
|---|---|---|---|---|---|---|---|
| inclusionai/ling-3.0-flash | 479 | 9 | 4 | 8.28 | 8.36 | 0.0000 | 3 |
| anthropic/claude-haiku-5.5 | 480 | 4 | 2 | 3.85 | 3.89 | 0.0019 | 3 |
| deepseek/deepseek-v4-flash-0731#off | 480 | 1 | 1 | 0.99 | 1.00 | 1.0000 | 1 |

Failures per task (out of 10 trials; tasks with ≥1 failure for any listed model; 6 of 48 tasks):

| task | ling-3.0-flash | claude-haiku-5.5 | deepseek-v4-flash-0731#off | total |
|---|---|---|---|---|
| h-aliased-calls | 3 | 3 | · | 6 |
| h-discount-code | 2 | · | · | 2 |
| importers-of-storage | 2 | · | · | 2 |
| review-diff | 2 | · | · | 2 |
| fix-shop-total | · | · | 1 | 1 |
| review-clean | · | 1 | · | 1 |

ling-3.0-flash failures vs Haiku on the same tasks (cf6):

| task | ling-3.0-flash failures | Haiku failures (of 10) | Haiku passes the same trial on each failing trial? |
|---|---|---|---|
| h-aliased-calls | 3 | 3 | 3/3 |
| h-discount-code | 2 | 0 | 2/2 |
| importers-of-storage | 2 | 0 | 2/2 |
| review-diff | 2 | 0 | 2/2 |

Oracle escalation ceiling (escalate exactly the failing runs to Haiku's run of the same task/trial): ling-3.0-flash 98.12% → 100.00% (9 of 9 failures recoverable). Tasks where ling-3.0-flash fails and Haiku passes all 10: h-discount-code, importers-of-storage, review-diff.

Haiku failures in cf6: h-aliased-calls (3/10), review-clean (1/10)

### cf3a: 14 tasks

| model | runs | failures | tasks with ≥1 failure (observed) | expected, binomial | expected, random placement | P(distinct ≤ observed) | max failures on one task |
|---|---|---|---|---|---|---|---|
| inception/mercury-2.5 | 140 | 12 | 5 | 8.29 | 8.46 | 0.0024 | 7 |
| stepfun/step-3.5-flash | 140 | 6 | 3 | 4.97 | 5.11 | 0.0184 | 3 |
| deepseek/deepseek-v4-flash-0731 | 140 | 4 | 1 | 3.52 | 3.62 | 0.0001 | 4 |
| deepseek/deepseek-v4-flash | 140 | 4 | 3 | 3.52 | 3.63 | 0.3450 | 2 |
| deepseek/deepseek-v4-flash#off | 140 | 4 | 3 | 3.52 | 3.62 | 0.3517 | 2 |
| inception/mercury-3 | 140 | 4 | 1 | 3.52 | 3.63 | 0.0001 | 4 |
| deepseek/deepseek-v4.1-flash | 140 | 2 | 2 | 1.88 | 1.93 | 1.0000 | 1 |
| poolside/laguna-s-2.1#off | 140 | 2 | 1 | 1.88 | 1.94 | 0.0649 | 2 |
| anthropic/claude-haiku-5.5 | 140 | 1 | 1 | 0.97 | 1.00 | 1.0000 | 1 |
| anthropic/claude-haiku-5.5#off | 140 | 1 | 1 | 0.97 | 1.00 | 1.0000 | 1 |
| deepseek/deepseek-v4-flash-0731#off | 140 | 1 | 1 | 0.97 | 1.00 | 1.0000 | 1 |
| inclusionai/ling-3.0-flash | 140 | 1 | 1 | 0.97 | 1.00 | 1.0000 | 1 |

Failures per task (out of 10 trials; tasks with ≥1 failure for any listed model; 8 of 14 tasks):

| task | mercury-2.5 | step-3.5-flash | deepseek-v4-flash-0731 | deepseek-v4-flash | deepseek-v4-flash#off | mercury-3 | deepseek-v4.1-flash | laguna-s-2.1#off | claude-haiku-5.5 | claude-haiku-5.5#off | deepseek-v4-flash-0731#off | ling-3.0-flash | total |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| h-discount-code | 1 | 3 | 4 | · | · | 4 | 1 | 2 | · | · | 1 | · | 16 |
| h-aliased-calls | 7 | · | · | · | 1 | · | 1 | · | 1 | 1 | · | 1 | 12 |
| h-incidents | · | · | · | 2 | 2 | · | · | · | · | · | · | · | 4 |
| h-crash-diagnose | 1 | · | · | 1 | · | · | · | · | · | · | · | · | 2 |
| h-import-cycle | · | 2 | · | · | · | · | · | · | · | · | · | · | 2 |
| h-log-correlate | 2 | · | · | · | · | · | · | · | · | · | · | · | 2 |
| h-mutable-default | 1 | 1 | · | · | · | · | · | · | · | · | · | · | 2 |
| h-retry-explain | · | · | · | 1 | 1 | · | · | · | · | · | · | · | 2 |

mercury-2.5 failures vs Haiku on the same tasks (cf3a):

| task | mercury-2.5 failures | Haiku failures (of 10) | Haiku passes the same trial on each failing trial? |
|---|---|---|---|
| h-aliased-calls | 7 | 1 | 6/7 |
| h-log-correlate | 2 | 0 | 2/2 |
| h-crash-diagnose | 1 | 0 | 1/1 |
| h-discount-code | 1 | 0 | 1/1 |
| h-mutable-default | 1 | 0 | 1/1 |

Oracle escalation ceiling (escalate exactly the failing runs to Haiku's run of the same task/trial): mercury-2.5 91.43% → 99.29% (11 of 12 failures recoverable). Tasks where mercury-2.5 fails and Haiku passes all 10: h-crash-diagnose, h-discount-code, h-log-correlate, h-mutable-default.

ling-3.0-flash failures vs Haiku on the same tasks (cf3a):

| task | ling-3.0-flash failures | Haiku failures (of 10) | Haiku passes the same trial on each failing trial? |
|---|---|---|---|
| h-aliased-calls | 1 | 1 | 1/1 |

Oracle escalation ceiling (escalate exactly the failing runs to Haiku's run of the same task/trial): ling-3.0-flash 99.29% → 100.00% (1 of 1 failures recoverable). Tasks where ling-3.0-flash fails and Haiku passes all 10: .

Haiku failures in cf3a: h-aliased-calls (1/10)
