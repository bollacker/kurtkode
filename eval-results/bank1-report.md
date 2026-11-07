Runs: 612 recorded, 332 degraded copies; 3609 judgments. (127 stray-edit copies of read-only tasks left out: explore agents can't edit.)

### Subagent models (real runs, all trials)

| model | pass rate (95% CI) | mean s | mean steps | mean tokens in/out | list $ per run |
|---|---|---|---|---|---|
| bang:qwen/qwen3.5-9b | 88% (81–93%) 90/102 | 32 | 5.7 | 16422/971 | – |
| google-gemini:gemini-3.6-flash | 100% (96–100%) 102/102 | 12 | 7.3 | 19850/1322 | 0.0197 |
| google-gemini:gemini-3.8-flash | 100% (96–100%) 102/102 | 17 | 7.3 | 19845/1197 | 0.0195 |
| google-gemini:gemini-4-argon | 100% (96–100%) 102/102 | 19 | 3.6 | 8180/513 | 0.0207 |
| lmstudio:gemma-4-e4b-it | 81% (73–88%) 83/102 | 80 | 5.0 | 11525/1878 | – |
| lmstudio:google/gemma-4-26b-a4b-qat | 89% (82–94%) 91/102 | 58 | 5.6 | 11942/1189 | – |

Passes by kind:

| model | edit | explain | fix | refactor | research | review | run | search | summarize | write-tests |
|---|---|---|---|---|---|---|---|---|---|---|
| bang:qwen/qwen3.5-9b | 6/6 | 16/18 | 9/9 | 6/6 | 8/9 | 7/9 | 6/6 | 16/21 | 10/12 | 6/6 |
| google-gemini:gemini-3.6-flash | 6/6 | 18/18 | 9/9 | 6/6 | 9/9 | 9/9 | 6/6 | 21/21 | 12/12 | 6/6 |
| google-gemini:gemini-3.8-flash | 6/6 | 18/18 | 9/9 | 6/6 | 9/9 | 9/9 | 6/6 | 21/21 | 12/12 | 6/6 |
| google-gemini:gemini-4-argon | 6/6 | 18/18 | 9/9 | 6/6 | 9/9 | 9/9 | 6/6 | 21/21 | 12/12 | 6/6 |
| lmstudio:gemma-4-e4b-it | 3/6 | 15/18 | 8/9 | 6/6 | 6/9 | 7/9 | 6/6 | 18/21 | 10/12 | 4/6 |
| lmstudio:google/gemma-4-26b-a4b-qat | 6/6 | 18/18 | 9/9 | 6/6 | 6/9 | 6/9 | 6/6 | 18/21 | 12/12 | 4/6 |

### Judges against gold

A verdict of 0–1 is "fail", 2–3 "pass". Failures are real failed runs and degraded copies.

All runs each judge rated:

| judge (path) | runs | no verdict | agreement | kappa | failures caught (95% CI) | passes failed (95% CI) | claimed unchecked | list $ |
|---|---|---|---|---|---|---|---|---|
| bang:qwen/qwen3.5-9b (grader) | 320 | 0 | 76% | 0.50 | 63% (55–71%) 87/138 | 14% (9–19%) 25/182 | 0 | – |
| bang:qwen/qwen3.5-9b (parent) | 320 | 16 | 81% | 0.58 | 58% (49–66%) 72/125 | 3% (2–7%) 6/179 | 71 | – |
| google-gemini:gemini-3.8-flash (grader) | 536 | 0 | 73% | 0.49 | 59% (54–64%) 205/346 | 2% (1–5%) 4/190 | 0 | 1.430 |
| google-gemini:gemini-3.8-flash (parent) | 536 | 6 | 84% | 0.68 | 75% (70–79%) 256/341 | 0% (0–2%) 0/189 | 2 | 5.223 |
| google-gemini:gemini-4-argon (grader) | 536 | 0 | 73% | 0.49 | 58% (53–63%) 202/346 | 1% (0–4%) 2/190 | 0 | 1.718 |
| google-gemini:gemini-4-argon (parent) | 536 | 1 | 84% | 0.69 | 76% (71–80%) 262/345 | 0% (0–2%) 0/190 | 0 | 8.312 |
| lmstudio:google/gemma-4-26b-a4b-qat (grader) | 262 | 3 | 77% | 0.51 | 52% (43–61%) 61/118 | 2% (1–6%) 3/141 | 0 | – |
| lmstudio:google/gemma-4-26b-a4b-qat (parent) | 262 | 50 | 82% | 0.63 | 62% (52–71%) 60/97 | 1% (0–5%) 1/115 | 5 | – |

Only the 262 runs every judge rated (118 failures):

| judge (path) | runs | no verdict | agreement | kappa | failures caught (95% CI) | passes failed (95% CI) | claimed unchecked | list $ |
|---|---|---|---|---|---|---|---|---|
| bang:qwen/qwen3.5-9b (grader) | 262 | 0 | 74% | 0.47 | 60% (51–69%) 71/118 | 14% (9–20%) 20/144 | 0 | – |
| bang:qwen/qwen3.5-9b (parent) | 262 | 10 | 80% | 0.57 | 58% (48–67%) 63/109 | 3% (2–8%) 5/143 | 56 | – |
| google-gemini:gemini-3.8-flash (grader) | 262 | 0 | 78% | 0.53 | 53% (44–62%) 63/118 | 2% (1–6%) 3/144 | 0 | 0.665 |
| google-gemini:gemini-3.8-flash (parent) | 262 | 2 | 85% | 0.68 | 66% (56–74%) 76/116 | 0% (0–3%) 0/144 | 0 | 2.516 |
| google-gemini:gemini-4-argon (grader) | 262 | 0 | 77% | 0.53 | 52% (43–61%) 61/118 | 1% (0–5%) 2/144 | 0 | 0.856 |
| google-gemini:gemini-4-argon (parent) | 262 | 0 | 86% | 0.71 | 69% (61–77%) 82/118 | 0% (0–3%) 0/144 | 0 | 3.937 |
| lmstudio:google/gemma-4-26b-a4b-qat (grader) | 262 | 3 | 77% | 0.51 | 52% (43–61%) 61/118 | 2% (1–6%) 3/141 | 0 | – |
| lmstudio:google/gemma-4-26b-a4b-qat (parent) | 262 | 50 | 82% | 0.63 | 62% (52–71%) 60/97 | 1% (0–5%) 1/115 | 5 | – |

### Grounded checks, and judges combined with them

|  | failures caught (95% CI) | passes failed (95% CI) |
|---|---|---|
| checks at the run's end | 14% (11–18%) 48/346 | 1% (0–3%) 1/190 |
| checks and the re-run check | 35% (30–40%) 121/346 | 1% (0–3%) 1/190 |
| grounded + bang:qwen/qwen3.5-9b (grader) | 71% (63–78%) 98/138 | 14% (9–19%) 25/182 |
| grounded + bang:qwen/qwen3.5-9b (parent) | 58% (50–66%) 80/138 | 3% (2–7%) 6/182 |
| grounded + google-gemini:gemini-3.8-flash (grader) | 68% (63–73%) 235/346 | 2% (1–5%) 4/190 |
| grounded + google-gemini:gemini-3.8-flash (parent) | 74% (69–79%) 257/346 | 1% (0–3%) 1/190 |
| grounded + google-gemini:gemini-4-argon (grader) | 68% (63–73%) 235/346 | 2% (1–5%) 3/190 |
| grounded + google-gemini:gemini-4-argon (parent) | 76% (71–80%) 263/346 | 1% (0–3%) 1/190 |
| grounded + lmstudio:google/gemma-4-26b-a4b-qat (grader) | 62% (53–70%) 73/118 | 2% (1–6%) 3/144 |
| grounded + lmstudio:google/gemma-4-26b-a4b-qat (parent) | 56% (47–65%) 66/118 | 1% (0–4%) 1/144 |

### Failures caught, by kind of failure

| failure | grounded | bang:qwen/qwen3.5-9b (grader) | bang:qwen/qwen3.5-9b (parent) | google-gemini:gemini-3.8-flash (grader) | google-gemini:gemini-3.8-flash (parent) | google-gemini:gemini-4-argon (grader) | google-gemini:gemini-4-argon (parent) | lmstudio:google/gemma-4-26b-a4b-qat (grader) | lmstudio:google/gemma-4-26b-a4b-qat (parent) |
|---|---|---|---|---|---|---|---|---|---|
| digits | 28/101 | 31/34 | 30/32 | 87/101 | 94/101 | 87/101 | 94/100 | 27/30 | 21/22 |
| drop-half | 0/43 | 11/19 | 4/17 | 17/43 | 34/43 | 17/43 | 33/43 | 4/12 | 3/9 |
| real | 2/14 | 8/14 | 4/13 | 5/14 | 8/14 | 5/14 | 10/14 | 4/14 | 2/10 |
| stray-edit | 0/63 | 3/26 | 0/26 | 0/63 | 0/63 | 0/63 | 0/63 | 1/25 | 0/22 |
| undo-all | 51/51 | 10/18 | 13/13 | 34/51 | 51/51 | 32/51 | 51/51 | 8/15 | 15/15 |
| undo-half | 18/18 | 5/6 | 4/4 | 13/18 | 18/18 | 12/18 | 18/18 | 3/6 | 6/6 |
| vanish | 12/12 | 5/7 | 6/6 | 5/12 | 12/12 | 5/12 | 12/12 | 3/5 | 5/5 |
| wrong-file | 10/44 | 14/14 | 11/14 | 44/44 | 39/39 | 44/44 | 44/44 | 11/11 | 8/8 |

### Judging its own model's runs, and others'

| judge (path) | own runs: agreement | own runs: failures caught | others' runs: agreement | others' runs: failures caught |
|---|---|---|---|---|
| bang:qwen/qwen3.5-9b (grader) | 41/57 | 61% (42–76%) 17/28 | 203/263 | 64% (54–72%) 70/110 |
| bang:qwen/qwen3.5-9b (parent) | 37/53 | 44% (27–63%) 11/25 | 208/251 | 61% (51–70%) 61/100 |
| google-gemini:gemini-3.8-flash (grader) | 76/93 | 73% (60–83%) 43/59 | 315/443 | 56% (51–62%) 162/287 |
| google-gemini:gemini-3.8-flash (parent) | 78/92 | 76% (63–85%) 44/58 | 367/438 | 75% (70–80%) 212/283 |
| google-gemini:gemini-4-argon (grader) | 73/92 | 67% (54–78%) 39/58 | 317/444 | 57% (51–62%) 163/288 |
| google-gemini:gemini-4-argon (parent) | 77/92 | 74% (62–84%) 43/58 | 375/443 | 76% (71–81%) 219/287 |
| lmstudio:google/gemma-4-26b-a4b-qat (grader) | 27/37 | 38% (18–61%) 6/16 | 172/222 | 54% (44–63%) 55/102 |
| lmstudio:google/gemma-4-26b-a4b-qat (parent) | 25/30 | 55% (28–79%) 6/11 | 149/182 | 63% (52–72%) 54/86 |
