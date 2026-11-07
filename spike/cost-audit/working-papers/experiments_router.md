# Router headroom experiments (R1–R4) on stored kurtkode eval runs

Audit question: on the data we have, is there any routing headroom for the designed-but-unbuilt P3 router (kNN over task embeddings + Bayesian prior, pick the cheapest adequate configuration), and is success predictable from the task text?

Everything here is offline: `python3 -I`, standard library only, reading `~/git/kurtkode/eval-results/runs/{cf2,cf3a,cf3b,cf6}/*/run.json` (read-only). Degraded copies and `infra` runs excluded. Scripts: `scratchpad/scripts3/` (`extract.py` → `data3/rows.jsonl` + `data3/prompts.json`; `common.py`; `r1.py`, `r2.py`, `retest.py`, `r3.py`, `r4.py`). Each script regenerates its section in under 5 s.

Costs: run `listPrice`, except cf6 deepseek-v4-flash-0731#off, whose list price is inflated about 6×; there `runRecord.totals.charged` is used (mean $0.00183/run), and R1 repeats with that charge scaled to a $0.00045 mean. Task prompts are byte-identical across stores (42/42 shared tasks); cf6 was built from a later commit (b9d497c vs 04a992e for cf2/cf3a), so cross-store differences can include harness changes.

## Bottom line

1. **Headroom is real but tiny and mostly noise.** The best possible per-task router (in-sample oracle) gains +1.9 pts over always-ling on cf6 and +0.7 pts on cf3a, at 1.05–1.3× ling's cost. When the oracle chooses on half the trials and is scored on the other half, the gain shrinks to +1.5 pts (cf6) and to zero (cf3a). Against always-Haiku the oracle is 77–79% cheaper, but always-ling is already 79–83% cheaper than Haiku at −1.0 to 0 pts.
2. **kNN over the task text does not beat the prior.** Leave-one-task-out Brier: on cf2, kNN k=5 scores 0.0630 against the prior's 0.0586, worse with a CI that excludes zero. kNN shrunk toward the prior ties the prior on all three stores. Text neighbours do beat random neighbours (cf2, cf3a), so there is a faint signal, but averaging over all other tasks beats both. A predictor told the held-out task's true difficulty would gain 18–49% in Brier; that is the ceiling, and nothing observable before the run gets close.
3. **The simulated router reproduces always-ling or does worse.** On cf2 the kNN router at 0.95 gives 94.6% at $0.00024, against always-ling's 98.2% at $0.00018. The prior-only router simply picks ling. On cf6 kNN at 0.95 gives 98.5% at $0.00030, against ling's 98.1% at $0.00025 and Haiku's 99.2% at $0.00144: +0.4 pts for +20% cost, from 5 tasks.
4. **No static difficulty signal either.** Prompt length, kind and edit-vs-read have |ρ| ≤ 0.37 with task failure rate, none significant, and the sign flips between stores. The strongest correlates are post-run: mean completion tokens (ρ = +0.38 on cf2, p = 0.05) and mean seconds (+0.28 on cf6, p = 0.06). Those would suit a cascade, not a pre-run router.
5. **Failure cost, not token price, decides the choice.** Haiku's cost per success is 5.4× ling's. Always-Haiku beats always-ling once a silent failure costs more than about $0.11; for deepseek#off at its typical price, more than about $0.03.

# R1. Oracle routing headroom

Hypothesis: if the cheap and dear models fail on different tasks, a per-task router can buy most of the dear model's pass rate at near the cheap model's price; if failures are rare and scattered (noise), the oracle's headroom is tiny and not reproducible on fresh trials.

