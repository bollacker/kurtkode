Runs: 123 recorded, 81 degraded copies; 3807 judgments. (32 stray-edit copies of read-only tasks left out: explore agents can't edit.)

### Cheapest above the floor

Configurations whose 95% Wilson lower bound on success clears the floor, cheapest per run first (list price; local models are timed, not priced, and are listed after).

**80%**: google-gemini:gemini-3.6-flash $0.0182/run, $0.0182/success (20/20, lower 84%); google-gemini:gemini-4-argon $0.0189/run, $0.0189/success (21/21, lower 85%); google-gemini:gemini-3.8-flash $0.0237/run, $0.0237/success (18/18, lower 82%)

**90%**: none priced

**95%**: none priced

### Subagent models (real runs, all trials)

| model | pass rate (95% CI) | mean s | mean steps | mean tokens in/out | list $ per run | $ per success |
|---|---|---|---|---|---|---|
| bang:qwen/qwen3.5-9b | 87% (68–95%) 20/23 | 38 | 6.7 | 21853/1096 | – | – |
| google-gemini:gemini-3.6-flash | 100% (84–100%) 20/20 | 12 | 6.8 | 17765/1311 | 0.0182 | 0.0182 |
| google-gemini:gemini-3.8-flash | 100% (82–100%) 18/18 | 18 | 7.6 | 24178/1489 | 0.0237 | 0.0237 |
| google-gemini:gemini-4-argon | 100% (85–100%) 21/21 | 15 | 3.2 | 7064/494 | 0.0189 | 0.0189 |
| lmstudio:gemma-4-e4b-it | 76% (55–89%) 16/21 | 91 | 5.6 | 13468/2140 | – | – |
| lmstudio:google/gemma-4-26b-a4b-qat | 95% (76–99%) 19/20 | 57 | 5.5 | 12191/1138 | – | – |

Passes by kind:

| model | edit | explain | fix | refactor | research | review | run | search | summarize | write-tests |
|---|---|---|---|---|---|---|---|---|---|---|
| bang:qwen/qwen3.5-9b | 2/2 | 2/3 | 2/2 | 2/2 | 2/2 | 2/3 | – | 5/6 | 2/2 | 1/1 |
| google-gemini:gemini-3.6-flash | 1/1 | 4/4 | 1/1 | 1/1 | – | 2/2 | – | 7/7 | 2/2 | 2/2 |
| google-gemini:gemini-3.8-flash | 1/1 | 4/4 | – | 1/1 | 1/1 | 3/3 | – | 5/5 | 2/2 | 1/1 |
| google-gemini:gemini-4-argon | 2/2 | 6/6 | – | 1/1 | – | 3/3 | – | 5/5 | 3/3 | 1/1 |
| lmstudio:gemma-4-e4b-it | 0/2 | 5/5 | 1/2 | 1/1 | 0/1 | – | 1/1 | 6/7 | 2/2 | – |
| lmstudio:google/gemma-4-26b-a4b-qat | 1/1 | 5/5 | 1/1 | 1/1 | – | 2/2 | – | 4/5 | 4/4 | 1/1 |

### Judges against gold

A verdict of 0–1 is "fail", 2–3 "pass". Failures are real failed runs and degraded copies.

All runs each judge rated:

| judge (path) | runs | no verdict | agreement | kappa | failures caught (95% CI) | passes failed (95% CI) | claimed unchecked | list $ |
|---|---|---|---|---|---|---|---|---|
| bang:qwen/qwen3.5-9b (grader) | 204 | 0 | 75% | 0.49 | 57% (46–66%) 51/90 | 10% (5–16%) 11/114 | 0 | – |
| bang:qwen/qwen3.5-9b (parent) | 204 | 0 | 79% | 0.56 | 58% (47–67%) 52/90 | 4% (2–10%) 5/114 | 44 | – |
| google-gemini:gemini-3.8-flash (grader) | 204 | 0 | 78% | 0.53 | 51% (41–61%) 46/90 | 1% (0–5%) 1/114 | 0 | 0.491 |
| google-gemini:gemini-3.8-flash (parent) | 204 | 0 | 84% | 0.66 | 63% (53–73%) 57/90 | 0% (0–3%) 0/114 | 0 | 1.803 |
| google-gemini:gemini-4-argon (grader) | 204 | 0 | 77% | 0.52 | 51% (41–61%) 46/90 | 2% (0–6%) 2/114 | 0 | 0.654 |
| google-gemini:gemini-4-argon (parent) | 204 | 0 | 86% | 0.71 | 69% (59–78%) 62/90 | 0% (0–3%) 0/114 | 0 | 2.874 |
| lmstudio:google/gemma-4-26b-a4b-qat (grader) | 204 | 2 | 77% | 0.50 | 49% (39–59%) 44/90 | 1% (0–5%) 1/112 | 0 | – |
| lmstudio:google/gemma-4-26b-a4b-qat (parent) | 204 | 0 | 82% | 0.63 | 61% (51–71%) 55/90 | 1% (0–5%) 1/114 | 5 | – |
| openrouter:anthropic/claude-haiku-5.5 (parent) | 204 | 0 | 84% | 0.67 | 67% (56–76%) 60/90 | 2% (0–6%) 2/114 | 1 | 0.228 |
| openrouter:deepseek/deepseek-v4-flash (parent) | 204 | 11 | 83% | 0.64 | 61% (51–71%) 51/83 | 0% (0–3%) 0/110 | 7 | 0.152 |
| openrouter:deepseek/deepseek-v4-flash-0731 (parent) | 204 | 3 | 82% | 0.61 | 59% (49–68%) 53/90 | 0% (0–3%) 0/111 | 8 | 0.090 |
| openrouter:inception/mercury-3 (parent) | 204 | 2 | 83% | 0.63 | 61% (50–70%) 54/89 | 0% (0–3%) 0/113 | 4 | 0.104 |
| openrouter:inclusionai/ling-3.0-flash (parent) | 204 | 5 | 81% | 0.60 | 57% (47–67%) 50/87 | 0% (0–3%) 0/112 | 18 | 0.034 |
| openrouter:inclusionai/ling-3.1-flash (parent) | 204 | 3 | 85% | 0.69 | 67% (56–76%) 60/90 | 0% (0–3%) 0/111 | 6 | 0.119 |
| openrouter:openai/gpt-6-luna (parent) | 204 | 0 | 81% | 0.60 | 61% (51–71%) 55/90 | 4% (1–9%) 4/114 | 11 | 0.104 |
| openrouter:poolside/laguna-s-2.1 (parent) | 204 | 11 | 81% | 0.59 | 55% (45–66%) 46/83 | 0% (0–3%) 0/110 | 13 | 0.108 |
| openrouter:qwen/qwen3.7-flash (parent) | 204 | 7 | 84% | 0.65 | 62% (52–72%) 53/85 | 0% (0–3%) 0/112 | 25 | 0.056 |
| openrouter:z-ai/glm-4.7-flash (parent) | 204 | 14 | 82% | 0.61 | 60% (49–70%) 51/85 | 1% (0–5%) 1/105 | 8 | 0.143 |

### Grounded checks, and judges combined with them

|  | failures caught (95% CI) | passes failed (95% CI) |
|---|---|---|
| checks at the run's end | 12% (7–21%) 11/90 | 1% (0–5%) 1/114 |
| checks and the re-run check | 33% (24–44%) 30/90 | 1% (0–5%) 1/114 |
| grounded + bang:qwen/qwen3.5-9b (grader) | 67% (56–76%) 60/90 | 10% (5–16%) 11/114 |
| grounded + bang:qwen/qwen3.5-9b (parent) | 58% (47–67%) 52/90 | 4% (2–10%) 5/114 |
| grounded + google-gemini:gemini-3.8-flash (grader) | 61% (51–71%) 55/90 | 1% (0–5%) 1/114 |
| grounded + google-gemini:gemini-3.8-flash (parent) | 63% (53–73%) 57/90 | 1% (0–5%) 1/114 |
| grounded + google-gemini:gemini-4-argon (grader) | 62% (52–72%) 56/90 | 3% (1–7%) 3/114 |
| grounded + google-gemini:gemini-4-argon (parent) | 69% (59–78%) 62/90 | 1% (0–5%) 1/114 |
| grounded + lmstudio:google/gemma-4-26b-a4b-qat (grader) | 61% (51–71%) 55/90 | 1% (0–5%) 1/114 |
| grounded + lmstudio:google/gemma-4-26b-a4b-qat (parent) | 61% (51–71%) 55/90 | 1% (0–5%) 1/114 |
| grounded + openrouter:anthropic/claude-haiku-5.5 (parent) | 67% (56–76%) 60/90 | 2% (0–6%) 2/114 |
| grounded + openrouter:deepseek/deepseek-v4-flash (parent) | 59% (49–68%) 53/90 | 1% (0–5%) 1/114 |
| grounded + openrouter:deepseek/deepseek-v4-flash-0731 (parent) | 60% (50–70%) 54/90 | 1% (0–5%) 1/114 |
| grounded + openrouter:inception/mercury-3 (parent) | 60% (50–70%) 54/90 | 1% (0–5%) 1/114 |
| grounded + openrouter:inclusionai/ling-3.0-flash (parent) | 58% (47–67%) 52/90 | 1% (0–5%) 1/114 |
| grounded + openrouter:inclusionai/ling-3.1-flash (parent) | 67% (56–76%) 60/90 | 1% (0–5%) 1/114 |
| grounded + openrouter:openai/gpt-6-luna (parent) | 61% (51–71%) 55/90 | 4% (1–9%) 4/114 |
| grounded + openrouter:poolside/laguna-s-2.1 (parent) | 54% (44–64%) 49/90 | 1% (0–5%) 1/114 |
| grounded + openrouter:qwen/qwen3.7-flash (parent) | 61% (51–71%) 55/90 | 1% (0–5%) 1/114 |
| grounded + openrouter:z-ai/glm-4.7-flash (parent) | 58% (47–67%) 52/90 | 1% (0–5%) 1/114 |

### Failures caught, by kind of failure

| failure | grounded | bang:qwen/qwen3.5-9b (grader) | bang:qwen/qwen3.5-9b (parent) | google-gemini:gemini-3.8-flash (grader) | google-gemini:gemini-3.8-flash (parent) | google-gemini:gemini-4-argon (grader) | google-gemini:gemini-4-argon (parent) | lmstudio:google/gemma-4-26b-a4b-qat (grader) | lmstudio:google/gemma-4-26b-a4b-qat (parent) | openrouter:anthropic/claude-haiku-5.5 (parent) | openrouter:deepseek/deepseek-v4-flash (parent) | openrouter:deepseek/deepseek-v4-flash-0731 (parent) | openrouter:inception/mercury-3 (parent) | openrouter:inclusionai/ling-3.0-flash (parent) | openrouter:inclusionai/ling-3.1-flash (parent) | openrouter:openai/gpt-6-luna (parent) | openrouter:poolside/laguna-s-2.1 (parent) | openrouter:qwen/qwen3.7-flash (parent) | openrouter:z-ai/glm-4.7-flash (parent) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| digits | 6/22 | 21/22 | 21/22 | 21/22 | 21/22 | 21/22 | 21/22 | 21/22 | 21/22 | 21/22 | 20/21 | 18/22 | 19/21 | 19/21 | 21/22 | 20/22 | 18/22 | 18/20 | 20/21 |
| drop-half | 0/8 | 4/8 | 2/8 | 3/8 | 3/8 | 3/8 | 5/8 | 3/8 | 3/8 | 4/8 | 3/8 | 3/8 | 1/8 | 3/8 | 4/8 | 3/8 | 0/6 | 3/8 | 1/7 |
| real | 1/9 | 5/9 | 2/9 | 2/9 | 4/9 | 3/9 | 7/9 | 1/9 | 2/9 | 6/9 | 3/9 | 4/9 | 6/9 | 2/9 | 7/9 | 3/9 | 3/9 | 5/9 | 2/9 |
| stray-edit | 0/22 | 1/22 | 0/22 | 0/22 | 0/22 | 0/22 | 0/22 | 1/22 | 0/22 | 0/22 | 0/19 | 0/22 | 0/22 | 0/22 | 0/22 | 0/22 | 1/22 | 0/20 | 1/20 |
| undo-all | 12/12 | 5/12 | 12/12 | 6/12 | 12/12 | 6/12 | 12/12 | 5/12 | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 9/9 | 12/12 | 11/11 |
| undo-half | 4/4 | 3/4 | 4/4 | 3/4 | 4/4 | 2/4 | 4/4 | 2/4 | 4/4 | 4/4 | 3/3 | 4/4 | 4/4 | 4/4 | 4/4 | 4/4 | 4/4 | 3/3 | 4/4 |
| vanish | 5/5 | 4/5 | 5/5 | 3/5 | 5/5 | 3/5 | 5/5 | 3/5 | 5/5 | 5/5 | 4/4 | 5/5 | 5/5 | 4/4 | 5/5 | 5/5 | 5/5 | 5/5 | 5/5 |
| wrong-file | 2/8 | 8/8 | 6/8 | 8/8 | 8/8 | 8/8 | 8/8 | 8/8 | 8/8 | 8/8 | 6/7 | 7/8 | 7/8 | 6/7 | 7/8 | 8/8 | 6/6 | 7/8 | 7/8 |

### Judging its own model's runs, and others'

| judge (path) | own runs: agreement | own runs: failures caught | others' runs: agreement | others' runs: failures caught |
|---|---|---|---|---|
| bang:qwen/qwen3.5-9b (grader) | 30/40 | 60% (39–78%) 12/20 | 124/164 | 56% (44–67%) 39/70 |
| bang:qwen/qwen3.5-9b (parent) | 28/40 | 45% (26–66%) 9/20 | 133/164 | 61% (50–72%) 43/70 |
| google-gemini:gemini-3.8-flash (grader) | 29/36 | 61% (39–80%) 11/18 | 130/168 | 49% (37–60%) 35/72 |
| google-gemini:gemini-3.8-flash (parent) | 29/36 | 61% (39–80%) 11/18 | 142/168 | 64% (52–74%) 46/72 |
| google-gemini:gemini-4-argon (grader) | 34/39 | 72% (49–88%) 13/18 | 124/165 | 46% (35–57%) 33/72 |
| google-gemini:gemini-4-argon (parent) | 34/39 | 72% (49–88%) 13/18 | 142/165 | 68% (57–78%) 49/72 |
| lmstudio:google/gemma-4-26b-a4b-qat (grader) | 20/28 | 20% (6–51%) 2/10 | 135/174 | 52% (42–63%) 42/80 |
| lmstudio:google/gemma-4-26b-a4b-qat (parent) | 24/29 | 50% (24–76%) 5/10 | 144/175 | 62% (52–72%) 50/80 |
| openrouter:anthropic/claude-haiku-5.5 (parent) | – | – | 172/204 | 67% (56–76%) 60/90 |
| openrouter:deepseek/deepseek-v4-flash (parent) | – | – | 161/193 | 61% (51–71%) 51/83 |
| openrouter:deepseek/deepseek-v4-flash-0731 (parent) | – | – | 164/201 | 59% (49–68%) 53/90 |
| openrouter:inception/mercury-3 (parent) | – | – | 167/202 | 61% (50–70%) 54/89 |
| openrouter:inclusionai/ling-3.0-flash (parent) | – | – | 162/199 | 57% (47–67%) 50/87 |
| openrouter:inclusionai/ling-3.1-flash (parent) | – | – | 171/201 | 67% (56–76%) 60/90 |
| openrouter:openai/gpt-6-luna (parent) | – | – | 165/204 | 61% (51–71%) 55/90 |
| openrouter:poolside/laguna-s-2.1 (parent) | – | – | 156/193 | 55% (45–66%) 46/83 |
| openrouter:qwen/qwen3.7-flash (parent) | – | – | 165/197 | 62% (52–72%) 53/85 |
| openrouter:z-ai/glm-4.7-flash (parent) | – | – | 155/190 | 60% (49–70%) 51/85 |