Data: cf6 (ling-3.0-flash, deepseek-v4-flash-0731#off, Haiku 5.5; 48 tasks × 10 trials; 1,439 real runs). cf3a (the 12 models with ≥100 runs, i.e. 10 trials on each of the 14 hard tasks) plus Opus 5.5 and Sonnet 5.5 from cf3b (3 trials/task, all pass) priced at their cf3b store means. Cost = run listPrice; cf6 deepseek uses runRecord.totals.charged (mean $0.00183) and, in a second pass, that charge scaled to a $0.00045 mean.


### cf6 (deepseek at charged, mean $0.00183): 48 tasks, 3 models

(a) Always-X (equal task weight; cost = mean $/run)

| model | pass rate | mean $/run | tasks with ≥1 fail |
|---|---|---|---|
| ling-3.0-flash | 98.1% | 0.00025 | 4 |
| claude-haiku-5.5 | 99.2% | 0.00144 | 2 |
| deepseek-v4-flash-0731#off | 99.8% | 0.00183 | 1 |

(b) Per-task oracle (in-sample: chooses and is scored on the same trials) and split-half oracle (choose on trials 1–5, score on 6–10, and the reverse; averaged)

| oracle bar | pass (in-sample) | mean $/run | pass (split-half) | $/run (split-half) | models chosen (in-sample) |
|---|---|---|---|---|---|
| match best | 100.00% | 0.00033 | 99.58% | 0.00030 | ling-3.0-flash×44, deepseek-v4-flash-0731#off×4 |
| ≥1.0 | 100.00% | 0.00033 | 99.58% | 0.00030 | ling-3.0-flash×44, deepseek-v4-flash-0731#off×4 |
| ≥0.95 | 100.00% | 0.00033 | 99.58% | 0.00030 | ling-3.0-flash×44, deepseek-v4-flash-0731#off×4 |
| ≥0.9 | 100.00% | 0.00033 | 99.58% | 0.00030 | ling-3.0-flash×44, deepseek-v4-flash-0731#off×4 |

Headline: match-best oracle 100.00% at $0.00033/run vs always-ling 98.12% at $0.00025 (1.30× ling's cost, +1.88 pts) and always-Haiku 99.17% at $0.00144 (77% cheaper than Haiku, +0.83 pts).


### cf6 (deepseek at typical, mean $0.00045): 48 tasks, 3 models

(a) Always-X (equal task weight; cost = mean $/run)

| model | pass rate | mean $/run | tasks with ≥1 fail |
|---|---|---|---|
| ling-3.0-flash | 98.1% | 0.00025 | 4 |
| deepseek-v4-flash-0731#off | 99.8% | 0.00045 | 1 |
| claude-haiku-5.5 | 99.2% | 0.00144 | 2 |

(b) Per-task oracle (in-sample: chooses and is scored on the same trials) and split-half oracle (choose on trials 1–5, score on 6–10, and the reverse; averaged)

| oracle bar | pass (in-sample) | mean $/run | pass (split-half) | $/run (split-half) | models chosen (in-sample) |
|---|---|---|---|---|---|
| match best | 100.00% | 0.00021 | 100.00% | 0.00021 | ling-3.0-flash×32, deepseek-v4-flash-0731#off×16 |
| ≥1.0 | 100.00% | 0.00021 | 100.00% | 0.00021 | ling-3.0-flash×32, deepseek-v4-flash-0731#off×16 |
| ≥0.95 | 100.00% | 0.00021 | 100.00% | 0.00021 | ling-3.0-flash×32, deepseek-v4-flash-0731#off×16 |
| ≥0.9 | 100.00% | 0.00021 | 100.00% | 0.00021 | ling-3.0-flash×32, deepseek-v4-flash-0731#off×16 |

Headline: match-best oracle 100.00% at $0.00021/run vs always-ling 98.12% at $0.00025 (0.82× ling's cost, +1.88 pts) and always-Haiku 99.17% at $0.00144 (86% cheaper than Haiku, +0.83 pts).


### cf3a + frontier: 14 tasks, 14 models

(a) Always-X (equal task weight; cost = mean $/run)

| model | pass rate | mean $/run | tasks with ≥1 fail |
|---|---|---|---|
| ling-3.0-flash | 99.3% | 0.00031 | 1 |
| deepseek-v4-flash-0731#off | 99.3% | 0.00068 | 1 |
| deepseek-v4-flash-0731 | 97.1% | 0.00086 | 1 |
| mercury-2.5 | 91.4% | 0.00087 | 5 |
| laguna-s-2.1#off | 98.6% | 0.00112 | 1 |
| deepseek-v4-flash#off | 97.1% | 0.00113 | 3 |
| claude-haiku-5.5#off | 99.3% | 0.00130 | 1 |
| deepseek-v4-flash | 97.1% | 0.00132 | 3 |
| mercury-3 | 97.1% | 0.00137 | 1 |
| claude-haiku-5.5 | 99.3% | 0.00154 | 1 |
| deepseek-v4.1-flash | 98.6% | 0.00239 | 2 |
| step-3.5-flash | 95.7% | 0.00299 | 3 |
| claude-sonnet-5.5 | 100.0% | 0.02286 | 0 |
| claude-opus-5.5 | 100.0% | 0.04582 | 0 |

(b) Per-task oracle (in-sample: chooses and is scored on the same trials) and split-half oracle (choose on trials 1–5, score on 6–10, and the reverse; averaged)

| oracle bar | pass (in-sample) | mean $/run | pass (split-half) | $/run (split-half) | models chosen (in-sample) |
|---|---|---|---|---|---|
| match best | 100.00% | 0.00032 | 99.29% | 0.00032 | ling-3.0-flash×13, deepseek-v4-flash-0731#off×1 |
| ≥1.0 | 100.00% | 0.00032 | 99.29% | 0.00032 | ling-3.0-flash×13, deepseek-v4-flash-0731#off×1 |
| ≥0.95 | 100.00% | 0.00032 | 99.29% | 0.00032 | ling-3.0-flash×13, deepseek-v4-flash-0731#off×1 |
| ≥0.9 | 99.29% | 0.00031 | 99.29% | 0.00032 | ling-3.0-flash×14 |

Headline: match-best oracle 100.00% at $0.00032/run vs always-ling 99.29% at $0.00031 (1.05× ling's cost, +0.71 pts) and always-Haiku 99.29% at $0.00154 (79% cheaper than Haiku, +0.71 pts).


### (c) Solve-set containment

Cell level pairs the same (task, trial index); trials are independent draws, so this is the chance the other model passes a failed cell, not a matched retry. 'Tasks A fails' = tasks where A's pass rate < 1; 'B's rate there' = B's mean pass rate on those tasks. Last three columns: tasks where B's rate is above / below / equal to A's.

| store | A | B | A's failed cells | B passes same cell | tasks A fails | B's rate there | B>A tasks | B<A tasks | tie |
|---|---|---|---|---|---|---|---|---|---|
| cf6 | ling-3.0-flash | claude-haiku-5.5 | 9 | 9/9 (100%) | 4 | 92% | 3 | 1 | 44 |
| cf6 | claude-haiku-5.5 | ling-3.0-flash | 4 | 4/4 (100%) | 2 | 85% | 1 | 3 | 44 |
| cf6 | ling-3.0-flash | deepseek-v4-flash-0731#off | 9 | 9/9 (100%) | 4 | 100% | 4 | 1 | 43 |
| cf6 | deepseek-v4-flash-0731#off | ling-3.0-flash | 1 | 1/1 (100%) | 1 | 100% | 1 | 4 | 43 |
| cf6 | deepseek-v4-flash-0731#off | claude-haiku-5.5 | 1 | 1/1 (100%) | 1 | 100% | 1 | 2 | 45 |
| cf6 | claude-haiku-5.5 | deepseek-v4-flash-0731#off | 4 | 4/4 (100%) | 2 | 100% | 2 | 1 | 45 |
| cf3a | ling-3.0-flash | claude-haiku-5.5 | 1 | 1/1 (100%) | 1 | 90% | 0 | 0 | 14 |
| cf3a | claude-haiku-5.5 | ling-3.0-flash | 1 | 1/1 (100%) | 1 | 90% | 0 | 0 | 14 |
| cf3a | mercury-2.5 | ling-3.0-flash | 12 | 11/12 (92%) | 5 | 98% | 5 | 0 | 9 |
| cf3a | ling-3.0-flash | mercury-2.5 | 1 | 0/1 (0%) | 1 | 30% | 0 | 5 | 9 |
| cf3a | ling-3.0-flash | claude-opus-5.5 | 1 | 0/0 | 1 | 100% | 1 | 0 | 13 |

Per-task failures (failed trials / trials) where any of ling, deepseek#off, Haiku failed, cf6:

| task | ling | deepseek#off | Haiku |
|---|---|---|---|
| fix-shop-total | 0/10 | 1/10 | 0/10 |
| h-aliased-calls | 3/10 | 0/10 | 3/10 |
| h-discount-code | 2/10 | 0/10 | 0/10 |
| importers-of-storage | 2/10 | 0/10 | 0/10 |
| review-clean | 0/10 | 0/10 | 1/10 |
| review-diff | 2/10 | 0/10 | 0/10 |

**Method/metric.** Per task: each model's pass rate over its trials and mean $/run. Always-X = mean over tasks (equal task weight; all cells in cf6/cf3a have 10 trials except one 9-trial cell). Oracle = per task, the cheapest model whose rate ≥ the best model's rate (or ≥ 0.9/0.95/1.0, falling back to the best). Split-half oracle: choose on trials 1–5, score on 6–10, and vice versa (frontier cf3b cells, 3 trials, used in both halves).

**Caveats.** The in-sample oracle is optimistic by construction: it routes on the very failures it is scored on. With 14 failures on cf6 (6 tasks) and 1 ling failure on cf3a, every oracle figure rests on a handful of events. Cell-level containment pairs the same trial index; trials are independent draws, so "Haiku passes ling's failed cell 9/9" is a retry statistic, not evidence of disjoint skills. The per-task view is the relevant one: on the tasks ling fails, Haiku's rate is 92% (cf6) and 90% (cf3a), well below its 99% overall. Failures concentrate on the same tasks (h-aliased-calls: ling 3/10, Haiku 3/10 on cf6), so they are shared difficulty, not complementary skill. One line: **the best possible per-task router would cost 5–30% more than always-ling (at the charged deepseek price; 18% less only if deepseek is billed at its typical $0.00045) for +0.7 to +1.9 pts in-sample (+0 to +1.5 pts on fresh trials), and would save 77–79% against always-Haiku at a pass rate ≥ Haiku's.**

# R2. Is failure predictable from the task text?

Hypothesis: if a task's text predicts which configurations fail it, a kNN over task embeddings should beat each configuration's own mean (the prior) in Brier score, and a router built on it should beat always-one-model on cost at equal pass rate.

Method: leave-one-task-out. TF-IDF (sublinear tf, idf over the store's task prompts, word + underscore-split identifier tokens) cosine kNN; card kNN uses distance = [kind differs] + |Δ log prompt chars| / sd. 'kNN + prior' = (k·kNN mean + m·prior)/(k+m), a Bayesian shrink. 'random k=5' averages 50 random draws of 5 training tasks: the null for 'similarity carries information'. 'oracle task-effect (cheat)' adds the held-out task's true mean difficulty shift to the prior: the ceiling for any predictor that only learns a per-task difficulty.


## cf2 (configurations with all 28 tasks): 28 tasks × 205 configurations (9492 runs; overall pass 93.5%; cells with 0<rate<1 or fail: 418)

Leave-one-task-out prediction of each configuration's pass rate on the held-out task (cells weighted equally; probabilities clipped to [0.01, 0.99]; Brier/log loss against the cell's observed pass rate).

| predictor | Brier | log loss | Brier skill vs smoothed prior | Δ Brier vs prior, 95% task-bootstrap CI |
|---|---|---|---|---|
| constant | 0.05890 | 0.2457 | -0.5% | [-0.00103, +0.00170] |
| prior (config mean, raw) | 0.05878 | 0.2472 | -0.3% | [+0.00004, +0.00030] |
| prior (smoothed, a=2) | 0.05861 | 0.2464 | +0.0% | – |
| kNN text k=3 | 0.06617 | 0.2856 | -12.9% | [-0.00030, +0.01699] |
| kNN text k=5 | 0.06304 | 0.2775 | -7.5% | [+0.00033, +0.00881] |
| kNN text k=5 + prior (m=5) | 0.05897 | 0.2485 | -0.6% | [-0.00155, +0.00225] |
| kNN card k=3 | 0.07744 | 0.3373 | -32.1% | [+0.01115, +0.02786] |
| kNN card k=5 | 0.06868 | 0.3053 | -17.2% | [+0.00500, +0.01553] |
| kNN card k=5 + prior (m=5) | 0.06130 | 0.2619 | -4.6% | [+0.00061, +0.00492] |
| random k=5 (null, 50 draws) | 0.06718 | 0.3012 | -14.6% | [+0.00762, +0.00960] |
| prior + kNN-text task-effect k=5 | 0.05805 | 0.2411 | +1.0% | [-0.00262, +0.00153] |
| prior + kNN-card task-effect k=5 | 0.06167 | 0.2698 | -5.2% | [+0.00047, +0.00585] |
| oracle task-effect (cheat) | 0.04824 | 0.1807 | +17.7% | [-0.02001, -0.00389] |

kNN text k=5 minus random k=5 Brier, 95% task-bootstrap CI: [-0.00792, -0.00009] (negative = text neighbours beat random neighbours).
Spread of configuration pass rates (all tasks): min 0.61, P10 0.89, median 0.93, P90 1.00; configurations at 100%: 40/205. Spread of task pass rates (all configs): warn-count 0.61, importers-of-storage 0.70, warn-top-component 0.80, review-clean 0.82, sum-csv 0.83 (five hardest).

Nearest neighbours by TF-IDF cosine (first six tasks, sanity check):

| task | kind | 3 nearest (cosine) |
|---|---|---|
| add-count-items | edit | write-pricing-tests (0.13), discount-for (0.13), review-diff (0.12) |
| calc-bugs-explain | explain | fix-shop-total (0.33), fix-rates (0.32), write-pricing-tests (0.17) |
| callers-reserve | search | list-classes (0.25), rename-total (0.20), find-too-many-test (0.20) |
| class-in-file | search | file-for-class (0.29), list-classes (0.20), find-too-many-test (0.19) |
| count-tests | run | write-pricing-tests (0.32), run-script (0.30), fix-rates (0.18) |
| discount-for | explain | write-pricing-tests (0.33), find-tax-rate (0.20), grow-value (0.16) |

Router simulation: for each held-out task, the cheapest configuration (by its mean cost on the training tasks) whose predicted pass probability ≥ threshold; if none, the highest predicted. Realized pass = that configuration's observed rate on the held-out task; realized cost = its observed mean $/run there.

| policy | threshold | realized pass | mean $/run | configs chosen (top 3) |
|---|---|---|---|---|
| always ling-3.0-flash | – | 98.21% | 0.00018 | – |
| always Haiku 5.5 | – | 99.64% | 0.00099 | – |
| always cheapest config perfect on the other tasks | – | 91.07% | 0.00133 | deepseek-v4-pro×23, mercury-3×1, longcat-2.0#off×1 |
| router: prior (smoothed, a=2) | 0.9 | 98.21% | 0.00018 | ling-3.0-flash×28 |
| router: prior (smoothed, a=2) | 0.95 | 98.21% | 0.00018 | ling-3.0-flash×28 |
| router: prior (smoothed, a=2) | 0.98 | 97.86% | 0.00038 | deepseek-v4-flash-0731×26, ling-3.0-flash×2 |
| router: kNN text k=5 | 0.9 | 94.64% | 0.00020 | ling-3.0-flash×17, ling-3.0-flash#off×11 |
| router: kNN text k=5 | 0.95 | 94.64% | 0.00024 | ling-3.0-flash×12, ling-3.0-flash#off×11, deepseek-v4-flash-0731×4 |
| router: kNN text k=5 | 0.98 | 94.64% | 0.00024 | ling-3.0-flash×12, ling-3.0-flash#off×11, deepseek-v4-flash-0731×4 |
| router: kNN text k=5 + prior (m=5) | 0.9 | 94.64% | 0.00020 | ling-3.0-flash×17, ling-3.0-flash#off×11 |
| router: kNN text k=5 + prior (m=5) | 0.95 | 98.21% | 0.00018 | ling-3.0-flash×28 |
| router: kNN text k=5 + prior (m=5) | 0.98 | 98.21% | 0.00022 | ling-3.0-flash×23, deepseek-v4-flash-0731×5 |
| router: kNN card k=5 + prior (m=5) | 0.9 | 85.71% | 0.00016 | ling-3.0-flash#off×15, ling-3.0-flash×13 |
| router: kNN card k=5 + prior (m=5) | 0.95 | 98.21% | 0.00019 | ling-3.0-flash×26, deepseek-v4-flash-0731×2 |
| router: kNN card k=5 + prior (m=5) | 0.98 | 98.21% | 0.00030 | ling-3.0-flash×15, laguna-s-2.1×7, deepseek-v4-flash-0731×4 |
| router: prior + kNN-text task-effect k=5 | 0.9 | 91.79% | 0.00020 | ling-3.0-flash×20, ling-3.0-flash#off×8 |
| router: prior + kNN-text task-effect k=5 | 0.95 | 98.21% | 0.00045 | ling-3.0-flash×23, deepseek-v4-flash-0731×2, deepseek-v4-pro×2 |
| router: prior + kNN-text task-effect k=5 | 0.98 | 95.71% | 0.00073 | ling-3.0-flash×19, deepseek-v4-pro×6, longcat-2.0#off×1 |
| router: oracle task-effect (cheat) | 0.9 | 91.07% | 0.00052 | ling-3.0-flash#off×16, ling-3.0-flash×7, mercury-3×1 |
| router: oracle task-effect (cheat) | 0.95 | 91.07% | 0.00053 | ling-3.0-flash×22, mercury-3×1, mimo-v2.6-flash×1 |
| router: oracle task-effect (cheat) | 0.98 | 91.07% | 0.00069 | ling-3.0-flash×19, deepseek-v4-pro×5, mercury-3×1 |

## cf3a (all 25 models): 14 tasks × 25 configurations (2226 runs; overall pass 96.1%; cells with 0<rate<1 or fail: 44)

Leave-one-task-out prediction of each configuration's pass rate on the held-out task (cells weighted equally; probabilities clipped to [0.01, 0.99]; Brier/log loss against the cell's observed pass rate).

| predictor | Brier | log loss | Brier skill vs smoothed prior | Δ Brier vs prior, 95% task-bootstrap CI |
|---|---|---|---|---|
| constant | 0.01656 | 0.1720 | +1.3% | [-0.00085, +0.00049] |
| prior (config mean, raw) | 0.01695 | 0.1724 | -1.0% | [+0.00001, +0.00029] |
| prior (smoothed, a=2) | 0.01678 | 0.1723 | +0.0% | – |
| kNN text k=3 | 0.01714 | 0.1741 | -2.1% | [-0.00103, +0.00200] |
| kNN text k=5 | 0.01675 | 0.1736 | +0.2% | [-0.00098, +0.00115] |
| kNN text k=5 + prior (m=5) | 0.01642 | 0.1691 | +2.1% | [-0.00093, +0.00040] |
| kNN card k=3 | 0.02019 | 0.1944 | -20.3% | [+0.00113, +0.00612] |
| kNN card k=5 | 0.01775 | 0.1879 | -5.8% | [-0.00022, +0.00227] |
| kNN card k=5 + prior (m=5) | 0.01706 | 0.1763 | -1.6% | [-0.00040, +0.00106] |
| random k=5 (null, 50 draws) | 0.01885 | 0.1880 | -12.3% | [+0.00139, +0.00257] |
| prior + kNN-text task-effect k=5 | 0.01654 | 0.1725 | +1.4% | [-0.00093, +0.00058] |
| prior + kNN-card task-effect k=5 | 0.01684 | 0.1753 | -0.4% | [-0.00058, +0.00075] |
| oracle task-effect (cheat) | 0.01283 | 0.1326 | +23.5% | [-0.00910, -0.00094] |

kNN text k=5 minus random k=5 Brier, 95% task-bootstrap CI: [-0.00345, -0.00032] (negative = text neighbours beat random neighbours).
Spread of configuration pass rates (all tasks): min 0.88, P10 0.90, median 0.97, P90 0.99; configurations at 100%: 2/25. Spread of task pass rates (all configs): h-discount-code 0.79, h-aliased-calls 0.87, h-log-correlate 0.94, h-import-cycle 0.97, h-retry-explain 0.97 (five hardest).

Nearest neighbours by TF-IDF cosine (first six tasks, sanity check):

| task | kind | 3 nearest (cosine) |
|---|---|---|
| h-aliased-calls | search | h-plugins (0.13), h-crash-diagnose (0.11), h-retry-explain (0.08) |
| h-config-migrate | edit | h-unit-bug (0.12), h-rename-trap (0.12), h-mutable-default (0.11) |
| h-crash-diagnose | run | h-unit-bug (0.12), h-mutable-default (0.12), h-aliased-calls (0.11) |
| h-discount-code | edit | h-mutable-default (0.10), h-leap-year (0.07), h-unit-bug (0.07) |
| h-edge-tests | write-tests | h-crash-diagnose (0.11), h-unit-bug (0.10), h-leap-year (0.10) |
| h-import-cycle | research | h-mutable-default (0.14), h-leap-year (0.10), h-unit-bug (0.08) |

Router simulation: for each held-out task, the cheapest configuration (by its mean cost on the training tasks) whose predicted pass probability ≥ threshold; if none, the highest predicted. Realized pass = that configuration's observed rate on the held-out task; realized cost = its observed mean $/run there.

| policy | threshold | realized pass | mean $/run | configs chosen (top 3) |
|---|---|---|---|---|
| always ling-3.0-flash | – | 99.29% | 0.00031 | – |
| always Haiku 5.5 | – | 99.29% | 0.00154 | – |
| always cheapest config perfect on the other tasks | – | 99.29% | 0.00061 | qwen3.7-flash×13, ling-3.0-flash×1 |
| router: prior (smoothed, a=2) | 0.9 | 99.29% | 0.00031 | ling-3.0-flash×14 |
| router: prior (smoothed, a=2) | 0.95 | 99.29% | 0.00031 | ling-3.0-flash×14 |
| router: prior (smoothed, a=2) | 0.98 | 99.29% | 0.00031 | ling-3.0-flash×14 |
| router: kNN text k=5 | 0.9 | 99.29% | 0.00031 | ling-3.0-flash×14 |
| router: kNN text k=5 | 0.95 | 99.29% | 0.00031 | ling-3.0-flash×14 |
| router: kNN text k=5 | 0.98 | 99.29% | 0.00031 | ling-3.0-flash×14 |
| router: kNN text k=5 + prior (m=5) | 0.9 | 99.29% | 0.00031 | ling-3.0-flash×14 |
| router: kNN text k=5 + prior (m=5) | 0.95 | 99.29% | 0.00031 | ling-3.0-flash×14 |
| router: kNN text k=5 + prior (m=5) | 0.98 | 99.29% | 0.00031 | ling-3.0-flash×14 |
| router: kNN card k=5 + prior (m=5) | 0.9 | 99.29% | 0.00031 | ling-3.0-flash×14 |
| router: kNN card k=5 + prior (m=5) | 0.95 | 99.29% | 0.00031 | ling-3.0-flash×14 |
| router: kNN card k=5 + prior (m=5) | 0.98 | 99.29% | 0.00031 | ling-3.0-flash×14 |
| router: prior + kNN-text task-effect k=5 | 0.9 | 99.29% | 0.00031 | ling-3.0-flash×14 |
| router: prior + kNN-text task-effect k=5 | 0.95 | 99.29% | 0.00031 | ling-3.0-flash×14 |
| router: prior + kNN-text task-effect k=5 | 0.98 | 99.29% | 0.00039 | ling-3.0-flash×13, qwen3.7-flash×1 |
| router: oracle task-effect (cheat) | 0.9 | 99.29% | 0.00033 | ling-3.0-flash×13, qwen3.7-flash×1 |
| router: oracle task-effect (cheat) | 0.95 | 99.29% | 0.00033 | ling-3.0-flash×13, qwen3.7-flash×1 |
| router: oracle task-effect (cheat) | 0.98 | 99.29% | 0.00041 | ling-3.0-flash×12, qwen3.7-flash×2 |

## cf6 (3 models, 10-trial rates; deepseek at charged cost): 48 tasks × 3 configurations (1439 runs; overall pass 99.0%; cells with 0<rate<1 or fail: 7)

Leave-one-task-out prediction of each configuration's pass rate on the held-out task (cells weighted equally; probabilities clipped to [0.01, 0.99]; Brier/log loss against the cell's observed pass rate).

| predictor | Brier | log loss | Brier skill vs smoothed prior | Δ Brier vs prior, 95% task-bootstrap CI |
|---|---|---|---|---|
| constant | 0.00213 | 0.0547 | +1.4% | [-0.00007, +0.00002] |
| prior (config mean, raw) | 0.00216 | 0.0555 | -0.1% | [-0.00000, +0.00000] |
| prior (smoothed, a=2) | 0.00216 | 0.0555 | +0.0% | – |
| kNN text k=3 | 0.00273 | 0.0611 | -26.6% | [+0.00004, +0.00120] |
| kNN text k=5 | 0.00245 | 0.0597 | -13.4% | [-0.00003, +0.00062] |
| kNN text k=5 + prior (m=5) | 0.00223 | 0.0569 | -3.2% | [-0.00008, +0.00020] |
| kNN card k=3 | 0.00224 | 0.0559 | -3.9% | [-0.00045, +0.00042] |
| kNN card k=5 | 0.00239 | 0.0559 | -10.6% | [-0.00024, +0.00069] |
| kNN card k=5 + prior (m=5) | 0.00214 | 0.0537 | +0.7% | [-0.00024, +0.00018] |
| random k=5 (null, 50 draws) | 0.00248 | 0.0595 | -14.9% | [+0.00021, +0.00041] |
| prior + kNN-text task-effect k=5 | 0.00229 | 0.0579 | -6.0% | [-0.00008, +0.00036] |
| prior + kNN-card task-effect k=5 | 0.00225 | 0.0560 | -4.3% | [-0.00020, +0.00038] |
| oracle task-effect (cheat) | 0.00111 | 0.0405 | +48.7% | [-0.00271, -0.00015] |

kNN text k=5 minus random k=5 Brier, 95% task-bootstrap CI: [-0.00033, +0.00031] (negative = text neighbours beat random neighbours).
Spread of configuration pass rates (all tasks): min 0.98, P10 0.98, median 0.99, P90 1.00; configurations at 100%: 0/3. Spread of task pass rates (all configs): h-aliased-calls 0.80, h-discount-code 0.93, importers-of-storage 0.93, review-diff 0.93, fix-shop-total 0.97 (five hardest).

Nearest neighbours by TF-IDF cosine (first six tasks, sanity check):

| task | kind | 3 nearest (cosine) |
|---|---|---|
| add-count-items | edit | add-median (0.37), review-shop-diff (0.22), h-rename-trap (0.12) |
| add-median | edit | add-count-items (0.37), review-clean (0.14), discount-for (0.14) |
| calc-bugs-explain | explain | fix-calc (0.43), fix-shop-total (0.32), fix-rates (0.29) |
| callers-reserve | search | find-reserve-def (0.32), list-classes (0.23), rename-total (0.20) |
| class-in-file | search | file-for-class (0.30), list-classes (0.23), find-too-many-test (0.17) |
| count-tests | run | write-report-tests (0.33), write-pricing-tests (0.28), run-script (0.25) |

Router simulation: for each held-out task, the cheapest configuration (by its mean cost on the training tasks) whose predicted pass probability ≥ threshold; if none, the highest predicted. Realized pass = that configuration's observed rate on the held-out task; realized cost = its observed mean $/run there.

| policy | threshold | realized pass | mean $/run | configs chosen (top 3) |
|---|---|---|---|---|
| always ling-3.0-flash | – | 98.12% | 0.00025 | – |
| always Haiku 5.5 | – | 99.17% | 0.00144 | – |
| always cheapest config perfect on the other tasks | – | 99.17% | 0.00184 | deepseek-v4-flash-0731#off×47, claude-haiku-5.5×1 |
| router: prior (smoothed, a=2) | 0.9 | 98.12% | 0.00025 | ling-3.0-flash×48 |
| router: prior (smoothed, a=2) | 0.95 | 98.12% | 0.00025 | ling-3.0-flash×48 |
| router: prior (smoothed, a=2) | 0.98 | 98.12% | 0.00025 | ling-3.0-flash×48 |
| router: kNN text k=5 | 0.9 | 98.12% | 0.00025 | ling-3.0-flash×48 |
| router: kNN text k=5 | 0.95 | 98.54% | 0.00030 | ling-3.0-flash×43, deepseek-v4-flash-0731#off×5 |
| router: kNN text k=5 | 0.98 | 98.33% | 0.00061 | ling-3.0-flash×31, claude-haiku-5.5×12, deepseek-v4-flash-0731#off×5 |
| router: kNN text k=5 + prior (m=5) | 0.9 | 98.12% | 0.00025 | ling-3.0-flash×48 |
| router: kNN text k=5 + prior (m=5) | 0.95 | 98.12% | 0.00027 | ling-3.0-flash×47, claude-haiku-5.5×1 |
| router: kNN text k=5 + prior (m=5) | 0.98 | 98.33% | 0.00061 | ling-3.0-flash×31, claude-haiku-5.5×12, deepseek-v4-flash-0731#off×5 |
| router: kNN card k=5 + prior (m=5) | 0.9 | 98.12% | 0.00025 | ling-3.0-flash×48 |
| router: kNN card k=5 + prior (m=5) | 0.95 | 98.12% | 0.00029 | ling-3.0-flash×44, claude-haiku-5.5×4 |
| router: kNN card k=5 + prior (m=5) | 0.98 | 98.75% | 0.00055 | ling-3.0-flash×31, claude-haiku-5.5×10, deepseek-v4-flash-0731#off×7 |
| router: prior + kNN-text task-effect k=5 | 0.9 | 98.12% | 0.00025 | ling-3.0-flash×48 |
| router: prior + kNN-text task-effect k=5 | 0.95 | 98.12% | 0.00025 | ling-3.0-flash×47, deepseek-v4-flash-0731#off×1 |
| router: prior + kNN-text task-effect k=5 | 0.98 | 98.33% | 0.00061 | ling-3.0-flash×31, claude-haiku-5.5×11, deepseek-v4-flash-0731#off×6 |
| router: oracle task-effect (cheat) | 0.9 | 98.12% | 0.00027 | ling-3.0-flash×47, claude-haiku-5.5×1 |
| router: oracle task-effect (cheat) | 0.95 | 99.38% | 0.00034 | ling-3.0-flash×44, deepseek-v4-flash-0731#off×3, claude-haiku-5.5×1 |
| router: oracle task-effect (cheat) | 0.98 | 99.17% | 0.00066 | ling-3.0-flash×42, deepseek-v4-flash-0731#off×5, claude-haiku-5.5×1 |

**Caveats (R2).** Most cf2 cells have 1 trial, so per-cell labels are noisy and the prior itself is weak: constant ≈ prior. Task difficulty, not configuration identity, carries most of the variance, which is why the "true task effect" cheat helps Brier. That cheat is additive, though, so it also inflates cheap unreliable configurations on easy tasks, and it routes worse than the prior (cf2 91.1%). The "cheapest config perfect on the other tasks" baseline shows the winner's curse: in a fold, a 1-trial configuration that fails only the held-out task looks perfect and gets picked (cf2: 91.1%). TF-IDF over the store's own 14–48 prompts is a crude embedding, and a neural embedding could rank neighbours better. But the cheat ceiling bounds any task-level predictor, and the test-retest table below shows the target itself is barely repeatable. Probabilities are clipped to [0.01, 0.99] for both metrics.

# R2 addendum. Test-retest: is a (task, model) failure persistent across independent stores?

Any router (kNN or otherwise) can only work if a model's failure on a task recurs. cf6 re-ran the cf2 bank tasks and the cf3a hard tasks with the same three models (10 trials per cell in each store). Below: tasks with ≥1 failure in either store, failed/trials.

| stores | model | shared tasks | tasks failing in first | in second | in both | Spearman of per-task rates | failures first→second |
|---|---|---|---|---|---|---|---|
| cf2→cf6 | ling-3.0-flash | 28 | 2 | 2 | 1 | +0.44 | importers-of-storage 2/10→2/10; review-diff 0/10→2/10; warn-count 3/10→0/10 |
| cf2→cf6 | deepseek-v4-flash-0731#off | 28 | 2 | 1 | 0 | -0.05 | fix-shop-total 0/10→1/10; importers-of-storage 1/10→0/10; warn-count 5/10→0/10 |
| cf2→cf6 | claude-haiku-5.5 | 28 | 1 | 1 | 1 | +1.00 | review-clean 1/10→1/10 |
| cf3a→cf6 | ling-3.0-flash | 14 | 1 | 2 | 1 | +0.73 | h-aliased-calls 1/10→3/10; h-discount-code 0/10→2/10 |
| cf3a→cf6 | deepseek-v4-flash-0731#off | 14 | 1 | 0 | 0 | +nan | h-discount-code 1/10→0/10 |
| cf3a→cf6 | claude-haiku-5.5 | 14 | 1 | 1 | 1 | +1.00 | h-aliased-calls 1/10→3/10 |

**Reading.** Of the 11 (store pair, model, task) combinations that failed in either store, 4 failed in both. The recurring ones are ling on importers-of-storage (2/10→2/10) and h-aliased-calls (1/10→3/10), and Haiku on review-clean and h-aliased-calls; warn-count went from 3/10 for ling and 5/10 for deepseek in cf2 to 0/10 in cf6, which may be a harness change between commits. A (task, model) failure seen in one batch of 10 trials predicts the next batch only weakly, and that is the label any router would be trained on.

# R3. Difficulty signals cheaper than a router

Hypothesis: if difficulty tracks something visible before the run (prompt length, kind, editing vs reading), a one-line static rule could capture whatever routing headroom exists without a learned router.

Data: per-task aggregates. Failure measure = mean over models of the per-model failure rate on that task (equal model weight). 'Post-run' features (steps, tokens, seconds) are means over all models' runs on the task, so they describe how much work the task induced; they are not available to a router before the run but are available to a cascade after a cheap first attempt.


## cf6: 48 tasks, 3 models, 1439 runs, 14 failures on 6 tasks

Spearman correlation of the task's mean failure rate (over models) with each feature; p = two-sided permutation test (2,000 shuffles).

| feature | available before routing? | Spearman ρ | perm. p |
|---|---|---|---|
| prompt chars | pre-run | +0.05 | 0.735 |
| prompt words | pre-run | +0.06 | 0.685 |
| edits files (kind ∈ edit/fix/refactor/write-tests) | pre-run | +0.01 | 0.982 |
| agent = general (vs explore) | pre-run | -0.04 | 0.821 |
| mean files changed (passing runs) | post-run (outcome-tainted) | +0.01 | 0.917 |
| mean steps | post-run (outcome-tainted) | +0.12 | 0.433 |
| mean prompt tokens | post-run (outcome-tainted) | +0.04 | 0.789 |
| mean completion tokens | post-run (outcome-tainted) | +0.25 | 0.095 |
| mean seconds | post-run (outcome-tainted) | +0.28 | 0.057 |
| hard-tier task (h- prefix) | pre-run | +0.05 | 0.711 |

By card kind:

| kind | tasks | tasks with ≥1 failure | failures | mean failure rate |
|---|---|---|---|---|
| search | 8 | 2 | 8 | 3.3% |
| review | 4 | 2 | 3 | 2.5% |
| edit | 4 | 1 | 2 | 1.7% |
| fix | 5 | 1 | 1 | 0.7% |
| explain | 7 | 0 | 0 | 0.0% |
| run | 3 | 0 | 0 | 0.0% |
| write-tests | 3 | 0 | 0 | 0.0% |
| research | 6 | 0 | 0 | 0.0% |
| summarize | 5 | 0 | 0 | 0.0% |
| refactor | 3 | 0 | 0 | 0.0% |

Hardest tasks:

| task | kind | failures | mean fail rate | prompt chars | mean steps | mean prompt tok | mean seconds |
|---|---|---|---|---|---|---|---|
| h-aliased-calls | search | 6 | 20.0% | 135 | 3.5 | 7,874 | 17 |
| h-discount-code | edit | 2 | 6.7% | 385 | 10.0 | 80,482 | 37 |
| importers-of-storage | search | 2 | 6.7% | 99 | 3.0 | 6,444 | 18 |
| review-diff | review | 2 | 6.7% | 125 | 2.7 | 5,763 | 16 |
| fix-shop-total | fix | 1 | 3.3% | 93 | 9.5 | 61,568 | 21 |
| review-clean | review | 1 | 3.3% | 114 | 3.1 | 6,651 | 24 |
| add-count-items | edit | 0 | 0.0% | 157 | 4.0 | 23,390 | 16 |
| add-median | edit | 0 | 0.0% | 189 | 3.9 | 22,636 | 16 |

All-task medians for comparison: prompt chars 112, steps 3.1, prompt tokens 8,796, seconds 16.

### Static escalation rules, cf6 (deepseek#off at charged cost): ling by default, escalate to the named model when the rule fires (in-sample; equal task weight)

| rule fires on | escalate to | tasks escalated | pass | mean $/run |
|---|---|---|---|---|
| never (always ling) | deepseek-v4-flash-0731#off | 0 | 98.12% | 0.00025 |
| always | deepseek-v4-flash-0731#off | 48 | 99.79% | 0.00183 |
| edit-kind tasks | deepseek-v4-flash-0731#off | 15 | 98.33% | 0.00137 |
| read-only tasks | deepseek-v4-flash-0731#off | 33 | 99.58% | 0.00071 |
| prompt > median (112 chars) | deepseek-v4-flash-0731#off | 24 | 99.58% | 0.00086 |
| prompt > P75 (167 chars) | deepseek-v4-flash-0731#off | 11 | 98.54% | 0.00063 |
| edit-kind and prompt > median | deepseek-v4-flash-0731#off | 10 | 98.54% | 0.00067 |
| hard-tier (h-) tasks | deepseek-v4-flash-0731#off | 14 | 99.17% | 0.00043 |
| never (always ling) | claude-haiku-5.5 | 0 | 98.12% | 0.00025 |
| always | claude-haiku-5.5 | 48 | 99.17% | 0.00144 |
| edit-kind tasks | claude-haiku-5.5 | 15 | 98.54% | 0.00079 |
| read-only tasks | claude-haiku-5.5 | 33 | 98.75% | 0.00091 |
| prompt > median (112 chars) | claude-haiku-5.5 | 24 | 98.75% | 0.00094 |
| prompt > P75 (167 chars) | claude-haiku-5.5 | 11 | 98.54% | 0.00062 |
| edit-kind and prompt > median | claude-haiku-5.5 | 10 | 98.54% | 0.00063 |
| hard-tier (h-) tasks | claude-haiku-5.5 | 14 | 98.54% | 0.00072 |

## cf3a (all 25 models): 14 tasks, 25 models, 2226 runs, 70 failures on 9 tasks

Spearman correlation of the task's mean failure rate (over models) with each feature; p = two-sided permutation test (2,000 shuffles).

| feature | available before routing? | Spearman ρ | perm. p |
|---|---|---|---|
| prompt chars | pre-run | -0.33 | 0.240 |
| prompt words | pre-run | -0.34 | 0.225 |
| edits files (kind ∈ edit/fix/refactor/write-tests) | pre-run | -0.37 | 0.199 |
| agent = general (vs explore) | pre-run | -0.34 | 0.233 |
| mean files changed (passing runs) | post-run (outcome-tainted) | -0.26 | 0.362 |
| mean steps | post-run (outcome-tainted) | -0.11 | 0.685 |
| mean prompt tokens | post-run (outcome-tainted) | -0.06 | 0.842 |
| mean completion tokens | post-run (outcome-tainted) | -0.04 | 0.890 |
| mean seconds | post-run (outcome-tainted) | +0.00 | 0.997 |

By card kind:

| kind | tasks | tasks with ≥1 failure | failures | mean failure rate |
|---|---|---|---|---|
| search | 1 | 1 | 18 | 12.8% |
| edit | 2 | 1 | 27 | 10.5% |
| explain | 1 | 1 | 4 | 3.5% |
| research | 3 | 2 | 10 | 3.2% |
| run | 1 | 1 | 3 | 2.1% |
| summarize | 1 | 1 | 4 | 1.6% |
| fix | 2 | 1 | 2 | 1.3% |
| review | 1 | 1 | 2 | 0.8% |
| write-tests | 1 | 0 | 0 | 0.0% |
| refactor | 1 | 0 | 0 | 0.0% |

Hardest tasks:

| task | kind | failures | mean fail rate | prompt chars | mean steps | mean prompt tok | mean seconds |
|---|---|---|---|---|---|---|---|
| h-discount-code | edit | 27 | 21.1% | 385 | 14.0 | 75,677 | 72 |
| h-aliased-calls | search | 18 | 12.8% | 135 | 4.2 | 7,132 | 23 |
| h-log-correlate | research | 6 | 6.1% | 157 | 5.1 | 45,830 | 39 |
| h-import-cycle | research | 4 | 3.5% | 90 | 4.0 | 7,595 | 30 |
| h-retry-explain | explain | 4 | 3.5% | 178 | 2.9 | 4,477 | 21 |
| h-unit-bug | fix | 2 | 2.7% | 93 | 7.0 | 20,509 | 29 |
| h-crash-diagnose | run | 3 | 2.1% | 166 | 3.7 | 10,721 | 22 |
| h-incidents | summarize | 4 | 1.6% | 165 | 3.4 | 7,668 | 25 |

All-task medians for comparison: prompt chars 166, steps 4.7, prompt tokens 11,486, seconds 29.

### Static escalation rules, cf3a: ling by default, escalate to the named model when the rule fires (in-sample; equal task weight)

| rule fires on | escalate to | tasks escalated | pass | mean $/run |
|---|---|---|---|---|
| never (always ling) | claude-haiku-5.5 | 0 | 99.29% | 0.00031 |
| always | claude-haiku-5.5 | 14 | 99.29% | 0.00154 |
| edit-kind tasks | claude-haiku-5.5 | 6 | 99.29% | 0.00087 |
| read-only tasks | claude-haiku-5.5 | 8 | 99.29% | 0.00098 |
| prompt > median (166 chars) | claude-haiku-5.5 | 7 | 99.29% | 0.00090 |
| prompt > P75 (226 chars) | claude-haiku-5.5 | 3 | 99.29% | 0.00066 |
| edit-kind and prompt > median | claude-haiku-5.5 | 4 | 99.29% | 0.00074 |
| hard-tier (h-) tasks | claude-haiku-5.5 | 14 | 99.29% | 0.00154 |
| never (always ling) | deepseek-v4-flash-0731#off | 0 | 99.29% | 0.00031 |
| always | deepseek-v4-flash-0731#off | 14 | 99.29% | 0.00068 |
| edit-kind tasks | deepseek-v4-flash-0731#off | 6 | 98.57% | 0.00049 |
| read-only tasks | deepseek-v4-flash-0731#off | 8 | 100.00% | 0.00050 |
| prompt > median (166 chars) | deepseek-v4-flash-0731#off | 7 | 98.57% | 0.00049 |
| prompt > P75 (226 chars) | deepseek-v4-flash-0731#off | 3 | 98.57% | 0.00041 |
| edit-kind and prompt > median | deepseek-v4-flash-0731#off | 4 | 98.57% | 0.00044 |
| hard-tier (h-) tasks | deepseek-v4-flash-0731#off | 14 | 99.29% | 0.00068 |

## cf2 (205 full-coverage configurations): 28 tasks, 205 models, 9492 runs, 496 failures on 25 tasks

Spearman correlation of the task's mean failure rate (over models) with each feature; p = two-sided permutation test (2,000 shuffles).

| feature | available before routing? | Spearman ρ | perm. p |
|---|---|---|---|
| prompt chars | pre-run | +0.20 | 0.299 |
| prompt words | pre-run | +0.22 | 0.254 |
| edits files (kind ∈ edit/fix/refactor/write-tests) | pre-run | -0.26 | 0.200 |
| agent = general (vs explore) | pre-run | -0.30 | 0.135 |
| mean files changed (passing runs) | post-run (outcome-tainted) | -0.21 | 0.284 |
| mean steps | post-run (outcome-tainted) | +0.10 | 0.599 |
| mean prompt tokens | post-run (outcome-tainted) | +0.15 | 0.423 |
| mean completion tokens | post-run (outcome-tainted) | +0.38 | 0.051 |
| mean seconds | post-run (outcome-tainted) | +0.32 | 0.090 |

By card kind:

| kind | tasks | tasks with ≥1 failure | failures | mean failure rate |
|---|---|---|---|---|
| review | 2 | 2 | 76 | 14.1% |
| research | 3 | 3 | 90 | 12.7% |
| summarize | 4 | 3 | 119 | 11.0% |
| write-tests | 1 | 1 | 18 | 7.5% |
| search | 6 | 5 | 137 | 7.0% |
| explain | 5 | 5 | 39 | 2.8% |
| refactor | 2 | 2 | 9 | 1.9% |
| run | 2 | 2 | 5 | 1.2% |
| edit | 1 | 1 | 1 | 0.5% |
| fix | 2 | 1 | 2 | 0.5% |

Hardest tasks:

| task | kind | failures | mean fail rate | prompt chars | mean steps | mean prompt tok | mean seconds |
|---|---|---|---|---|---|---|---|
| warn-count | summarize | 108 | 38.8% | 69 | 4.2 | 27,737 | 34 |
| importers-of-storage | search | 103 | 30.1% | 99 | 4.2 | 6,987 | 21 |
| warn-top-component | research | 50 | 19.7% | 74 | 5.2 | 41,112 | 33 |
| review-clean | review | 51 | 18.3% | 114 | 3.4 | 5,259 | 27 |
| sum-csv | research | 35 | 16.7% | 90 | 3.8 | 5,695 | 20 |
| review-diff | review | 25 | 9.9% | 125 | 3.1 | 4,749 | 24 |
| discount-for | explain | 22 | 9.1% | 173 | 2.4 | 3,642 | 21 |
| write-pricing-tests | write-tests | 18 | 7.5% | 269 | 8.7 | 31,823 | 53 |

All-task medians for comparison: prompt chars 102, steps 3.7, prompt tokens 6,537, seconds 21.

**Caveats (R3).** With 6 failing tasks on cf6 and 9 on cf3a, the correlations have almost no power (a |ρ| of 0.3 is p ≈ 0.1–0.2). The sign of the pre-run features flips between stores: on cf3a, longer and edit prompts are slightly *easier*; on cf2, longer prompts are slightly harder. The static-rule tables are in-sample, and the `h-` prefix is an eval-bank artifact that production tasks don't carry. Could a static rule beat kNN? On cf6, "escalate prompts > P75 to deepseek#off" gives the same 98.54% as the kNN router at about 2× its cost. "Hard-tier → deepseek#off" gives 99.17% at $0.00043, but only because it is fitted to where the failures happened to fall. On cf3a no rule improves on always-ling. Neither approach beats always-ling by a margin the data can distinguish from noise.

# R4. Price sensitivity of the pool's ordering (arithmetic only)

Cost per success (CPS) = mean $/run ÷ pass rate (the expected spend per success if failures are detected and retried on the same model). 'ling price × to tie' = how far ling's price must rise before the row's model has the lower CPS (= CPS_row / CPS_ling); values < 1× mean the row is already cheaper per success. 'Break-even failure cost' = the cost of one undetected failure F at which always-row equals always-ling in expected cost, (c_row − c_ling) / (p_row − p_ling): routing to the dearer model pays only if a silent failure costs more than this. 'Cascade' = ling first, escalate the failures (assumes failures are detected) to the row's model: expected $/task and pass. Rows are compared with ling on the same task mix (pooled block vs ling pooled; hard block vs ling on cf3a).

| model | task mix | mean $/run | pass rate | $/success | ling price × to tie | break-even failure cost | cascade ling→row: $/task (pass) |
|---|---|---|---|---|---|---|---|
| ling-3.0-flash | bank+hard pooled (cf2+cf6+cf3a) | 0.00024 | 98.3% (884/899; Laplace 98.2%) | 0.00024 | – | – | – |
| deepseek-v4-flash-0731#off @ $0.00045 | bank+hard pooled | 0.00045 | 99.1% (892/900; Laplace 99.0%) | 0.00045 | 1.86× | $0.027 | 0.00025 (99.99%) |
| deepseek-v4-flash-0731#off @ $0.00183 | bank+hard pooled | 0.00183 | 99.1% (892/900; Laplace 99.0%) | 0.00185 | 7.57× | $0.204 | 0.00027 (99.99%) |
| mercury-2.5 | cf2+cf3a (no cf6; harder mix) | 0.00060 | 94.0% (395/420; Laplace 93.8%) | 0.00064 | 2.61× | never (not more reliable) | 0.00025 (99.90%) |
| claude-haiku-5.5 | bank+hard pooled | 0.00132 | 99.3% (894/900; Laplace 99.2%) | 0.00133 | 5.44× | $0.108 | 0.00026 (99.99%) |
| ling-3.0-flash | hard tier (cf3a) | 0.00031 | 99.3% (139/140; Laplace 98.6%) | 0.00031 | – | – | – |
| claude-haiku-5.5 | hard tier (cf3a) | 0.00154 | 99.3% (139/140; Laplace 98.6%) | 0.00155 | 4.97× | never (not more reliable) | 0.00032 (99.99%) |
| claude-sonnet-5.5 | hard tier (cf3b) | 0.02286 | 100.0% (42/42; Laplace 97.7%) | 0.02286 | 73.22× | $3.157 | 0.00047 (100.00%) |
| gemini-4-argon | hard tier (cf3b) | 0.03488 | 100.0% (42/42; Laplace 97.7%) | 0.03488 | 111.71× | $4.840 | 0.00056 (100.00%) |
| claude-opus-5.5 | hard tier (cf3b) | 0.04582 | 100.0% (42/42; Laplace 97.7%) | 0.04582 | 146.75× | $6.371 | 0.00064 (100.00%) |

Caveats: frontier pass rates are 42/42 (95% one-sided lower bound ≈ 93%); the break-even for them uses the observed 100%, so with Laplace smoothing (97.7%) Opus/Sonnet would not beat ling's 99.3% at all on the hard tier. mercury-2.5's mix excludes cf6. The pass-rate gaps (≤ 1 pt) rest on 6–15 failures per model, so break-even figures carry roughly ±50% uncertainty.
Cascade pass assumes the second model's failures are independent of ling's. R1 shows they are not (Haiku passes 92%, not 99%, of tasks ling fails), so the true cascade pass is about 99.8–99.9%. The cascade also assumes failures are detected, which requires a verifier.
